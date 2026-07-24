//
//  MainController+Keys.swift
//  Port of Main.pas — keyboard handling (FormKeyDown / FormKeyPress).
//
//  The original relied on Delphi's KeyPreview; we intercept keys at the window
//  level via a custom content-view subclass. Function keys, navigation, and
//  special characters are handled here; ordinary typing still reaches the
//  focused text field.
//

import AppKit

public let sVersion = "1.71 (macOS)"

extension MainController {

    /// Returns true if the key was consumed here.
    @discardableResult
    func handleKeyEvent(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Function keys — mapping matches the original Main.dfm button tags
        // (SpeedButton4..11 → TStationMessage 1..8):
        //   F1 CQ, F2 <#>(NR), F3 TU, F4 <my>, F5 <his>, F6 B4, F7 ?, F8 NIL.
        switch event.keyCode {
        case kVK_F1: sendMsg(.cq); return true
        case kVK_F2: sendMsg(.nr); return true
        case kVK_F3: sendMsg(.tu); return true
        case kVK_F4: sendMsg(.myCall); return true
        case kVK_F5: sendMsg(.hisCall); return true
        case kVK_F6: sendMsg(.b4); return true
        case kVK_F7: sendMsg(.qm); return true
        case kVK_F8: sendMsg(.nilMsg); return true
        case kVK_Escape:
            // abort send
            if Tst.me.msg.contains(.hisCall) { QsoLog.shared.callSent = false }
            if Tst.me.msg.contains(.nr) { QsoLog.shared.nrSent = false }
            Tst.me.abortSend()
            return true
        default: break
        }

        // Special characters and navigation via characters.
        let chars = event.charactersIgnoringModifiers ?? ""

        if chars == "\r" || chars == "\n" {
            // Enter / Return — ESM logic. Pass modifiers so Ctrl/Shift/Alt+Enter
            // saves the QSO directly.
            processEnter(modifiers: mods)
            return true
        }

        // Ctrl-W / Alt-W = wipe
        if (mods.contains(.control) || mods.contains(.option)) && chars.lowercased() == "w" {
            wipeBoxes()
            return true
        }
        // F11 = wipe
        if event.keyCode == kVK_F11 { wipeBoxes(); return true }

        // ';' = his-call + NR
        if chars == ";" {
            sendMsg(.hisCall); sendMsg(.nr); return true
        }
        // '.' '+' ',' '[' = TU + save
        if chars == "." || chars == "+" || chars == "," || chars == "[" {
            if !QsoLog.shared.callSent { sendMsg(.hisCall) }
            sendMsg(.tu)
            saveQso()
            return true
        }

        // Space = field advance
        if chars == " " {
            processSpace()
            return true
        }

        // PageUp/PageDn = speed
        if event.keyCode == kVK_PageUp { incSpeed(); return true }
        if event.keyCode == kVK_PageDown { decSpeed(); return true }

        // Arrow Up/Down = RIT (or bandwidth with Ctrl)
        if event.keyCode == kVK_UpArrow {
            if mods.contains(.control) {
                if Settings.shared.runMode != .hst { setBw(bandwidthPopup.indexOfSelectedItem + 1) }
            } else {
                incRit(1)
            }
            return true
        }
        if event.keyCode == kVK_DownArrow {
            if mods.contains(.control) {
                if Settings.shared.runMode != .hst { setBw(bandwidthPopup.indexOfSelectedItem - 1) }
            } else {
                incRit(-1)
            }
            return true
        }

        // F9/F10 with Alt or Ctrl = speed
        if (event.keyCode == kVK_F9) && (mods.contains(.control) || mods.contains(.option)) {
            decSpeed(); return true
        }
        if (event.keyCode == kVK_F10) && (mods.contains(.control) || mods.contains(.option)) {
            incSpeed(); return true
        }

        return false
    }

    private func processSpace() {
        mustAdvance = false
        let firstResponder = window.firstResponder
        if firstResponder === callField.currentEditor() {
            if rstField.stringValue.isEmpty { rstField.stringValue = "599" }
            window.makeFirstResponder(nrField)
        } else if firstResponder === rstField.currentEditor() {
            if rstField.stringValue.isEmpty { rstField.stringValue = "599" }
            window.makeFirstResponder(nrField)
        } else {
            window.makeFirstResponder(callField)
        }
    }
}

// Virtual key codes used above (not all exported by Carbon on arm64).
private let kVK_F1: UInt16 = 0x7A
private let kVK_F2: UInt16 = 0x78
private let kVK_F3: UInt16 = 0x63
private let kVK_F4: UInt16 = 0x76
private let kVK_F5: UInt16 = 0x60
private let kVK_F6: UInt16 = 0x61
private let kVK_F7: UInt16 = 0x62
private let kVK_F8: UInt16 = 0x64
private let kVK_F9: UInt16 = 0x65
private let kVK_F10: UInt16 = 0x6D
private let kVK_F11: UInt16 = 0x67
private let kVK_Escape: UInt16 = 0x35
private let kVK_PageUp: UInt16 = 0x74
private let kVK_PageDown: UInt16 = 0x79
private let kVK_UpArrow: UInt16 = 0x7E
private let kVK_DownArrow: UInt16 = 0x7D
