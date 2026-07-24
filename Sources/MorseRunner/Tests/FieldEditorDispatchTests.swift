//
//  Tests/FieldEditorDispatchTests.swift
//  Verifies the field-editor command dispatch (control(_:textView:doCommandBy:)),
//  which is the mechanism that makes "Enter while a field has focus → CQ" work
//  in the GUI. The field editor forwards Return/Esc to the controller before
//  treating them as text.
//

import Foundation
import AppKit

enum FieldEditorDispatchTests {
    static let suite = TestRunner.register("Field-editor dispatch (GUI)", [

        TestCase("doCommandBy insertNewline: with empty call → sends CQ") {
            // This is the exact GUI path: NSTextField's field editor calls
            // control(_:textView:doCommandBy:) with insertNewline: on Return.
            let c = makeController()
            c.callField.stringValue = ""
            let consumed = c.control(c.callField, textView: NSTextView(),
                                     doCommandBy: #selector(NSResponder.insertNewline(_:)))
            return expectAll(
                expectTrue(consumed, "Return should be consumed (not inserted as newline)"),
                expectTrue(Tst.me.msg.contains(.cq), "Return on empty call sends CQ")
            )
        },

        TestCase("doCommandBy insertNewline: with call+NR → sends TU and saves") {
            // Full completion path via the field-editor dispatch.
            let c = makeController()
            c.callField.stringValue = "W1AW"
            c.rstField.stringValue = "599"
            c.nrField.stringValue = "7"
            QsoLog.shared.callSent = true
            QsoLog.shared.nrSent = true
            let before = QsoLog.shared.qsoList.count
            let consumed = c.control(c.callField, textView: NSTextView(),
                                     doCommandBy: #selector(NSResponder.insertNewline(_:)))
            return expectAll(
                expectTrue(consumed, "Return consumed"),
                expectEqual(QsoLog.shared.qsoList.count, before + 1, "QSO saved"),
                expectTrue(Tst.me.msg.contains(.tu), "TU sent")
            )
        },

        TestCase("doCommandBy cancelOperation: (Esc) aborts the send") {
            let c = makeController()
            c.callField.stringValue = "W1AW"
            c.sendMsg(.hisCall)
            QsoLog.shared.callSent = true
            _ = c.control(c.callField, textView: NSTextView(),
                          doCommandBy: #selector(NSResponder.cancelOperation(_:)))
            return expectTrue(!QsoLog.shared.callSent, "Esc resets callSent")
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

private func expectAll(_ results: TestResult...) -> TestResult {
    for r in results { if case .fail(let m) = r { return .fail(m) } }
    return .pass
}
