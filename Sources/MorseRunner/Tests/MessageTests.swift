//
//  Tests/MessageTests.swift
//  Asserts that each function-key message (F1-F8) expands to the CW text
//  described in BA4ALC's Morse Runner guide.
//

import Foundation

enum MessageTests {
    static let suite = TestRunner.register("Function-key messages (BA4ALC)", [
        TestCase("F1 sends 'CQ <my> TEST'") {
            return checkMessage(.cq, expectedContains: ["CQ", "TEST", "BH4BQI"])
        },
        TestCase("F3 sends 'TU'") {
            return checkMessage(.tu, expected: "TU")
        },
        TestCase("F4 sends my call") {
            return checkMessage(.myCall, expected: "BH4BQI")
        },
        TestCase("F5 sends his call") {
            return checkMessage(.hisCall, expected: "W1AW")
        },
        TestCase("F6 sends 'QSO B4'") {
            return checkMessage(.b4, expected: "QSO B4")
        },
        TestCase("F7 sends '?'") {
            return checkMessage(.qm, expected: "?")
        },
        TestCase("F8 sends 'NIL'") {
            return checkMessage(.nilMsg, expected: "NIL")
        },
        TestCase("AGN sends 'AGN'") {
            return checkMessage(.agn, expected: "AGN")
        },
        TestCase("NR exchange uses 5NN (599) and serial number") {
            // <#> expands to RST+NR with 599→5NN.
            let s = makePlainStation()
            s.myCall = "BH4BQI"; s.hisCall = "W1AW"; s.rst = 599; s.nr = 42
            s.msgText = ""
            s.sendMsg(.nr)
            // nrAsText applies 599→5NN plus 0→T / 9→N substitutions; just check
            // the 5NN and the NR's last digit ("2") are present.
            let text = s.msgText
            if !text.contains("5NN") { return .fail("expected 5NN in \"\(text)\"") }
            if !text.contains("2") { return .fail("expected NR digit in \"\(text)\"") }
            return .pass
        },
    ])
}

private func makePlainStation() -> Station {
    if Contest.shared == nil { _ = Contest() }
    makeKeyer()
    let s = Station()
    s.wpm = 30
    s.amplitude = 1000
    return s
}

private func checkMessage(_ msg: StationMessage, expected: String) -> TestResult {
    let s = makePlainStation()
    s.myCall = "BH4BQI"; s.hisCall = "W1AW"; s.rst = 599; s.nr = 1
    s.msgText = ""
    s.sendMsg(msg)
    return expectEqual(s.msgText, expected, "msgText for \(msg)")
}

private func checkMessage(_ msg: StationMessage, expectedContains: [String]) -> TestResult {
    let s = makePlainStation()
    s.myCall = "BH4BQI"; s.hisCall = "W1AW"; s.rst = 599; s.nr = 1
    s.msgText = ""
    s.sendMsg(msg)
    for token in expectedContains {
        if !s.msgText.contains(token) {
            return .fail("expected \"\(token)\" in msgText, got \"\(s.msgText)\"")
        }
    }
    return .pass
}
