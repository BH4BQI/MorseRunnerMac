//
//  Tests/RunButtonTests.swift
//  Tests for the Run button's toggle/dropdown/reset behaviour, matching the
//  original ToolButton1 + RunMNUClick + Run().
//

import Foundation
import AppKit

enum RunButtonTests {
    static let suite = TestRunner.register("Run button (toggle/reset)", [

        TestCase("run button title flips to 'Stop' when running, back to 'Run' on stop") {
            let c = makeController()
            Settings.shared.runMode = .stop   // ensure clean start (suite-level state)
            c.run(.pileUp)
            if c.runButton.title != "Stop" {
                return .fail("button title while running should be 'Stop', got \"\(c.runButton.title)\"")
            }
            c.run(.stop)
            return expectEqual(c.runButton.title, "Run", "button title after stop")
        },

        TestCase("runClicked toggles: start when stopped, stop when running") {
            let c = makeController()
            Settings.shared.runMode = .stop
            // stopped → click starts Pile-Up.
            c.runClicked()
            if Settings.shared.runMode != .pileUp {
                return .fail("runClicked while stopped should start Pile-Up")
            }
            // running → click stops.
            c.runClicked()
            // Stop is asynchronous via fStopPressed in the GUI; force-stop here.
            c.run(.stop)
            return expectEqual(Settings.shared.runMode, .stop, "runMode after stop")
        },

        TestCase("re-running after stop is a fresh session, not a resume") {
            // The user's specific concern: after stopping, re-Run must RESET
            // (empty log, NR=1, blockNumber small again), not continue from
            // where it stopped.
            let c = makeController()
            Settings.shared.runMode = .stop
            c.run(.pileUp)
            // Pretend a QSO and some elapsed time.
            Tst.blockNumber = 12345
            QsoLog.shared.saveQso(callField: "W1AW", rstField: "599", nrField: "1")
            if QsoLog.shared.qsoList.count == 0 {
                return .fail("sanity: QSO should have been logged before stop")
            }
            // Stop, then run again. run() resets blockNumber to 0 and clears
            // sessionEnding before the audio engine's prefill runs.
            c.run(.stop)
            c.run(.pileUp)
            let bn = Tst.blockNumber
            return expectAll(
                expectTrue(bn < 100, "blockNumber reset (got \(bn), expected < 100"),
                expectEqual(QsoLog.shared.qsoList.count, 0, "QSO log cleared"),
                expectEqual(Tst.me.nr, 1, "NR reset to 1"),
                expectFalse(Tst.fStopPressed, "fStopPressed cleared")
            )
        },

        TestCase("dropdown selection starts the chosen mode") {
            let c = makeController()
            let item = NSMenuItem(title: "Single Calls", action: nil, keyEquivalent: "")
            item.tag = RunMode.single.rawValue
            c.runMenuClicked(item)
            return expectEqual(Settings.shared.runMode, .single, "mode from dropdown")
        },

        TestCase("dropdown Stop item triggers fStopPressed") {
            let c = makeController()
            c.run(.pileUp)
            Tst.fStopPressed = false
            let item = NSMenuItem(title: "Stop", action: nil, keyEquivalent: "")
            item.tag = RunMode.stop.rawValue
            c.runMenuClicked(item)
            return expectTrue(Tst.fStopPressed, "dropdown Stop sets fStopPressed")
        },

        TestCase("WPX mode respects the user's Duration setting") {
            // The user sets Duration=10 via the menu; WPX must use that value,
            // not force compDuration (60).
            let c = makeController()
            Settings.shared.runMode = .stop
            Settings.shared.duration = 10
            Settings.shared.compDuration = 60
            c.run(.wpx)
            return expectEqual(Settings.shared.duration, 10,
                "WPX should keep the user's Duration (10), not override with compDuration (60)")
        },
    ])
}

private func makeController() -> MainController {
    if Contest.shared == nil { _ = Contest() }
    makeKeyer()
    let c = MainController()
    MainController.shared = c
    Tst.initContest()
    QsoLog.shared.clear()
    return c
}

private func expectAll(_ results: TestResult...) -> TestResult {
    for r in results { if case .fail(let m) = r { return .fail(m) } }
    return .pass
}
