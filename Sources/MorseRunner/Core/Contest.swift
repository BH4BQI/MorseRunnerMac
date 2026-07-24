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
    public var filt: MovingAverage
    public var filt2: MovingAverage
    public var modul: Modulator
    public var ritPhase: Float = 0
    public var fStopPressed: Bool = false
    /// Guards against re-entering the end-of-session block from the audio thread.
    public var sessionEnding: Bool = false

    public init() {
        me = MyStation()
        stations = Stations()
        filt = MovingAverage()
        modul = Modulator()
        agc = VolumeControl()

        filt.points = Int((0.7 * Float(DEFAULTRATE) / Float(Settings.shared.bandWidth)).rounded())
        filt.passes = 3
        filt.samplesInInput = Settings.shared.bufSize
        filt.gainDb = 10 * log10f(500.0 / Float(Settings.shared.bandWidth))

        filt2 = MovingAverage()
        filt2.passes = filt.passes
        filt2.samplesInInput = filt.samplesInInput
        filt2.gainDb = filt.gainDb

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

    public func swapFilters() {
        let f = filt
        filt = filt2
        filt2 = f
        filt2.reset()
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
            for i in 0..<n {
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
            for i in 0..<n {
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

        // LPF: Filt2 then Filt (both cascaded on the same data), and every 10
        // blocks swap them so neither's history grows stale. Faithful to the
        // original `Filt2.Filter(ReIm); ReIm := Filt.Filter(ReIm);`.
        var filtered = filt2.filter(reIm)
        filtered = filt.filter(filtered)
        if (blockNumber % 10) == 0 { swapFilters() }

        // up-convert to pitch
        var audio = modul.modulate(filtered)
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
