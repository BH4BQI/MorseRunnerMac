//
//  Tests/DxOperatorTests.swift
//  Verifies the DX operator's callsign-matching state machine (Levenshtein
//  with '?' wildcards) — Yes/Almost/No classification for replies.
//

import Foundation

enum DxOperatorTests {
    static let suite = TestRunner.register("DxOperator", [
        TestCase("exact call match → yes") {
            let op = makeOp(realCall: "W1AW")
            Tst.me.hisCall = "W1AW"
            return expectEqual(op.isMyCall(), .yes, "isMyCall")
        },

        TestCase("wildcard match → almost") {
            let op = makeOp(realCall: "W1AW")
            Tst.me.hisCall = "W?AW"
            return expectEqual(op.isMyCall(), .almost, "isMyCall")
        },

        TestCase("one char off → almost") {
            let op = makeOp(realCall: "W1AW")
            Tst.me.hisCall = "W1AB"
            return expectEqual(op.isMyCall(), .almost, "isMyCall")
        },

        TestCase("different call → no") {
            let op = makeOp(realCall: "W1AW")
            Tst.me.hisCall = "Z9ZZZ"
            return expectEqual(op.isMyCall(), .no, "isMyCall")
        },

        TestCase("too-short partial → no") {
            let op = makeOp(realCall: "W1AW")
            Tst.me.hisCall = "W????"   // only 1 real char
            return expectEqual(op.isMyCall(), .no, "isMyCall")
        },
    ])
}

private func makeOp(realCall: String) -> DxOperator {
    if Contest.shared == nil { _ = Contest() }
    // LIDS randomly flips almost↔yes for long calls — disable it so the
    // matching tests are deterministic.
    Settings.shared.lids = false
    let op = DxOperator()
    op.call = realCall
    op.skills = 1
    return op
}
