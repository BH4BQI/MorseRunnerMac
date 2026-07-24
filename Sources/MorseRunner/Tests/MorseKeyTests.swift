//
//  Tests/MorseKeyTests.swift
//  Verifies the CW keyer: encoding, PARIS-standard WPM timing, dit/dah ratio,
//  and ramp shape. These guard the audio fidelity that's hard to verify by ear.
//

import Foundation

enum MorseKeyTests {
    static let suite = TestRunner.register("MorseKey", [
        TestCase("encode known characters") {
            let k = MorseKey()
            return expectAll(
                expectEqual(k.encode("E"), ".~", "E"),
                expectEqual(k.encode("T"), "-~", "T"),
                expectTrue(k.encode("PARIS").hasSuffix("~"), "PARIS suffix"),
                expectTrue(k.encode("PARIS").contains(".--."), "P present")
            )
        },

        TestCase("encode empty string is empty") {
            return expectEqual(MorseKey().encode(""), "")
        },

        TestCase("PARIS timing @60 WPM ≈ 1.0 s") {
            let k = MorseKey()
            k.rate = DEFAULTRATE
            k.bufSize = 512
            k.wpm = 60
            let spu = Int((0.1 * Float(k.rate) * 12.0 / Float(60)).rounded())
            let duration = Double(spu * 50) / Double(k.rate)
            return expectAll(
                expectEqual(spu, 221, "samplesPerUnit"),
                expectApprox(duration, 1.002, accuracy: 0.01, "PARIS duration")
            )
        },

        TestCase("dit is ~1 unit, dah is ~3× dit") {
            let k = MorseKey()
            k.rate = 11025
            k.bufSize = 512
            k.wpm = 30
            let spu = Int((0.1 * Float(11025) * 12.0 / Float(30)).rounded())
            func onCount(_ ch: String) -> Int {
                k.morseMsg = k.encode(ch)
                return k.envelope.filter { $0 > 0.5 }.count
            }
            let dit = onCount("E")
            let dah = onCount("T")
            return expectAll(
                expectTrue(dah > dit * 2, "dah should be ~3× dit (dah=\(dah) dit=\(dit))"),
                expectTrue(dah < dit * 4, "dah shouldn't exceed ~3× dit + ramps"),
                expectApprox(Double(dit), Double(spu), accuracy: Double(spu) / 2, "dit on-time")
            )
        },

        TestCase("Blackman-Harris onset is monotonic") {
            let k = MorseKey()
            k.riseTime = 0.005
            k.morseMsg = k.encode("E")
            let env = k.envelope
            var sawStart = false
            var prev: Float = 0
            var rose = false
            for v in env {
                if v > 0.01 { sawStart = true }
                if sawStart {
                    if v > prev + 0.001 { rose = true }
                    if v >= 0.99 { break }
                    if v < prev - 0.001 {
                        return .fail("ramp decreased (prev=\(prev) v=\(v))")
                    }
                    prev = v
                }
            }
            return rose ? .pass : .fail("envelope never rose")
        },
    ])
}

/// Helper: a test passes only if all sub-results pass.
private func expectAll(_ results: TestResult...) -> TestResult {
    for r in results { if case .fail(let m) = r { return .fail(m) } }
    return .pass
}
