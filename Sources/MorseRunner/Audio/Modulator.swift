//
//  Modulator.swift
//  Port of Mixers.pas (TModulator only).
//
//  Up-converts the baseband (complex) signal to the audio carrier (CW pitch).
//  Uses a precomputed sin/cos table indexed by sample number for speed.
//

import Foundation

public final class Modulator {
    public var samplesPerSec: Int = 5512 {
        didSet { calcSinCos() }
    }
    /// Carrier (pitch) frequency. Setter rebuilds the sin/cos lookup table.
    /// NOTE: `calcSinCos` mutates the backing field directly to avoid infinite
    /// recursion (the Pascal original assigns the field FCarrierFreq, not a
    /// property setter).
    private var _carrierFreq: Float = 600
    public var carrierFreq: Float {
        get { _carrierFreq }
        set {
            _carrierFreq = newValue
            calcSinCos()
        }
    }
    public var gain: Float = 1 {
        didSet { calcSinCos() }
    }

    private var sampleNo: Int = 0
    private var sn: [Float] = []
    private var cs: [Float] = []

    public init() {
        _carrierFreq = 600
        samplesPerSec = 5512
        gain = 1
        calcSinCos()
        sampleNo = 0
    }

    private func calcSinCos() {
        let cnt = Int((Float(samplesPerSec) / _carrierFreq).rounded())
        // Recompute carrier to land on an integer table length (original behaviour).
        _carrierFreq = Float(samplesPerSec) / Float(cnt)
        let dFi = TWO_PI / Float(cnt)

        sn = [Float](repeating: 0, count: cnt)
        cs = [Float](repeating: 0, count: cnt)

        sn[0] = 0; sn[1] = sinf(dFi)
        cs[0] = 1; cs[1] = cosf(dFi)

        // phase recursion (stable recurrence)
        if cnt > 2 {
            for i in 2..<cnt {
                cs[i] = cs[1] * cs[i - 1] - sn[1] * sn[i - 1]
                sn[i] = cs[1] * sn[i - 1] + sn[1] * cs[i - 1]
            }
        }
        // apply gain
        for i in 0..<cnt {
            cs[i] *= gain
            sn[i] *= gain
        }
    }

    // MARK: modulate (baseband → audio)

    public func modulate(_ data: ReImArrays) -> [Float] {
        let n = data.re.count
        var result = [Float](repeating: 0, count: n)
        let tableLen = cs.count
        guard tableLen > 0 else { return result }
        for i in 0..<n {
            // Result[i] := Re[i]*Sn[k] - Im[i]*Cs[k]
            result[i] = data.re[i] * sn[sampleNo] - data.im[i] * cs[sampleNo]
            sampleNo = (sampleNo + 1) % tableLen
        }
        return result
    }

    public func modulate(_ data: [Float]) -> [Float] {
        let n = data.count
        var result = [Float](repeating: 0, count: n)
        let tableLen = cs.count
        guard tableLen > 0 else { return result }
        for i in 0..<n {
            result[i] = data[i] * cs[sampleNo]
            sampleNo = (sampleNo + 1) % tableLen
        }
        return result
    }

    public func modulate(_ data: [TComplex]) -> [Float] {
        let n = data.count
        var result = [Float](repeating: 0, count: n)
        let tableLen = cs.count
        guard tableLen > 0 else { return result }
        for i in 0..<n {
            result[i] = data[i].re * sn[sampleNo] - data[i].im * cs[sampleNo]
            sampleNo = (sampleNo + 1) % tableLen
        }
        return result
    }
}
