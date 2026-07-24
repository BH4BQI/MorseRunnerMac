//
//  Histo.swift
//  Port of Log.pas — THisto.
//
//  Renders the 5-minute QSO-rate histogram. 48 bars cover a 4-hour window.
//

import AppKit

public final class Histo {
    public private(set) var duration: Int = 30
    private var counts: [Int] = [Int](repeating: 0, count: 48)
    private weak var view: NSView?

    /// Test/diagnostic accessor for the per-bucket QSO counts.
    public var countsForTest: [Int] { counts }

    public init(view: NSView? = nil) {
        self.view = view
    }

    public func setView(_ view: NSView) { self.view = view }

    public func reCalc(_ duration: Int) {
        self.duration = duration
    }

    public func repaint() {
        // recompute histogram from the QSO log
        counts = [Int](repeating: 0, count: 48)
        for q in QsoLog.shared.qsoList {
            let bucket = Int(q.t * 1440) / 5
            if bucket >= 0 && bucket < counts.count {
                counts[bucket] += 1
            }
        }
        view?.needsDisplay = true
    }

    /// Draw the histogram into the given rect.
    ///
    /// The hosting view (HistogramView) is flipped (origin top-left, like the
    /// original Delphi VCL PaintBox). The original computes
    ///   y := Height - 3 - Histo[i] * 2;   FillRect(Rect(x, y, x+w-1, Height-2))
    /// i.e. bars grow upward from the bottom. We replicate that exactly, and
    /// add a light baseline + grid so the bars are visible even at low counts
    /// (the previous version filled from the top edge and was nearly invisible).
    public func draw(in rect: NSRect) {
        // Background — use a slightly lighter panel color so the green bars
        // and the baseline read clearly against it (the default window
        // background is nearly black in dark mode).
        NSColor.controlBackgroundColor.setFill()
        rect.fill()

        guard !counts.isEmpty else {
            drawBaseline(in: rect)
            return
        }

        let n = counts.count
        let w = Int(rect.width) / n
        let height = rect.height
        // Bars sit on a baseline near the bottom; height grows upward.
        // (In a flipped view "up" = smaller Y, matching the VCL math.)
        let bottomInset: CGFloat = 3
        let barTop: (Int) -> CGFloat = { c in
            // original: y = Height - 3 - Histo[i]*2 ; bar spans [y, Height-2]
            // → in flipped coords the bar's TOP edge is at (Height - 3 - c*2).
            rect.minY + (height - bottomInset - CGFloat(c * 2))
        }
        let barBottom = rect.minY + (height - 2)

        // Grid: a couple of faint horizontal reference lines.
        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        let gridPath = NSBezierPath()
        gridPath.lineWidth = 0.5
        for frac in [0.25, 0.5, 0.75] {
            let gy = rect.minY + height * frac
            gridPath.move(to: NSPoint(x: rect.minX, y: gy))
            gridPath.line(to: NSPoint(x: rect.maxX, y: gy))
        }
        gridPath.stroke()

        // Bars.
        for (i, c) in counts.enumerated() {
            let x = Int(rect.minX) + i * w
            if c <= 0 { continue }
            let topY = barTop(c)
            let barRect = NSRect(x: CGFloat(x) + 1,
                                 y: topY,
                                 width: CGFloat(max(1, w - 2)),
                                 height: max(2, barBottom - topY))
            NSColor.systemGreen.setFill()
            barRect.fill()
        }

        drawBaseline(in: rect)
    }

    private func drawBaseline(in rect: NSRect) {
        NSColor.separatorColor.setStroke()
        let baseline = NSBezierPath()
        baseline.lineWidth = 1
        let y = rect.maxY - 2
        baseline.move(to: NSPoint(x: rect.minX, y: y))
        baseline.line(to: NSPoint(x: rect.maxX, y: y))
        baseline.stroke()
    }
}
