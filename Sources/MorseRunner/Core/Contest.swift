//
//  Contest.swift
//  Port of Contest.pas — TContest.
//
//  The simulation controller. `getAudio(count:)` is called by the AudioEngine
//  for every output buffer; it assembles the current audio block from all
//  active stations + noise, runs it through the band-pass filter + modulator +
//  AGC, then advances every station by one tick.
//

import Foundation

public final class Contest: AudioSampleProvider {
    public static var shared: Contest!

    public var blockNumber: Int = 0
    public var me: MyStation
    public var stations: Stations
    public var agc: VolumeControl
    public var modul: Modulator
    public var ritPhase: Float = 0
    public var fStopPressed: Bool = false
    /// Guards against re-entering the end-of-session block from the audio thread.
    public var sessionEnding: Bool = false

    // Dual cascaded filter pairs for multipath/fading simulation.
    // Each pair is a 2-stage cascade (stage1 → stage2), matching the original
    // Delphi `Filt2.Filter(ReIm); ReIm := Filt.Filter(ReIm)`.
    // Pair A and Pair B alternate every 10 blocks via Equal-Power Crossfade
    // (no Reset — both pairs run continuously to avoid click artifacts).
    public var filtA1: MovingAverage
    public var filtA2: MovingAverage
    public var filtB1: MovingAverage
    public var filtB2: MovingAverage

    /// Which filter pair is currently dominant (0 = A, 1 = B).
    private var activePair: Int = 0
    /// True while a crossfade transition is in progress.
    private var isCrossfading: Bool = false
    /// Current position within the crossfade (in global sample count).
    private var crossfadePos: Int = 0
    /// Crossfade duration in samples (~20ms at 11025Hz).
    private let crossfadeLen: Int = Int(0.020 * Float(DEFAULTRATE))
    /// Pre-computed cos/sin gain table for equal-power crossfade.
    private var crossfadeGainOut: [Float] = []
    private var crossfadeGainIn: [Float] = []
    /// Reusable buffers for the parallel filter outputs (zero-alloc hot path).
    private var bufA: ReImArrays = ReImArrays()
    private var bufB: ReImArrays = ReImArrays()
    /// Global sample counter for crossfade tracking (across block boundaries).
    private var globalSampleIdx: Int = 0

    /// Backward-compat: `filt` is the primary filter (used by setBw/setPitch).
    public var filt: MovingAverage { activePair == 0 ? filtA2 : filtB2 }

    public init() {
        me = MyStation()
        stations = Stations()
        filtA1 = MovingAverage()
        filtA2 = MovingAverage()
        filtB1 = MovingAverage()
        filtB2 = MovingAverage()
        modul = Modulator()
        agc = VolumeControl()

        func configure(_ f: MovingAverage) {
            f.points = Int((0.7 * Float(DEFAULTRATE) / Float(Settings.shared.bandWidth)).rounded())
            f.passes = 3
            f.samplesInInput = Settings.shared.bufSize
            f.gainDb = 10 * log10f(500.0 / Float(Settings.shared.bandWidth))
        }
        configure(filtA1); configure(filtA2)
        configure(filtB1); configure(filtB2)

        // Pre-compute equal-power crossfade gain table.
        crossfadeGainOut = [Float](repeating: 0, count: crossfadeLen)
        crossfadeGainIn = [Float](repeating: 0, count: crossfadeLen)
        for i in 0..<crossfadeLen {
            let t = Float(i) / Float(crossfadeLen - 1)
            crossfadeGainOut[i] = cosf(HALF_PI * t)   // fade out (1→0)
            crossfadeGainIn[i] = sinf(HALF_PI * t)    // fade in (0→1)
        }

        modul.samplesPerSec = DEFAULTRATE
        modul.carrierFreq = Float(Settings.shared.pitch)

        agc.noiseInDb = 76
        agc.noiseOutDb = 76
        agc.attackSamples = 155   // AGC attack ~5 ms
        agc.holdSamples = 155
        agc.agcEnabled = true

        Contest.shared = self
        initContest()
    }

    public func initContest() {
        me.initStation()
        stations.clear()
        blockNumber = 0
        sessionEnding = false
        fStopPressed = false
        // Reset crossfade state for a fresh session.
        activePair = 0
        isCrossfading = false
        crossfadePos = 0
        globalSampleIdx = 0
    }

    public func minute() -> Float {
        return blocksToSeconds(Float(blockNumber)) / 60.0
    }

    /// Count active DX stations not yet done.
    public func dxCount() -> Int {
        var result = 0
        for s in stations.items {
            if let dx = s as? DxStation, dx.oper.state != .done {
                result += 1
            }
        }
        return result
    }

