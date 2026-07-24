//
//  Random.swift
//  Port of RndFunc.pas — statistical distributions and block/time conversions.
//

import Foundation

/// Uniform in [0,1) — mirrors Delphi's `Random`.
@inlinable
public func rnd() -> Float { Float.random(in: 0..<1) }

/// Standard normal via Box-Muller. Faithful port of RndNormal (guards against
/// the very rare Ln(0) by resampling).
public func rndNormal() -> Float {
    while true {
        let u = rnd()
        if u > 0 {
            return sqrtf(-2 * logf(u)) * cosf(TWO_PI * rnd())
        }
    }
}

/// Gaussian clamped to [mean-lim, mean+lim].
public func rndGaussLim(_ mean: Float, _ lim: Float) -> Float {
    var r = mean + rndNormal() * 0.5 * lim
    r = max(mean - lim, min(mean + lim, r))
    return r
}

/// Rayleigh-distributed sample with the given mean.
public func rndRayleigh(_ mean: Float) -> Float {
    // Mirrors the original (two uniform draws): mean * sqrt(-ln(u1) - ln(u2)).
    return mean * sqrtf(-logf(max(rnd(), SMALL_FLOAT)) - logf(max(rnd(), SMALL_FLOAT)))
}

/// Uniform in [-1, 1].
public func rndUniform() -> Float { 2 * rnd() - 1 }

/// U-shaped (sin(π·(u-0.5))) — peaks at ±1.
public func rndUShaped() -> Float { sinf(.pi * (rnd() - 0.5)) }

/// Seconds → number of audio blocks at the current bufSize.
public func secondsToBlocks(_ sec: Float) -> Int {
    return Int((Float(DEFAULTRATE) / Float(Settings.shared.bufSize) * sec).rounded())
}

/// Blocks → seconds.
public func blocksToSeconds(_ blocks: Float) -> Float {
    return blocks * Float(Settings.shared.bufSize) / Float(DEFAULTRATE)
}

/// Poisson-distributed count with the given mean (Knuth).
public func rndPoisson(_ mean: Float) -> Int {
    let g = expf(-mean)
    var t: Float = 1
    for k in 0...30 {
        t *= rnd()
        if t <= g { return k }
    }
    return 30
}
