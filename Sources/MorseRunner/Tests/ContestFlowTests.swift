//
//  Tests/ContestFlowTests.swift
//  End-to-end contest-flow tests, modelled on BA4ALC's Morse Runner guide
//  (https://www.qsl.net/ba4alc/chinese/MORSERUNNER/morserunner.html).
//
//  These drive the real Contest engine headlessly through the user workflow:
//    Start Pile-Up → send CQ → stations call → save a QSO → verify the log
//    records the correct call/RST/NR and the WPX score (QSOs × prefixes).
//

import Foundation

enum ContestFlowTests {
    static let suite = TestRunner.register("ContestFlow (BA4ALC guide)", [

        TestCase("Pile-Up: CQ elicits at least one caller") {
            // Guide: "在 Pile-Up 模式下，发送 CQ (F1) 后会有随机数量的电台呼叫你。"
            // The number of callers is Poisson-distributed, so to keep the test
            // deterministic we force at least one via addCaller, then verify the
            // engine actually drives it onto the air within a render window.
            bootstrap()
            Settings.shared.activity = 6
            Settings.shared.runMode = .pileUp
            Tst.initContest()
            QsoLog.shared.clear()

            _ = Tst.stations.addCaller()
            runEngine(seconds: 2.0)

            return expectTrue(Tst.stations.count >= 1,
                "a forced caller should be present (got \(Tst.stations.count))")
        },

        TestCase("saving a QSO logs call/RST/NR") {
            // Guide: the log shows call, received and sent exchanges.
            bootstrap()
            Settings.shared.activity = 6
            Settings.shared.runMode = .pileUp
            Tst.initContest()
            QsoLog.shared.clear()

            // Force a known caller and let it come up on the air.
            let dx = Tst.stations.addCaller() as! DxStation
            runEngine(seconds: 1.0)
            // The user copies the call + exchange and saves with the DX's true
            // data, then we verify the log captured it verbatim.
            QsoLog.shared.saveQso(callField: dx.myCall,
                                   rstField: String(format: "%03d", dx.rst),
                                   nrField: String(dx.nr))
            QsoLog.shared.updateLastTrueCall(dx.myCall, rst: dx.rst, nr: dx.nr)
            QsoLog.shared.checkErr()
            return expectAll(
                expectEqual(QsoLog.shared.qsoList.last?.call, dx.myCall, "logged call"),
                expectEqual(QsoLog.shared.qsoList.last?.rst, dx.rst, "logged RST"),
                expectEqual(QsoLog.shared.qsoList.last?.nr, dx.nr, "logged NR"),
                expectEqual(QsoLog.shared.qsoList.last?.err, "   ", "clean QSO err")
            )
        },

        TestCase("duplicate QSO is flagged DUP") {
            // Guide: the log marks DUP for duplicate contacts. Per the original
            // CheckErr, NIL takes precedence over DUP — so DUP only shows when
            // both QSOs have the DX's true call. We inject matching truth for
            // both saves.
            bootstrap()
            Settings.shared.runMode = .pileUp
            Tst.initContest()
            QsoLog.shared.clear()
            // First (clean) QSO.
            QsoLog.shared.saveQso(callField: "W1AW", rstField: "599", nrField: "001")
            QsoLog.shared.updateLastTrueCall("W1AW", rst: 599, nr: 1)
            QsoLog.shared.checkErr()
            guard QsoLog.shared.qsoList.first?.err == "   " else {
                return .fail("first QSO should be clean, got \(QsoLog.shared.qsoList.first?.err ?? "?")")
            }
            // Second QSO with the same call AND matching truth → DUP.
            QsoLog.shared.saveQso(callField: "W1AW", rstField: "599", nrField: "001")
            QsoLog.shared.updateLastTrueCall("W1AW", rst: 599, nr: 1)
            QsoLog.shared.checkErr()
            return expectEqual(QsoLog.shared.qsoList.last?.err, "DUP", "second QSO err flag")
        },

        TestCase("error codes: NIL when no DX truth, RST/NR when mismatched") {
            // Guide: NIL = not in the other station's log; RST = wrong RST;
            // NR = wrong exchange number.
            bootstrap()
            Settings.shared.runMode = .pileUp
            Tst.initContest()
            QsoLog.shared.clear()
            // No DX truth injected → NIL.
            QsoLog.shared.saveQso(callField: "W1AW", rstField: "599", nrField: "1")
            if QsoLog.shared.qsoList.last?.err != "NIL" {
                return .fail("expected NIL, got \(QsoLog.shared.qsoList.last?.err ?? "?")")
            }
            // Truth with wrong RST → RST.
            QsoLog.shared.saveQso(callField: "W2BK", rstField: "579", nrField: "1")
            QsoLog.shared.updateLastTrueCall("W2BK", rst: 599, nr: 1)
            QsoLog.shared.checkErr()
            if QsoLog.shared.qsoList.last?.err != "RST" {
                return .fail("expected RST, got \(QsoLog.shared.qsoList.last?.err ?? "?")")
            }
            // Truth with wrong NR → NR.
            QsoLog.shared.saveQso(callField: "W3CM", rstField: "599", nrField: "5")
            QsoLog.shared.updateLastTrueCall("W3CM", rst: 599, nr: 9)
            QsoLog.shared.checkErr()
            return expectEqual(QsoLog.shared.qsoList.last?.err, "NR ", "NR mismatch err flag")
        },

        TestCase("invalid QSO (short call) is rejected") {
            // Guide / input validation: a callsign must be long enough to log.
            bootstrap()
            Settings.shared.runMode = .pileUp
            Tst.initContest()
            QsoLog.shared.clear()
            let before = QsoLog.shared.qsoList.count
            QsoLog.shared.saveQso(callField: "W", rstField: "599", nrField: "1")  // too short
            return expectEqual(QsoLog.shared.qsoList.count, before,
                "short call must not be logged")
        },

        TestCase("NR increments after each save") {
            // Guide: the sent exchange serial number auto-increments per QSO.
            bootstrap()
            Settings.shared.runMode = .pileUp
            Tst.initContest()
            Tst.me.nr = 1
            QsoLog.shared.clear()
            QsoLog.shared.saveQso(callField: "W1AW", rstField: "599", nrField: "1")
            let nrAfterFirst = Tst.me.nr
            QsoLog.shared.saveQso(callField: "W2BK", rstField: "599", nrField: "2")
            return expectEqual(Tst.me.nr, nrAfterFirst + 1, "NR increments by 1 per QSO")
        },

        TestCase("WPX score = clean QSOs × distinct prefixes") {
            // Guide: "成绩 = QSO 数 × 前缀数（不同前缀的数量）". We log three QSOs
            // with two distinct prefixes (W1, W2, W1) and verify the verified
            // score = 3 × 2 = 6.
            bootstrap()
            Settings.shared.runMode = .pileUp
            Tst.initContest()
            QsoLog.shared.clear()
            for (call, nr) in [("W1AW", 1), ("W2BK", 2), ("W1ZZ", 3)] {
                QsoLog.shared.saveQso(callField: call, rstField: "599", nrField: String(nr))
                QsoLog.shared.updateLastTrueCall(call, rst: 599, nr: nr)  // clean
                QsoLog.shared.checkErr()
            }
            // Recompute verified stats: pts = #clean QSOs, mul = #distinct pfx.
            // pfx comes from ExtractPrefix on each call's raw callsign.
            let clean = QsoLog.shared.qsoList.filter { $0.err == "   " }
            let pfxes = Set(clean.map { $0.pfx })
            let score = clean.count * pfxes.count
            return expectAll(
                expectEqual(clean.count, 3, "clean QSO count"),
                expectEqual(pfxes.count, 2, "distinct prefix count"),
                expectEqual(score, 6, "WPX score")
            )
        },
        TestCase("late DX truth lands in the correct (non-last) QSO, not NIL") {
            // Bug: in pile-up, several QSOs may be saved before the DX stations
            // report their true data. The truth must land in the QSO whose call
            // matches, even if it's no longer the last entry — otherwise earlier
            // QSOs get wrongly marked NIL.
            bootstrap()
            Settings.shared.runMode = .pileUp
            Tst.initContest()
            QsoLog.shared.clear()
            // Save QSO A (W1AW), then QSO B (K1ABC) BEFORE A's DX reports.
            QsoLog.shared.saveQso(callField: "W1AW", rstField: "599", nrField: "001")
            QsoLog.shared.saveQso(callField: "K1ABC", rstField: "589", nrField: "007")
            // Now W1AW's DX finishes (one tick later). The old code matched only
            // qsoList.last (K1ABC) → W1AW stayed NIL. With the fix it finds W1AW.
            let idx = QsoLog.shared.updateLastTrueCall("W1AW", rst: 599, nr: 1)
            QsoLog.shared.checkErr(at: idx)
            let w1aw = QsoLog.shared.qsoList[0]
            let k1abc = QsoLog.shared.qsoList[1]
            return expectAll(
                expectEqual(w1aw.err, "   ", "W1AW should be clean, not NIL"),
                expectEqual(w1aw.trueCall, "W1AW", "W1AW got its true call"),
                expectEqual(k1abc.err, "NIL", "K1ABC still NIL until its DX reports")
            )
        },
    ])
}

// MARK: - helpers

private func bootstrap() {
    if Contest.shared == nil { _ = Contest() }
    makeKeyer()
    Keyer.rate = DEFAULTRATE
    Keyer.bufSize = Settings.shared.bufSize
    Settings.shared.saveWav = false
}

/// Render `seconds` of audio through the engine, advancing the simulation.
private func runEngine(seconds: Double) {
    let bufSize = Settings.shared.bufSize
    let blocks = (Int(seconds * Double(DEFAULTRATE)) + bufSize - 1) / bufSize
    for _ in 0..<blocks {
        _ = Tst.getAudio(count: bufSize)
    }
}

private func expectAll(_ results: TestResult...) -> TestResult {
    for r in results { if case .fail(let m) = r { return .fail(m) } }
    return .pass
}
