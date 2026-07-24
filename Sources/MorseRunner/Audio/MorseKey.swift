//
//  MorseKey.swift
//  Port of MorseKey.pas + MorseTbl.pas
//
//  Generates the CW (Morse) amplitude envelope for a text message at a given
//  WPM (PARIS standard). The on/off keying shape uses a Blackman-Harris
//  step-response ramp for click-free edges, exactly as the original.
//

import Foundation

// MARK: - Morse code table (MorseTbl.pas)

/// Raw table entries of the form `"<char>[<code>]<freq>"`.
/// The 3-digit suffix is the character's relative frequency (unused at runtime
/// here, kept for fidelity to the original data).
private let morseTableRaw: [String] = [
    "1[.----]013", "2[..---]014", "3[...--]033", "4[....-]043", "5[.....]041",
    "6[-....]008", "7[--...]014", "8[---..]010", "9[----.]014", "0[-----]011",
    "A[.-]127", "B[-...]062", "C[-.-.]069", "D[-..]084", "E[.]321", "F[..-.]055",
    "G[--.]043", "H[....]068", "I[..]130", "J[.---]008", "K[-.-]117", "L[.-..]100",
    "M[--]076", "N[-.]168", "O[---]126", "P[.--.]057", "Q[--.-]068", "R[.-.]095",
    "S[...]159", "T[-]236", "U[..-]061", "V[...-]023", "W[.--]095", "X[-..-]016",
    "Y[-.--]040", "Z[--..]012",
    "/[-..-.]019", "[.-.-.-]012", ",[--..--]009", "?[..--..]016", "=[-...-]015",
    "\\[...-.]001",
    "sk[...-.-]007", "ar[.-.-.]011", "kn[-.--.]001", "cq[-.-.--.-]001",
    "bk[-...-.-]002", "dx[-..-..-]001",
]

// MARK: - TKeyer

public final class MorseKey {
    /// char → morse code string (with trailing element separators).
    private var morse: [Character: String] = [:]

    private var rampLen: Int = 0
    private var rampOn: [Float] = []
    private var rampOff: [Float] = []

    /// Keying rise time in seconds (5 ms by default — very click-free).
    public var riseTime: Float = 0.005 {
        didSet { makeRamp() }
    }

    public var wpm: Int = 30
    public var bufSize: Int = DEFAULTBUFSIZE
    public var rate: Int = 11025
    public var morseMsg: String = ""
    public var trueEnvelopeLen: Int = 0

    public init() {
        rate = 11025
        loadMorseTable()
        riseTime = 0.005   // triggers makeRamp via setter
    }

    // MARK: table parsing (LoadMorseTable)

    private func loadMorseTable() {
        // Parse "X[code]freq" → morse[X] = code + " " (trailing space).
        for entry in morseTableRaw {
            guard entry.count >= 4 else { continue }
            // entry[0] is the char, entry[1] must be '['.
            // Multi-char keys ("sk","ar","kn","cq","bk","dx") are lowercase and
            // don't participate in single-char lookups here; original code only
            // loads single-char entries via `Morse[Ch]` with a Char key, so we
            // skip any entry whose first character is already lowercase/letter
            // sequence — but to stay faithful we still register the first char.
            let chars = Array(entry)
            // The opening bracket must be at index 1 for a single-char key.
            guard chars[1] == "[" else { continue }
            let ch = chars[0]
            guard let closeIdx = chars.firstIndex(of: "]"), closeIdx > 2 else { continue }
            // Code sits between '[' (index 1) and ']' (closeIdx), i.e. chars[2..<closeIdx].
            // (The Pascal original used 1-based indexing: Copy(S, 3, ...).)
            let code = String(chars[2..<closeIdx]) + " "
            morse[ch] = code
        }
    }

    // MARK: Blackman-Harris ramp (BlackmanHarrisKernel / StepResponse / MakeRamp)

    private func blackmanHarrisKernel(_ x: Float) -> Float {
        let a0: Float = 0.35875
        let a1: Float = 0.48829
        let a2: Float = 0.14128
        let a3: Float = 0.01168
        return a0 - a1 * cosf(2 * .pi * x) + a2 * cosf(4 * .pi * x) - a3 * cosf(6 * .pi * x)
    }

