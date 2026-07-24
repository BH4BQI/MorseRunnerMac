//
//  MainWindowClass.swift
//  A custom NSWindow that replicates Delphi's `KeyPreview = True`: the window
//  inspects every key before the focused control. Function keys (F1-F8),
//  navigation keys, and the special contest characters (Enter, Space, ;, ., +,
//  [, ,) are intercepted here and dispatched to MainController; ordinary typing
//  falls through to the focused text field.
//
//  Two overrides cover the full path:
//   - performKeyEquivalent: runs before any control sees the event. Used for
//     function keys, which NSTextField otherwise swallows/ignores.
//   - keyDown: runs after the first responder refuses. Used for printable
//     characters and Enter/Space/Escape.
//
//  The window's contentView is a FlippedContentView: its coordinate origin is
//  the TOP-LEFT (like Delphi VCL / Main.dfm). This lets buildWindow() place the
//  three region containers (leftMain/rightCol/bottom) using DFM "Top=" coords
//  directly — Top=0 is the top of the window, Top=335 is near the bottom.
//

import AppKit

/// The window's content view, flipped so its origin is top-left. All region
/// containers are placed in this view using DFM-style top-left coordinates.
/// Draws the window background explicitly so the area behind group boxes and
/// transparent panels matches the current theme (light/dark) rather than the
/// opaque-black default of a layer-backed view.
final class FlippedContentView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

public final class MainWindowClass: NSWindow {

    public override func keyDown(with event: NSEvent) {
        if MainController.shared?.handleKeyEvent(event) == true { return }
        super.keyDown(with: event)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Function keys, PgUp/Dn, arrows, F11 — intercept here so they work even
        // while a text field has focus.
        let kc = event.keyCode
        let functionKey: Set<UInt16> = [
            0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64,   // F1-F8
            0x65, 0x6D, 0x67,                                    // F9, F10, F11
            0x74, 0x79,                                          // PgUp, PgDn
            0x7E, 0x7D,                                          // Up, Down arrows
            0x35,                                                // Escape
        ]
        if functionKey.contains(kc) {
            if MainController.shared?.handleKeyEvent(event) == true { return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Don't beep on keys we don't recognize as text input — pass through silently.
    public override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
    }
}
