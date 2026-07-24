//
//  Qsb.swift
//  Port of Qsb.pas — TQsb.
//
//  Rayleigh-fading model: applies a smoothly-varying gain to a station's audio
//  block. The gain is derived from filtered complex uniform noise and ramps
//  linearly across sub-blocks.
//

import Foundation

public final class Qsb {
    private var filt: QuickAverage
    public var qsbLevel: Float = 1
    public var bandwidth: Float = 0.1 {
        didSet { applyBandwidth(bandwidth) }
    }
    private var fGain: Float = 0

    public init() {
        filt = QuickAverage()
        filt.passes = 3
        qsbLevel = 1
        applyBandwidth(0.1)
    }

    private func newGain() -> Float {
        let c = filt.filter(rndUniform(), rndUniform())
        var r = sqrtf((c.re * c.re + c.im * c.im) * 3 * Float(filt.points))
        r = r * qsbLevel + (1 - qsbLevel)
        return r
    }

    private func applyBandwidth(_ value: Float) {
        // Filt.Points := Ceil(0.37 * DEFAULTRATE / ((bufSize/4) * value))
        let pts = Int((0.37 * Float(DEFAULTRATE) / ((Float(Settings.shared.bufSize) / 4) * value)).rounded(.up))
        filt.points = max(1, pts)
        // warm up the filter to settle the gain
        for _ in 0..<(filt.points * 3) { fGain = newGain() }
    }

    /// Apply fading to a station audio block (in place).
    public func apply(to arr: inout [Float]) {
        let subBlock = Settings.shared.bufSize / 4
        guard subBlock > 0 else { return }
        let blkCnt = arr.count / subBlock
        for b in 0..<blkCnt {
            let target = newGain()
            let dG = (target - fGain) / Float(subBlock)
            let base = b * subBlock
            for i in 0..<subBlock {
                arr[base + i] *= fGain
                fGain += dG
            }
        }
    }
}
