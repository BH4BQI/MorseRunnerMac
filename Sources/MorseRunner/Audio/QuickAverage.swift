//
//  QuickAverage.swift
//  Port of QuickAvg.pas — TQuickAverage.
//
//  A fast recursive multi-pass moving average used per-sample (rather than per
//  block) — employed by the QSB fading model. Operates sample-by-sample.
//

import Foundation

public final class QuickAverage {
    public var passes: Int = 4 {
        didSet { reset() }
    }
    public var points: Int = 128 {
        didSet { reset() }
    }

    private var scale: Float = 0
    private var reBufs: [[Double]] = []
    private var imBufs: [[Double]] = []
    private var idx: Int = 0
    private var prevIdx: Int = 0

    public init() {
        points = 128
        passes = 4
        reset()
    }

    public func reset() {
        reBufs = Array(repeating: [Double](repeating: 0, count: points), count: passes + 1)
        imBufs = Array(repeating: [Double](repeating: 0, count: points), count: passes + 1)
        scale = powf(Float(points), Float(-passes))
        idx = 0
        prevIdx = points - 1
    }

    // MARK: per-sample filter

    public func filter(_ v: Float) -> Float {
        let r = doFilter(Double(v), bufs: &reBufs)
        prevIdx = idx
        idx = (idx + 1) % points
        return Float(r)
    }

    public func filter(_ are: Float, _ aim: Float) -> TComplex {
        let r = doFilter(Double(are), bufs: &reBufs)
        let im = doFilter(Double(aim), bufs: &imBufs)
        prevIdx = idx
        idx = (idx + 1) % points
        return TComplex(re: Float(r), im: Float(im))
    }

    public func filter(_ v: TComplex) -> TComplex {
        return filter(v.re, v.im)
    }

    public func filteredModule(_ are: Float, _ aim: Float) -> Float {
        let c = filter(are, aim)
        return sqrtf(c.re * c.re + c.im * c.im)
    }

    /// Faithful port of DoFilter.
    private func doFilter(_ v: Double, bufs: inout [[Double]]) -> Double {
        var result = v
        for p in 1...passes {
            let vv = result
            // Result := Bufs[p][PrevIdx] - Bufs[p-1][Idx] + V;
            result = bufs[p][prevIdx] - bufs[p - 1][idx] + vv
            bufs[p - 1][idx] = vv
        }
        bufs[passes][idx] = result
        return Double(scale) * result
    }
}