    private func blackmanHarrisStepResponse(_ len: Int) -> [Float] {
        guard len > 0 else { return [] }
        var result = [Float](repeating: 0, count: len)
        // generate kernel
        for i in 0..<len {
            result[i] = blackmanHarrisKernel(Float(i) / Float(len))
        }
        // integrate
        for i in 1..<len {
            result[i] = result[i - 1] + result[i]
        }
        // normalize
        let scale: Float = 1.0 / result[len - 1]
        for i in 0..<len {
            result[i] = result[i] * scale
        }
        return result
    }

    private func makeRamp() {
        rampLen = Int((2.7 * riseTime * Float(rate)).rounded())
        rampOn = blackmanHarrisStepResponse(rampLen)
        rampOff = [Float](repeating: 0, count: rampLen)
        // rampOff is rampOn reversed
        if rampLen > 0 {
            for i in 0..<rampLen {
                rampOff[rampLen - 1 - i] = rampOn[i]
            }
        }
    }

    // MARK: Encode (text → morse string)

    public func encode(_ txt: String) -> String {
        var result = ""
        for ch in txt {
            if ch == " " || ch == "_" {
                result.append(" ")
            } else {
                if let code = morse[ch] {
                    result.append(code)
                }
            }
        }
        // Replace trailing space with '~' (end-of-message marker).
        if !result.isEmpty {
            result.removeLast()
            result.append("~")
        }
        return result
    }

    // MARK: GetEnvelope (morse string → amplitude samples)

    public var envelope: [Float] {
        getEnvelope()
    }

    /// Build the amplitude envelope for `morseMsg` at the current `wpm`.
    /// Faithful port of `TKeyer.GetEnvelope`.
    public func getEnvelope() -> [Float] {
        let chars = Array(morseMsg)
        guard !chars.isEmpty else { return [] }

        // Count units: '.'=2, '-'=4, ' '=2, '~'=1
        var unitCnt = 0
        for c in chars {
            switch c {
            case ".": unitCnt += 2
            case "-": unitCnt += 4
            case " ": unitCnt += 2
            case "~": unitCnt += 1
            default: break
            }
        }

        // samples per unit (PARIS: 1 unit = 1200/wpm ms; *0.1s*12/wpm)
        let samplesInUnit = Int((0.1 * Float(rate) * 12.0 / Float(wpm)).rounded())
        trueEnvelopeLen = unitCnt * samplesInUnit + rampLen
        let len = bufSize * Int((Double(trueEnvelopeLen) / Double(bufSize)).rounded(.up))

        var result = [Float](repeating: 0, count: len)

        // Local closures mirroring the Pascal nested procedures.
        // AddRampOn writes `rampLen` samples starting at `p`.
        func addRampOn(_ p: inout Int) {
            guard rampLen > 0 else { return }
            for i in 0..<rampLen {
                if p + i < result.count {
                    result[p + i] = rampOn[i]
                }
            }
            p += rampOn.count
        }
        func addRampOff(_ p: inout Int) {
            guard rampLen > 0 else { return }
            for i in 0..<rampLen {
                if p + i < result.count {
                    result[p + i] = rampOff[i]
                }
            }
            p += rampOff.count
        }
        // AddOn writes `dur*samplesInUnit - rampLen` samples of '1'.
        func addOn(_ dur: Int, _ p: inout Int) {
            let n = dur * samplesInUnit - rampLen
            for i in 0..<n {
                if p + i < result.count {
                    result[p + i] = 1
                }
            }
            p += max(0, dur * samplesInUnit - rampLen)
        }
        // AddOff just advances the pointer by `dur*samplesInUnit - rampLen`.
        func addOff(_ dur: Int, _ p: inout Int) {
            p += max(0, dur * samplesInUnit - rampLen)
        }

        var p = 0
        for c in chars {
            switch c {
            case ".":
                addRampOn(&p); addOn(1, &p); addRampOff(&p); addOff(1, &p)
            case "-":
                addRampOn(&p); addOn(3, &p); addRampOff(&p); addOff(1, &p)
            case " ":
                addOff(2, &p)
            case "~":
                addOff(1, &p)
            default:
                break
            }
        }

        return result
    }
}

// MARK: - Global keyer singleton (MakeKeyer / DestroyKeyer / Keyer)

public var Keyer: MorseKey = MorseKey()

public func makeKeyer() {
    Keyer = MorseKey()
    Keyer.rate = DEFAULTRATE
    Keyer.bufSize = Settings.shared.bufSize
}

public func destroyKeyer() {
    // No-op in Swift (ARC manages lifetime); kept for API parity.
}
