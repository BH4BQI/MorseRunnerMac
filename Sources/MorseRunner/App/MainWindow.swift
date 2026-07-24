//
//  MainWindow.swift
//  Rebuilds the Main.dfm layout in AppKit.
//
//  Layout (matching the original):
//   ┌─────────────────────────────────────────────────────────────┐
//   │ top: settings panel (left)  │  operating area (right)        │
//   │   - My Call / WPM / Pitch   │  - Call / RST / NR fields      │
//   │   - Bandwidth / QSK         │  - F1..F8 message buttons      │
//   │   - Activity / Duration     │  - RIT indicator + clock       │
//   │   - QRM/QRN/QSB/Fltr/LIDS   │  - mode + pile-up + rate       │
//   │   - self-monitor volume     │                                │
//   ├─────────────────────────────────────────────────────────────┤
//   │ bottom: QSO log table | score columns | 5-min histogram      │
//   └─────────────────────────────────────────────────────────────┘
//

import AppKit

/// View that draws the 5-minute QSO-rate histogram.
public final class HistogramView: NSView {
    public weak var histo: Histo?

    public override var isFlipped: Bool { true }
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
    }
    required init?(coder: NSCoder) { fatalError() }

    public override func draw(_ dirtyRect: NSRect) {
        histo?.draw(in: bounds)
    }
}

/// View that draws the RIT (receiver incremental tuning) indicator.
public final class RitIndicatorView: NSView {
    public var bandWidth: Int = 500
    public var rit: Int = 0

    public override init(frame frameRect: NSRect) { super.init(frame: frameRect) }
    required init?(coder: NSCoder) { fatalError() }

    public override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        let w = max(1, bandWidth / 9)
        let cx = Int(bounds.midX)
        let ritOffset = rit / 9
        let barRect = NSRect(x: CGFloat(cx + ritOffset - w / 2),
                             y: bounds.minY + 4,
                             width: CGFloat(w), height: bounds.height - 8)
        NSColor.systemBlue.setFill()
        barRect.fill()
    }

    public func hitTestRit(_ location: NSPoint) -> Int {
        // -1 if click left of bar, +1 if right, 0 if on the bar.
        let w = max(1, bandWidth / 9)
        let cx = bounds.midX
        let ritOffset = CGFloat(rit / 9)
        let left = cx + ritOffset - CGFloat(w) / 2
        let right = left + CGFloat(w)
        if location.x < left { return -1 }
        if location.x > right { return 1 }
        return 0
    }
}
