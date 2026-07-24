//
//  Tests/ESMFlowTests.swift
//  Tests for the ESM (Enter Sends Messages) state machine and the F-key
//  message dispatch — the exact behaviours VE3NEA's Main.pas implements.
//
//  We observe what was "sent" via Tst.me.msg (the bitmask of sent messages)
//  and Tst.me.msgText (the expanded CW body) after each action.
//

import Foundation
import AppKit

enum ESMFlowTests {
    static let suite = TestRunner.register("ESM flow (Main.pas)", [

        TestCase("Enter with empty call field sends CQ") {
            // Main.pas ProcessEnter: "no QSO in progress, send CQ".
            let c = makeController()
            c.callField.stringValue = ""
            c.processEnter(modifiers: [])
            return expectTrue(Tst.me.msg.contains(.cq),
                "Enter on empty call should send CQ")
        },

        TestCase("Enter with a call but nothing sent → sends his-call + NR") {
            // ProcessEnter: C=false, N=false, R=false → send his-call then NR.
            let c = makeController()
            c.callField.stringValue = "W1AW"
            c.rstField.stringValue = ""
            c.nrField.stringValue = ""
            QsoLog.shared.callSent = false
            QsoLog.shared.nrSent = false
            c.processEnter(modifiers: [])
            return expectAll(
                expectTrue(Tst.me.msg.contains(.hisCall), "sent his-call"),
                expectTrue(Tst.me.msg.contains(.nr), "sent NR")
            )
        },

        TestCase("F5 (his-call) sets CallSent; F2 (NR) sets NrSent") {
            // Main.pas SendMsg: msgHisCall → CallSent:=true; msgNR → NrSent:=true.
            let c = makeController()
            c.callField.stringValue = "W1AW"
            QsoLog.shared.callSent = false
            QsoLog.shared.nrSent = false
            c.sendMsg(.hisCall)
            if !QsoLog.shared.callSent { return .fail("F5 should set callSent") }
            c.sendMsg(.nr)
            return expectTrue(QsoLog.shared.nrSent, "F2 should set nrSent")
        },

        TestCase("F4 (my-call) does NOT set CallSent") {
            // Only msgHisCall sets CallSent — msgMyCall must not.
            let c = makeController()
            QsoLog.shared.callSent = false
            c.sendMsg(.myCall)
            return expectTrue(!QsoLog.shared.callSent,
                "F4 (my-call) must not set callSent")
        },

        TestCase("F-key dispatch: F1..F8 map to the original messages") {
            // Verify the mapping table the keyboard handler uses:
            //   F1 CQ, F2 NR, F3 TU, F4 myCall, F5 hisCall, F6 B4, F7 ?, F8 NIL.
            // (Matching the original Main.dfm button tags 1..8.)
            let c = makeController()
            c.callField.stringValue = "W1AW"
            Tst.me.myCall = "BH4BQI"
            let mapping: [(UInt16, String, StationMessages)] = [
                (0x7A, "F1", .cq),
                (0x78, "F2", .nr),
                (0x63, "F3", .tu),
                (0x76, "F4", .myCall),
                (0x60, "F5", .hisCall),
                (0x61, "F6", .b4),
                (0x62, "F7", .qm),
                (0x64, "F8", .nilMsg),
            ]
            for (kc, name, flag) in mapping {
                Tst.me.msg = .none   // clear before each
                let event = NSEvent.keyEvent(with: .keyDown, location: .zero,
                    modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                    characters: "", charactersIgnoringModifiers: "",
                    isARepeat: false, keyCode: kc)!
                _ = c.handleKeyEvent(event)
                if !Tst.me.msg.contains(flag) {
                    return .fail("\(name) (kc 0x\(String(kc, radix: 16))) should set \(flag), msg=\(Tst.me.msg.rawValue)")
                }
            }
            return .pass
        },

        TestCase("';' sends his-call + NR (Insert equivalent)") {
            let c = makeController()
            c.callField.stringValue = "W1AW"
            QsoLog.shared.callSent = false
            QsoLog.shared.nrSent = false
            Tst.me.msg = .none
            _ = c.handleKeyEvent(keyEvent(char: ";"))
            return expectAll(
                expectTrue(Tst.me.msg.contains(.hisCall), "; sends his-call"),
                expectTrue(Tst.me.msg.contains(.nr), "; sends NR")
            )
        },

        TestCase("'.' / '+' / '[' / ',' send TU + save the QSO") {
            // Main.pas FormKeyPress: '.', '+', '[', ',' → if not CallSent send
            // his-call, then TU, then Log.SaveQso.
            for ch in [".", "+", "[", ","] {
                let c = makeController()
                c.callField.stringValue = "W1AW"
                c.rstField.stringValue = "599"
                c.nrField.stringValue = "1"
                QsoLog.shared.callSent = false
                QsoLog.shared.nrSent = false
                let before = QsoLog.shared.qsoList.count
                _ = c.handleKeyEvent(keyEvent(char: ch))
                let after = QsoLog.shared.qsoList.count
                if after != before + 1 {
                    return .fail("'\(ch)' should save a QSO (count \(before)→\(after))")
                }
            }
            return .pass
        },

        TestCase("Esc aborts the current send") {
            // Main.pas: Esc → AbortSend; reset CallSent/NrSent if those were sent.
            let c = makeController()
            c.callField.stringValue = "W1AW"
            c.sendMsg(.hisCall)
            QsoLog.shared.callSent = true
            _ = c.handleKeyEvent(keyEvent(keyCode: 0x35))  // Esc
            return expectTrue(!QsoLog.shared.callSent,
                "Esc should reset callSent (was sending his-call)")
        },

        TestCase("F3 + Enter completes a QSO and the call lands in the log") {
            // Full happy path: type call, enter NR, then Enter → TU + save.
            // The DX call must appear in the QSO log.
            let c = makeController()
            c.callField.stringValue = "W1AW"
            c.rstField.stringValue = "599"
            c.nrField.stringValue = "42"
            QsoLog.shared.callSent = true   // pretend we already sent his-call
            QsoLog.shared.nrSent = true     // and NR
            let before = QsoLog.shared.qsoList.count
            c.processEnter(modifiers: [])
            let after = QsoLog.shared.qsoList.count
            return expectAll(
                expectEqual(after, before + 1, "QSO saved"),
                expectEqual(QsoLog.shared.qsoList.last?.call, "W1AW", "logged call"),
                expectTrue(Tst.me.msg.contains(.tu), "TU sent on completion")
            )
        },
    ])
}

// MARK: - test helpers

/// Build a headless MainController for the ESM tests.
private func makeController() -> MainController {
    if Contest.shared == nil { _ = Contest() }
    makeKeyer()
    let c = MainController()
    MainController.shared = c
    Settings.shared.runMode = .pileUp
    Tst.initContest()
    QsoLog.shared.clear()
    return c
}

private func keyEvent(char: String = "", keyCode: UInt16 = 0) -> NSEvent {
    return NSEvent.keyEvent(with: .keyDown, location: .zero,
        modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
        characters: char, charactersIgnoringModifiers: char,
        isARepeat: false, keyCode: keyCode)!
}

private func expectAll(_ results: TestResult...) -> TestResult {
    for r in results { if case .fail(let m) = r { return .fail(m) } }
    return .pass
}
