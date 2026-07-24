//
//  Tests/ProbeTests.swift
//  Diagnostic suite: prints what each StationMessage actually expands to and
//  what the ESM/space flows produce, so we can compare against BA4ALC's guide.
//  (Run with --run-tests; the printed lines are the "expected vs actual".)
//

import Foundation

enum ProbeTests {
    static let suite = TestRunner.register("Probe (diagnostic)", [
        TestCase("print message → expanded-text mapping") {
            // Use a plain Station (not MyStation) to avoid the piece-splitting
            // override, so sendText just builds msgText directly.
            let s = makePlainStation()
            s.myCall = "BH4BQI"
            s.hisCall = "W1AW"
            s.rst = 599
            s.nr = 1

            print("\n    --- message → expanded text (BA4ALC guide) ---")
            let mapping: [(String, StationMessage)] = [
                ("F1 CQ", .cq), ("F2 NR(<#>)", .nr), ("F3 TU", .tu),
                ("F4 my-call", .myCall), ("F5 his-call", .hisCall),
                ("F6 B4", .b4), ("F7 ?", .qm), ("F8 NIL", .nilMsg),
                ("agn", .agn), ("nrQm", .nrQm), ("r_nr", .r_nr),
            ]
            for (name, msg) in mapping {
                s.msgText = ""   // reset for a clean read
                s.sendMsg(msg)
                print("      \(name.padding(toLength: 14, withPad: " ", startingAt: 0)) → \"\(s.msgText)\"")
            }
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
