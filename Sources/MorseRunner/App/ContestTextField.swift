//
//  ContestTextField.swift
//  An NSTextField subclass that lets the MainController intercept contest
//  command keys (Enter, Space, ;, ., +, [, ,, Esc) BEFORE the field editor
//  handles them as text.
//
//  Problem: in AppKit, when a text field has focus its field editor is the
//  first responder and consumes Return/Enter/Space/printable characters as
//  text input — they never reach the window's keyDown (which is why
//  "Enter-on-empty-call sends CQ" didn't work in the GUI). Delphi's
//  `KeyPreview = True` inspects every key before the focused control; the
//  macOS equivalent is to forward these specific keys from the field editor
//  up the responder chain to the controller.
//
//  We do it by overriding the field editor's behaviour via a custom
//  NSTextView (the field editor) installed through the window delegate's
//  `windowWillReturnFieldEditor`. That field editor forwards command keys to
//  MainController.handleKeyEvent; if the controller consumes the event, it
//  is not inserted as text.
//

import AppKit

/// A field-editor NSTextView that forwards contest command keys to the
/// MainController before treating them as text.
final class ContestFieldEditor: NSTextView {

    public override func keyDown(with event: NSEvent) {
        // Give the controller first crack at contest command keys.
        if MainController.shared?.handleKeyEvent(event) == true {
            return   // consumed — don't insert into the field
        }
        super.keyDown(with: event)
    }
}

/// Marker protocol so the window delegate knows to provide a ContestFieldEditor
/// for these fields. Attached to the Call/RST/NR fields via their delegate.
protocol ContestFieldProtocol: NSTextFieldDelegate {}

extension MainController {
    /// NSWindowDelegate hook: return a custom field editor for the contest
    /// input fields so command keys reach the controller before being inserted
    /// as text. This is the macOS equivalent of Delphi's `KeyPreview = True`
    /// for printable/Enter/Space keys.
    public func window(_ window: NSWindow,
                       willReturnFieldEditor editor: AutoreleasingUnsafeMutablePointer<NSObject?>,
                       client: Any?) -> Bool {
        // The `client` can be an NSCell (not the NSTextField itself). Resolve
        // to the owning NSTextField via the cell's controlView.
        let field: NSTextField?
        if let tf = client as? NSTextField {
            field = tf
        } else if let cell = client as? NSCell, let cv = cell.controlView as? NSTextField {
            field = cv
        } else {
            field = nil
        }
        guard let f = field else { return false }
        if f === callField || f === rstField || f === nrField {
            if fieldEditor == nil {
                fieldEditor = ContestFieldEditor()
            }
            editor.pointee = fieldEditor
            return true
        }
        return false
    }
}