    // MARK: audio main loop

    private static let NOISE_AMP: Float = 6000

    public func getAudio(count: Int) -> [Float] {
        // The Pascal code reads Ini.BufSize samples per block; the audio device
        // may request a different count. We always produce BufSize samples and
        // let the engine hand whatever it needs to the device (zero-padded).
        let n = Settings.shared.bufSize
        var result = [Float](repeating: 0, count: 1)
        blockNumber += 1
        if blockNumber < 6 { return result }

        var reIm = ReImArrays()
        reIm.setLength(n)

        // complex noise floor
        let amp = Contest.NOISE_AMP
        for i in 0..<n {
            reIm.re[i] = 3 * amp * (rnd() - 0.5)
            reIm.im[i] = 3 * amp * (rnd() - 0.5)
        }

        // QRN
        if Settings.shared.qrn {
            // background spikes
            for i in 0..<n {
                if rnd() < 0.01 { reIm.re[i] = 60 * amp * (rnd() - 0.5) }
            }
            // occasional burst
            if rnd() < 0.01 { stations.addQrn() }
        }

        // QRM
        if Settings.shared.qrm && rnd() < 0.0002 { stations.addQrm() }

        // audio from each active station
        for s in stations.items {
            guard s.state == .sending else { continue }
            let blk = s.getBlock()
            let baseBfo = s.currentBfo()
            // Use blk.count (not n/bufSize) so short blocks at the end of a
            // station's envelope don't read past the array (which caused clicks).
            for i in 0..<blk.count {
                let bfo = baseBfo - ritPhase - Float(i) * TWO_PI * Float(Settings.shared.rit) / Float(DEFAULTRATE)
                reIm.re[i] += blk[i] * cosf(bfo)
                reIm.im[i] -= blk[i] * sinf(bfo)
            }
        }

        // RIT phase accumulation
        ritPhase += Float(n) * TWO_PI * Float(Settings.shared.rit) / Float(DEFAULTRATE)
        while ritPhase > TWO_PI { ritPhase -= TWO_PI }
        while ritPhase < -TWO_PI { ritPhase += TWO_PI }

        // my audio (self-monitoring)
        if me.state == .sending {
            let blk = me.getBlock()
            let smg = powf(10, (Settings.shared.selfMonVolume - 0.75) * 4)
            var rfg: Float = 1
            for i in 0..<blk.count {
                if Settings.shared.qsk {
                    let target: Float = 1 - blk[i] / me.amplitude
                    if rfg > target {
                        rfg = target
                    } else {
                        rfg = rfg * 0.997 + 0.003
                    }
                    reIm.re[i] = smg * blk[i] + rfg * reIm.re[i]
                    reIm.im[i] = smg * blk[i] + rfg * reIm.im[i]
                } else {
                    reIm.re[i] = smg * blk[i]
                    reIm.im[i] = smg * blk[i]
                }
            }
        }

        // LPF: dual cascaded filter pairs with Equal-Power Crossfade.
        // Both pairs (A and B) run in parallel on a copy of the input. Every
        // 10 blocks they swap dominance via a 20ms cos/sin crossfade — this
        // restores the original MorseRunner's multipath/fading texture without
        // the click artifacts caused by the original's hard Reset on swap.
        // Both pairs stay "hot" (never reset), so the crossfade is seamless.
        bufA.re = reIm.re; bufA.im = reIm.im
        bufB.re = reIm.re; bufB.im = reIm.im
        // Cascade pair A: filtA1 → filtA2
        filtA1.filterInPlace(&bufA)
        filtA2.filterInPlace(&bufA)
        // Cascade pair B: filtB1 → filtB2
        filtB1.filterInPlace(&bufB)
        filtB2.filterInPlace(&bufB)

        // Check if it's time to start a crossfade (every 10 blocks).
        if (blockNumber % 10) == 0 && blockNumber > 0 && !isCrossfading {
            isCrossfading = true
            crossfadePos = 0
        }

        // Mix the two filtered outputs: use crossfade gains during transition,
        // otherwise just the active pair at full gain.
        if isCrossfading {
            // Per-sample crossfade across block boundaries (globalSampleIdx tracks position).
            for i in 0..<n {
                let gOut: Float, gIn: Float
                if crossfadePos < crossfadeLen {
                    gOut = crossfadeGainOut[crossfadePos]
                    gIn = crossfadeGainIn[crossfadePos]
                } else {
                    gOut = 0; gIn = 1
                }
                // activePair's output fades out, the other fades in.
                if activePair == 0 {
                    reIm.re[i] = gOut * bufA.re[i] + gIn * bufB.re[i]
                    reIm.im[i] = gOut * bufA.im[i] + gIn * bufB.im[i]
                } else {
                    reIm.re[i] = gOut * bufB.re[i] + gIn * bufA.re[i]
                    reIm.im[i] = gOut * bufB.im[i] + gIn * bufA.im[i]
                }
                crossfadePos += 1
                if crossfadePos >= crossfadeLen {
                    isCrossfading = false
                    activePair = activePair == 0 ? 1 : 0
                }
            }
        } else {
            // No crossfade in progress — use the active pair at full gain.
            if activePair == 0 {
                reIm.re = bufA.re; reIm.im = bufA.im
            } else {
                reIm.re = bufB.re; reIm.im = bufB.im
            }
        }

        // up-convert to pitch
        var audio = modul.modulate(reIm)
        // AGC
        audio = agc.process(audio)

        // WAV recording
        if Settings.shared.saveWav, let wav = MainController.shared?.wavFile, wav.isOpen {
            audio.withUnsafeBufferPointer { ptr in
                wav.write(from: ptr.baseAddress!, right: nil, count: audio.count)
            }
        }

        // advance every station by one tick
        me.tick()
        for s in stations.items { s.tick() }

        // DX done → write its true data into the matching log entry.
        // dataToLastQso() searches the log for the QSO whose call matches this
        // DX's true call (and isn't filled yet), so it lands in the right row
        // even when several QSOs were saved before this DX finished (pile-up).
        for s in stations.items {
            if let dx = s as? DxStation,
               dx.oper.state == .done,
               QsoLog.shared.hasUnfilledQso(for: dx.myCall) {
                dx.dataToLastQso()   // fills the row + recomputes its err flag
                if Settings.shared.runMode == .hst {
                    QsoLog.shared.updateStatsHst()
                } else {
                    QsoLog.shared.updateStats()
                }
            }
        }

        // UI updates
        QsoLog.shared.showRate()
        let secs = blocksToSeconds(Float(blockNumber)) / 86400.0
        let timeStr = formatClock(secs)
        let dxs = dxCount()
        MainController.shared?.updateRunningDisplay(timeText: timeStr,
                                                    pileUpCount: dxs,
                                                    isPileUp: Settings.shared.runMode == .pileUp)

        // Mode-specific caller scheduling
        if Settings.shared.runMode == .single, dxCount() == 0 {
            me.msg = .cq       // no need to actually send CQ in this mode
            let caller = stations.addCaller()
            caller.processEvent(.meFinished)
        } else if Settings.shared.runMode == .hst, dxCount() < Settings.shared.activity {
            me.msg = .cq
            let need = Settings.shared.activity - dxCount()
            for _ in 0..<need {
                let caller = stations.addCaller()
                caller.processEvent(.meFinished)
            }
        }

        // End of session. This runs on the realtime audio thread, so we must
        // NOT call AppKit here. Defer the actual stop + score popup to the main
        // thread, and use `sessionEnding` to ensure we only fire once.
        let elapsedMin = blocksToSeconds(Float(blockNumber)) / 60.0
        if (elapsedMin >= Float(Settings.shared.duration) || fStopPressed) && !sessionEnding {
            sessionEnding = true
            let wasStop = fStopPressed
            let mode = Settings.shared.runMode
            DispatchQueue.main.async {
                if mode == .hst {
                    MainController.shared?.run(.stop)
                    MainController.shared?.popupScoreHst()
                } else if mode == .wpx, !wasStop {
                    MainController.shared?.run(.stop)
                    MainController.shared?.popupScoreWpx()
                } else {
                    MainController.shared?.run(.stop)
                }
            }
            fStopPressed = false
        }

        result = audio
        return result
    }

    public func onMeFinishedSending() {
        let runMode = Settings.shared.runMode
        // stations that heard my CQ and want to call
        if runMode != .single, runMode != .hst {
            let cq = me.msg.contains(.cq)
            let tuAndMyCall = me.msg.contains(.tu) && me.msg.contains(.myCall)
            if cq || (tuAndMyCall && !QsoLog.shared.qsoList.isEmpty) {
                let n = rndPoisson(Float(Settings.shared.activity) / 2)
                for _ in 0..<n { stations.addCaller() }
            }
        }
        // tell everyone I finished sending
        for s in stations.items { s.processEvent(.meFinished) }
    }

    public func onMeStartedSending() {
        for s in stations.items { s.processEvent(.meStarted) }
    }

    // Format seconds-fraction-of-day as hh:nn:ss.
    private func formatClock(_ dayFraction: Float) -> String {
        let total = Int(dayFraction * 86400)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

// MARK: - Global singleton accessor (mirrors Delphi `Tst`)

public var Tst: Contest {
    return Contest.shared
}
