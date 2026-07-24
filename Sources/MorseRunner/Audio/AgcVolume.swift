//
//  AgcVolume.swift
//  Port of VolumCtl.pas — TVolumeControl.
//
//  Log-domain AGC with a Hann-windowed attack/hold shape. Drives quiet signals
//  up and loud signals down toward `maxOut`, mapping the configured noise floor
//  to a fixed output level.
//

import Foundation

public final class VolumeControl {
    public var maxOut: Float = 20000 {
        didSet { calcBeta() }
    }
    public var noiseInDb: Float {
        get { 20 * log10f(noiseIn) }
        set { noiseIn = powf(10, 0.05 * newValue); calcBeta() }
    }
    public var noiseOutDb: Float {
        get { 20 * log10f(noiseOut) }
        set { noiseOut = min(0.25 * maxOut, powf(10, 0.05 * newValue)); calcBeta() }
    }
    public var attackSamples: Int = 28 {
        didSet { attackSamples = max(1, attackSamples); makeAttackShape() }
    }
    public var holdSamples: Int = 28 {
        didSet { holdSamples = max(1, holdSamples); makeAttackShape() }
    }
    public var agcEnabled: Bool = false {
        didSet { if agcEnabled && !oldValue { reset() } }
    }
    public private(set) var isOverload: Bool = false

    // backing storage for the dB-typed properties
    private var noiseIn: Float = 1
    private var noiseOut: Float = 2000

    private var beta: Float = 0
    private var envelope: Float = 0
    private var defaultGain: Float = 0

    private var complexBuf = ReImArrays()
    private var realBuf: [Float] = []
    private var magBuf: [Float] = []
    private var len: Int = 0
    private var bufIdx: Int = 0
    private var attackShape: [Float] = []

    public init() {
        maxOut = 20000
        noiseIn = 1
        noiseOut = 2000
        calcBeta()
        attackSamples = 28
        holdSamples = 28
        makeAttackShape()
    }

    public func reset() {
        realBuf = [Float](repeating: 0, count: len)
        complexBuf.setLength(len)
        magBuf = [Float](repeating: 0, count: len)
        bufIdx = 0
    }

    // MARK: params

    private func makeAttackShape() {
        len = 2 * (attackSamples + holdSamples) + 1
        attackShape = [Float](repeating: 0, count: len)
        // attack shape (raised-cosine in log domain)
        if attackSamples > 0 {
            for i in 0..<attackSamples {
                let v = logf(0.5 - 0.5 * cosf(Float(i + 1) * Float.pi / Float(attackSamples + 1)))
                attackShape[i] = v
                attackShape[len - 1 - i] = v
            }
        }
        reset()
    }

    // Amplitude characteristic: Out = MaxOut * (1 - Exp(-In / Beta)).
    // Solve for beta so that NoiseIn → NoiseOut.
    private func calcBeta() {
        beta = noiseIn / logf(maxOut / (maxOut - noiseOut))
        defaultGain = noiseOut / noiseIn
    }

    // MARK: gain

    /// Find the max log-magnitude weighted by `attackShape` (centered on the output sample).
    private func calcAgcGain() -> Float {
        var envel: Float = 1e-10
        var di = bufIdx
        for wi in 0..<len {
            let sample = magBuf[di] + attackShape[wi]
            if sample > envel { envel = sample }
            di += 1
            if di == len { di = 0 }
        }
        envelope = envel
        envel = expf(envel)
        return maxOut * (1 - expf(-envel / beta)) / envel
    }

    private func applyAgc(_ v: Float) -> Float {
        realBuf[bufIdx] = v
        magBuf[bufIdx] = logf(abs(v) + 1e-10)
        bufIdx = (bufIdx + 1) % len
        let mid = (bufIdx + (len / 2)) % len
        return realBuf[mid] * calcAgcGain()
    }

    private func applyAgc(_ re: Float, _ im: Float) -> TComplex {
        complexBuf.re[bufIdx] = re
        complexBuf.im[bufIdx] = im
        magBuf[bufIdx] = 0.5 * logf(re * re + im * im)
        bufIdx = (bufIdx + 1) % len
        let mid = (bufIdx + (len / 2)) % len
        let gain = calcAgcGain()
        return TComplex(re: complexBuf.re[mid] * gain, im: complexBuf.im[mid] * gain)
    }

    private func applyDefaultGain(_ v: Float) -> Float {
        let r = min(maxOut, max(-maxOut, v * defaultGain))
        isOverload = isOverload || (abs(r) == maxOut)
        return r
    }

    private func applyDefaultGain(_ re: Float, _ im: Float) -> TComplex {
        let rr = min(maxOut, max(-maxOut, re * defaultGain))
        let ii = min(maxOut, max(-maxOut, im * defaultGain))
        isOverload = isOverload || abs(rr) == maxOut || abs(ii) == maxOut
        return TComplex(re: rr, im: ii)
    }

    // MARK: process

    public func process(_ data: [Float]) -> [Float] {
        isOverload = false
        var result = [Float](repeating: 0, count: data.count)
        if agcEnabled {
            for i in 0..<data.count {
                result[i] = applyAgc(data[i])
            }
        } else {
            for i in 0..<data.count {
                result[i] = applyDefaultGain(data[i])
            }
        }
        return result
    }

    public func process(_ data: ReImArrays) -> ReImArrays {
        isOverload = false
        var result = ReImArrays()
        result.setLength(data.re.count)
        if agcEnabled {
            for i in 0..<data.re.count {
                let c = applyAgc(data.re[i], data.im[i])
                result.re[i] = c.re
                result.im[i] = c.im
            }
        } else {
            for i in 0..<data.re.count {
                let c = applyDefaultGain(data.re[i], data.im[i])
                result.re[i] = c.re
                result.im[i] = c.im
            }
        }
        return result
    }
}
