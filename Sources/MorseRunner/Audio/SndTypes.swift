//
//  SndTypes.swift
//  Port of SndTypes.pas — basic sample-array types and DSP constants.
//

import Foundation

// MARK: - Constants (SndTypes.pas)

public let FOUR_PI: Float = 4 * .pi
public let TWO_PI: Float = 2 * .pi
public let HALF_PI: Float = 0.5 * .pi
public let SMALL_FLOAT: Float = 1e-12

// MARK: - Re/Im container (TReImArrays)

/// Pair of real arrays representing a complex (I/Q) sample block.
/// Mirrors the Delphi `TReImArrays = record Re, Im: TSingleArray; end;`.
public struct ReImArrays {
    public var re: [Float]
    public var im: [Float]

    public init() { self.re = []; self.im = [] }
    public init(re: [Float], im: [Float]) { self.re = re; self.im = im }

    public var count: Int { return re.count }

    public mutating func setLength(_ len: Int) {
        re = [Float](repeating: 0, count: len)
        im = [Float](repeating: 0, count: len)
    }

    public mutating func clear() {
        re.removeAll(keepingCapacity: true)
        im.removeAll(keepingCapacity: true)
    }
}

public func setLengthReIm(_ arr: inout ReImArrays, _ len: Int) {
    arr.setLength(len)
}

public func clearReIm(_ arr: inout ReImArrays) {
    arr.clear()
}

// MARK: - Complex (TComplex)

public struct TComplex {
    public var re: Float
    public var im: Float
    public init(re: Float = 0, im: Float = 0) { self.re = re; self.im = im }
}
