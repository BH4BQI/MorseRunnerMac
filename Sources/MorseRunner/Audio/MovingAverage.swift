//
//  MovingAverage.swift
//  Port of MovAvg.pas — TMovingAverage.
//
//  Multi-pass recursive moving-average filter. Used as the receiver band-pass
//  filter: cascaded passes sharpen the roll-off. Operates on real or complex
//  (Re/Im) buffers.
//

import Foundation

public final class MovingAverage {
    public var passes: Int = 3 {
        didSet { reset() }
    }
    public var points: Int = 129 {
        didSet { reset() }
    }
    public var samplesInInput: Int = DEFAULTBUFSIZE {
        didSet { reset() }
    }
    public var decimateFactor: Int = 1 {
        didSet { reset() }
    }
    public var gainDb: Float = 0 {
        didSet { calcScale() }
    }

    private var bufRe: [[Float]] = []
    private var bufIm: [[Float]] = []
    private var norm: Float = 0
    /// Pre-allocated result buffers (reused every call — zero allocation on the
    /// hot audio path, which avoids GC pauses that can cause clicks).
    private var resultRe: [Float] = []
    private var resultIm: [Float] = []

    public init() {
        passes = 3
        points = 129
        samplesInInput = DEFAULTBUFSIZE
        decimateFactor = 1
        gainDb = 0
        reset()
    }

    public func reset() {
        let width = samplesInInput + points
        bufRe = Array(repeating: [Float](repeating: 0, count: width), count: passes + 1)
        bufIm = Array(repeating: [Float](repeating: 0, count: width), count: passes + 1)
        resultRe = [Float](repeating: 0, count: samplesInInput)
        resultIm = [Float](repeating: 0, count: samplesInInput)
        calcScale()
    }

    private func calcScale() {
        // (gain, dB→linear) × (averaging factor) = 10^(0.05·gainDb) × points^(-passes)
        norm = powf(10, 0.05 * gainDb) * powf(Float(points), Float(-passes))
    }

    // MARK: filter entry points

    public func filter(_ data: [Float]) -> [Float] {
        return doFilter(data, bufs: &bufRe, result: &resultRe)
    }

    public func filter(_ data: ReImArrays) -> ReImArrays {
        var out = ReImArrays()
        out.re = doFilter(data.re, bufs: &bufRe, result: &resultRe)
        out.im = doFilter(data.im, bufs: &bufIm, result: &resultIm)
        return out
    }

    /// Filter a ReImArrays in-place: overwrites data.re and data.im with the
    /// filtered result. Used by the Contest audio loop to avoid allocating a
    /// new ReImArrays on every block (zero-allocation hot path).
    public func filterInPlace(_ data: inout ReImArrays) {
        _ = doFilter(data.re, bufs: &bufRe, result: &resultRe)
        _ = doFilter(data.im, bufs: &bufIm, result: &resultIm)
        // Copy results back into the input array (in-place).
        for i in 0..<data.re.count {
            data.re[i] = resultRe[i]
            data.im[i] = resultIm[i]
        }
    }

    /// Core multi-pass filter. Writes normalized result into the pre-allocated
    /// `result` buffer and returns it. Faithful port of DoFilter + PushArray +
    /// ShiftArray + Pass + GetResult.
    private func doFilter(_ data: [Float], bufs: inout [[Float]], result: inout [Float]) -> [Float] {
        // put new data at the end of the 0-th buffer
        pushArray(data, into: &bufs[0])
        // multi-pass
        for i in 1...passes {
            pass(src: bufs[i - 1], dst: &bufs[i])
        }
        // normalize + decimate result from last buffer into pre-allocated array
        getResult(bufs[passes], into: &result)
        return result
    }

    // shift existing data to the left, append new data at the end
    private func pushArray(_ src: [Float], into dst: inout [Float]) {
        let len = dst.count - src.count
        guard len > 0 else {
            if !src.isEmpty { dst = src }
            return
        }
        // dst[0..<len] = dst[src.count..<src.count+len]
        for i in 0..<len {
            dst[i] = dst[i + src.count]
        }
        for i in 0..<src.count {
            dst[len + i] = src[i]
        }
    }

    private func shiftArray(_ dst: inout [Float], count: Int) {
        let n = dst.count - count
        for i in 0..<n {
            dst[i] = dst[i + count]
        }
        // Deliberately do NOT zero the tail — matches the original Delphi Move()
        // which leaves stale data that is immediately overwritten by pass().
        // Zeroing it caused subtle discontinuities that produced audible clicks.
    }

    private func pass(src: [Float], dst: inout [Float]) {
        // make free space
        shiftArray(&dst, count: samplesInInput)
        // recursive moving average: dst[i] = dst[i-1] - src[i-points] + src[i]
        for i in points..<src.count {
            dst[i] = dst[i - 1] - src[i - points] + src[i]
        }
    }

    private func getResult(_ src: [Float], into result: inout [Float]) {
        if decimateFactor == 1 {
            for i in 0..<samplesInInput {
                result[i] = src[points + i] * norm
            }
        } else {
            let outLen = min(samplesInInput / decimateFactor, result.count)
            for i in 0..<outLen {
                result[i] = src[points + i * decimateFactor] * norm
            }
        }
    }
}
