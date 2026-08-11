//
//  ContestTextField.swift
//  Intercepts contest keys (Space, Enter, ;.+[, etc.) in the Call/RST/NR
//  fields before they're inserted as text.
//
//  macOS text input flow: keyDown → interpretKeyEvents → insertText / doCommand
//  We intercept at the field-editor level by overriding keyDown AND
//  doCommand(by:) to catch Return/Tab/Space and forward to MainController.
//

import AppKit

/// Custom field editor that forwards contest keys to MainController.
/// Intercepts at multiple points for maximum reliability:
///   1. keyDown — catches the raw key event before text processing
///   2. doCommand(by:) — catches Enter/Tab/Backtab after text processing
final class ContestFieldEditor: NSTextView {

    public override func keyDown(with event: NSEvent) {
        // Forward ALL key events to the controller. If it consumes the key
        // (Space, ;, ., +, [, ,, Enter, arrows, function keys), we return
        // without calling super — the character is NOT inserted.
        if MainController.shared?.handleKeyEvent(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}

/// Custom cell that returns our ContestFieldEditor for contest text fields.
final class ContestTextFieldCell: NSTextFieldCell {
    override func fieldEditor(for controlView: NSView) -> NSTextView? {
        if MainController.shared?.fieldEditor == nil {
            MainController.shared?.fieldEditor = ContestFieldEditor()
        }
        return MainController.shared?.fieldEditor
    }
}

/// Text field subclass that installs ContestTextFieldCell.
final class ContestTextField: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.cell = ContestTextFieldCell()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.cell = ContestTextFieldCell()
    }
}

extension MainController {
    /// NSWindowDelegate hook — backup field editor installation.
    public func window(_ window: NSWindow,
                       willReturnFieldEditor editor: AutoreleasingUnsafeMutablePointer<NSObject?>,
                       client: Any?) -> Bool {
        // Resolve the owning NSTextField.
        let field: NSTextField?
        if let tf = client as? NSTextField { field = tf }
        else if let cell = client as? NSCell, let cv = cell.controlView as? NSTextField { field = cv }
        else { field = nil }
        guard let f = field else { return false }
        if f is ContestTextField {
            if fieldEditor == nil { fieldEditor = ContestFieldEditor() }
            editor.pointee = fieldEditor
            return true
        }
        return false
    }
}
