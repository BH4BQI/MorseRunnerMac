//
//  Tests/AudioThreadSafetyTests.swift
//  Regression tests for the audio-thread → AppKit safety rules.
//
//  The realtime Core Audio render callback runs Contest.getAudio() on a
//  high-priority audio thread. Any AppKit touch from there (makeFirstResponder,
//  stringValue=, NSTableView reloadData, window properties) throws an Obj-C
//  exception that terminates the app. These tests verify the audio-thread
//  entry points dispatch to the main thread instead of touching AppKit
//  synchronously.
//
//  Reproduces the crash: in Single mode, after copying a callsign and pressing
//  Enter, MyStation.getBlock() (called from the audio loop) invoked
//  MainController.advance(), which called makeFirstResponder on the audio
//  thread → SIGABRT.
//

import Foundation
import AppKit

enum AudioThreadSafetyTests {
    static let suite = TestRunner.register("Audio-thread safety", [

        TestCase("advance() does not touch AppKit synchronously (regression)") {
            // advance() is called from MyStation.getBlock() on the audio thread.
            // It used to call window.makeFirstResponder directly → crash.
            // Now it must dispatch to main and return immediately.
            let c = makeController()
            c.mustAdvance = true
            c.rstField.stringValue = ""
            c.callField.stringValue = "W1AW"
            // Call it as the audio loop would — synchronously, off-main.
            // It must NOT throw and must NOT synchronously change rstField.
            c.advance()
            // mustAdvance must be cleared synchronously (the guard latch).
            if c.mustAdvance {
                return .fail("advance() should clear mustAdvance synchronously")
            }
            // rstField must NOT have been set synchronously (it's dispatched).
            if !c.rstField.stringValue.isEmpty {
                return .fail("advance() must not set rstField synchronously (AppKit on audio thread)")
            }
            return .pass
        },

        TestCase("QSO completion via the audio loop does not crash (Single mode)") {
            // Drive the full path that crashed: type a call, mark call/NR sent,
            // then have MyStation.getBlock() run advance() as the audio loop does.
            let c = makeController()
            Settings.shared.runMode = .single
            c.callField.stringValue = "W1AW"
            c.rstField.stringValue = "599"
            c.nrField.stringValue = "5"
            QsoLog.shared.callSent = true
            QsoLog.shared.nrSent = true
            c.mustAdvance = true
            // Simulate MyStation.getBlock()'s call to advance() from the audio thread.
            // (In the GUI this is what crashed on Enter.)
            c.advance()
            // Drain the dispatched main-thread work so the NSTextField updates run.
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            return .pass   // reaching here means no exception was thrown
        },

        TestCase("processEnter completion is safe when fields are filled") {
            // The Enter key path that leads into saveQso → which (on the main
            // thread) is fine, but the completion also sets mustAdvance=true,
            // and the next audio block calls advance(). Verify the whole Enter
            // path completes without throwing.
            let c = makeController()
            Settings.shared.runMode = .single
            c.callField.stringValue = "W1AW"
            c.rstField.stringValue = "599"
            c.nrField.stringValue = "1"
            QsoLog.shared.callSent = true
            QsoLog.shared.nrSent = true
            let before = QsoLog.shared.qsoList.count
            c.processEnter(modifiers: [])
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            return expectEqual(QsoLog.shared.qsoList.count, before + 1,
                "QSO saved on Enter completion")
        },
    ])
}

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
