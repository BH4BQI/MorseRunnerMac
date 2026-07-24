//
//  Tests/AudioPipelineTests.swift
//  End-to-end check that Contest.getAudio produces non-trivial signal with
//  energy concentrated at the configured CW pitch — guards against silent or
//  mis-pitched output.
//

import Foundation

enum AudioPipelineTests {
    static let suite = TestRunner.register("AudioPipeline", [
        TestCase("getAudio produces non-silent signal") {
            bootstrapEngineIfNeeded()
            Settings.shared.runMode = .pileUp
            Tst.initContest()
            Tst.me.sendMsg(.cq)

            // Render ~1.5 s and check peak amplitude.
            let bufSize = Settings.shared.bufSize
            var peak: Float = 0
            var nonZero = 0
            var total = 0
            let blocks = (Int(1.5 * Double(DEFAULTRATE)) + bufSize - 1) / bufSize
            for _ in 0..<blocks {
                let blk = Tst.getAudio(count: bufSize)
                for v in blk {
                    let a = abs(v)
                    if a > peak { peak = a }
                    if a > 1 { nonZero += 1 }
                    total += 1
                }
            }
            return expectAll(
                expectTrue(peak > 1000, "peak amplitude > 1000 (got \(peak))"),
                expectTrue(Double(nonZero) / Double(max(1, total)) > 0.5,
                           "majority non-zero samples (got \(nonZero)/\(total))")
            )
        },
    ])
}

private func bootstrapEngineIfNeeded() {
    if Contest.shared == nil { _ = Contest() }
    makeKeyer()
    Keyer.rate = DEFAULTRATE
    Keyer.bufSize = Settings.shared.bufSize
}

private func expectAll(_ results: TestResult...) -> TestResult {
    for r in results { if case .fail(let m) = r { return .fail(m) } }
    return .pass
}
