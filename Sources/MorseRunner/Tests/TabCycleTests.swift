//
//  Tests/TabCycleTests.swift
//  Tests for Tab / Shift-Tab field cycling — the original VCL form used
//  TabOrder 0/1/2 on the Call/RST/NR fields; we cycle them so the cursor stays
//  in the contest fields and you can Tab back to Call to correct a callsign.
//

import Foundation
import AppKit

enum TabCycleTests {
    static let suite = TestRunner.register("Tab field cycling", [

        TestCase("Tab from Call → RST → NR → Call (cycle)") {
            let c = makeController()
            c.rstField.stringValue = ""   // RST empty so we also test auto-fill
            c.window.makeFirstResponder(c.callField)

            c.moveFocus(forward: true)
            if !isFocused(c.rstField, in: c.window) {
                return .fail("Tab from Call should focus RST")
            }
            if c.rstField.stringValue != "599" {
                return .fail("RST should auto-fill '599' on entry, got \"\(c.rstField.stringValue)\"")
            }
            c.moveFocus(forward: true)
            if !isFocused(c.nrField, in: c.window) {
                return .fail("Tab from RST should focus NR")
            }
            // Tab from NR must wrap back to Call (the user's requirement: be
            // able to return to the Call field to fix the callsign).
            c.moveFocus(forward: true)
            return expectTrue(isFocused(c.callField, in: c.window),
                "Tab from NR must cycle back to Call")
        },

        TestCase("Shift-Tab cycles backward (Call → NR → RST → Call)") {
            let c = makeController()
            c.rstField.stringValue = "599"
            c.window.makeFirstResponder(c.callField)

            c.moveFocus(forward: false)
            if !isFocused(c.nrField, in: c.window) {
                return .fail("Shift-Tab from Call should focus NR")
            }
            c.moveFocus(forward: false)
            if !isFocused(c.rstField, in: c.window) {
                return .fail("Shift-Tab from NR should focus RST")
            }
            c.moveFocus(forward: false)
            return expectTrue(isFocused(c.callField, in: c.window),
                "Shift-Tab from RST should focus Call")
        },

        TestCase("doCommandBy insertTab: / insertBacktab: dispatch to cycling") {
            // The real GUI path: the field editor forwards Tab/Shift-Tab here.
            let c = makeController()
            c.rstField.stringValue = "599"
            c.window.makeFirstResponder(c.callField)

            let consumed = c.control(c.callField, textView: NSTextView(),
                                     doCommandBy: #selector(NSResponder.insertTab(_:)))
            if !consumed || !isFocused(c.rstField, in: c.window) {
                return .fail("insertTab: should move focus to RST (consumed=\(consumed))")
            }
            let consumed2 = c.control(c.rstField, textView: NSTextView(),
                                      doCommandBy: #selector(NSResponder.insertBacktab(_:)))
            return expectTrue(consumed2 && isFocused(c.callField, in: c.window),
                "insertBacktab: should move focus back to Call")
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

/// Is `field` the currently-focused control (its field editor is first responder)?
private func isFocused(_ field: NSTextField, in window: NSWindow) -> Bool {
    if let editor = field.currentEditor(), editor === window.firstResponder { return true }
    return false
}
