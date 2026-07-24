//
//  FlippedView.swift
//  A container view whose coordinate origin is the TOP-left (like the Delphi
//  VCL / Main.dfm layout we're porting). Used by buildWindow() so we can place
//  subviews using DFM "Left/Top" coordinates directly.
//

import AppKit

public final class FlippedView: NSView {
    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder: Bool { false }
}

extension NSTextField {
    /// Convenience for inline label construction: `NSTextField(labelWithString:).withFont(...)`.
    @inlinable
    func withFont(_ font: NSFont) -> NSTextField {
        self.font = font
        return self
    }
}
