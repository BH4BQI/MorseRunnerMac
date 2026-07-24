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
        calcScale()
    }

    private func calcScale() {
        // (gain, dB→linear) × (averaging factor) = 10^(0.05·gainDb) × points^(-passes)
        norm = powf(10, 0.05 * gainDb) * powf(Float(points), Float(-passes))
    }

    // MARK: filter entry points

    public func filter(_ data: [Float]) -> [Float] {
        doFilter(data, bufs: &bufRe)
    }

    public func filter(_ data: ReImArrays) -> ReImArrays {
        var out = ReImArrays()
        out.re = doFilter(data.re, bufs: &bufRe)
        out.im = doFilter(data.im, bufs: &bufIm)
        return out
    }

    /// Core multi-pass filter. Faithful port of DoFilter + PushArray + ShiftArray + Pass + GetResult.
    private func doFilter(_ data: [Float], bufs: inout [[Float]]) -> [Float] {
        // put new data at the end of the 0-th buffer
        pushArray(data, into: &bufs[0])
        // multi-pass
        for i in 1...passes {
            pass(src: bufs[i - 1], dst: &bufs[i])
        }
        // normalize + decimate result from last buffer
        return getResult(bufs[passes])
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
        // The Pascal code leaves the tail stale (overwritten later); zero it for safety.
        for i in n..<dst.count {
            dst[i] = 0
        }
    }

    private func pass(src: [Float], dst: inout [Float]) {
        // make free space
        shiftArray(&dst, count: samplesInInput)
        // recursive moving average: dst[i] = dst[i-1] - src[i-points] + src[i]
        for i in points..<src.count {
            dst[i] = dst[i - 1] - src[i - points] + src[i]
        }
    }

    private func getResult(_ src: [Float]) -> [Float] {
        if decimateFactor == 1 {
            var result = [Float](repeating: 0, count: samplesInInput)
            for i in 0..<samplesInInput {
                result[i] = src[points + i] * norm
            }
            return result
        } else {
            let outLen = samplesInInput / decimateFactor
            var result = [Float](repeating: 0, count: outLen)
            for i in 0..<outLen {
                result[i] = src[points + i * decimateFactor] * norm
            }
            return result
        }
    }
}
