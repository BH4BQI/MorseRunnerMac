//
//  Tests/MyStationTests.swift
//  Regression tests for MyStation — especially updateCallInMessage, which
//  crashed (range trap, MyStation.swift:123) when the user typed in the call
//  field while no callsign piece was queued.
//

import Foundation

enum MyStationTests {
    static let suite = TestRunner.register("MyStation", [
        TestCase("updateCallInMessage does not crash when idle (regression)") {
            // Regression: previously `1..<pieces.count` trapped when pieces
            // was empty (count == 0). This is the exact user crash path:
            // type a char in the call field while nothing is being sent.
            let s = makeIdleStation()
            guard s.piecesCount == 0, !s.isSendingCallsign else {
                return .skip("precondition not met")
            }
            let result = s.updateCallInMessage("W1A")
            return expectFalse(result, "no queued callsign → nothing to correct")
        },

        TestCase("incremental typing W → W1 → W1A is safe (regression)") {
            let s = makeIdleStation()
            for partial in ["W", "W1", "W1A", "W1AW"] {
                _ = s.updateCallInMessage(partial)   // must not trap
            }
            return .pass
        },

        TestCase("empty call returns false") {
            let s = makeIdleStation()
            return expectFalse(s.updateCallInMessage(""), "empty input should short-circuit")
        },

        TestCase("queued '@' piece is found and call is stored") {
            let s = makeIdleStation()
            s.hisCall = "TEST"
            s.sendText("DE <my> <his>")  // queues pieces incl. '@'
            let result = s.updateCallInMessage("W1A")
            if result != true { return .fail("expected queued call to be found") }
            return expectEqual(s.hisCall, "W1A", "hisCall")
        },
    ])
}

/// Shared helper: a fresh MyStation in the idle (nothing-sending) state.
private func makeIdleStation() -> MyStation {
    if Contest.shared == nil { _ = Contest() }
    makeKeyer()
    let s = MyStation()
    s.myCall = "VE3NEA"
    s.hisCall = ""
    s.amplitude = 300000
    s.wpm = 30
    return s
}

