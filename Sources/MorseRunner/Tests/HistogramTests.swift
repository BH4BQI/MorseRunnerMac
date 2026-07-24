//
//  Tests/HistogramTests.swift
//  Tests for the 5-minute QSO-rate histogram.
//
//  Two bugs previously made the histogram invisible:
//   1. Histo.counts was only recomputed in repaint(), but nothing called it —
//      scoreViewSetNeedsDisplay only set needsDisplay, so bars always read zero.
//   2. HistogramView.histo back-reference was never wired, so draw() rendered
//      nothing even when counts were correct.
//

import Foundation
import AppKit

enum HistogramTests {
    static let suite = TestRunner.register("Histogram", [

        TestCase("repaint() recomputes counts from the QSO log") {
            let h = Histo()
            bootstrap()
            QsoLog.shared.clear()
            // Log 3 QSOs all in the first 5-minute bucket (t < 5/1440 day).
            for nr in 1...3 {
                QsoLog.shared.saveQso(callField: "W\(nr)AW", rstField: "599",
                                      nrField: String(nr))
            }
            h.repaint()
            // First bucket should hold all 3 (t is tiny at session start).
            let total = h.countsForTest.reduce(0, +)
            return expectEqual(total, 3, "histogram counts sum to 3 QSOs")
        },

        TestCase("empty log → all-zero counts (no bars)") {
            let h = Histo()
            bootstrap()
            QsoLog.shared.clear()
            h.repaint()
            let total = h.countsForTest.reduce(0, +)
            return expectEqual(total, 0, "empty log → zero counts")
        },

        TestCase("scoreViewSetNeedsDisplay triggers a recompute via the controller") {
            // End-to-end: saving a QSO should update the histogram through the
            // delegate path. Build a controller so the delegate is wired.
            let c = makeController()
            QsoLog.shared.clear()
            c.histo.repaint()
            let before = c.histo.countsForTest.reduce(0, +)
            QsoLog.shared.saveQso(callField: "W1AW", rstField: "599", nrField: "1")
            QsoLog.shared.updateStats()   // calls delegate.scoreViewSetNeedsDisplay
            // The delegate dispatches to main; run the loop to drain it.
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            let after = c.histo.countsForTest.reduce(0, +)
            return expectEqual(after, before + 1,
                "histogram updated via delegate after a QSO")
        },
    ])
}

private func bootstrap() {
    if Contest.shared == nil { _ = Contest() }
    makeKeyer()
    Settings.shared.runMode = .pileUp
    Tst.initContest()
}

private func makeController() -> MainController {
    let c = MainController()
    MainController.shared = c
    return c
}

private func expectAll(_ results: TestResult...) -> TestResult {
    for r in results { if case .fail(let m) = r { return .fail(m) } }
    return .pass
}
