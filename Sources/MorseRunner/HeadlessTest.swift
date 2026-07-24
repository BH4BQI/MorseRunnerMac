//
//  HeadlessTest.swift
//  Headless audio-render smoke test: drives the Contest engine for N seconds
//  without a window and writes the result to a WAV, so we can verify the DSP
//  pipeline produces real CW audio.
//

import Foundation

extension MainController {
    /// Run the engine headless for `seconds`, rendering audio to
    /// `~/Library/Application Support/MorseRunner/test.wav`. Requires resources
    /// to be locatable via Bundle.main (works inside the .app bundle).
    /// Run the engine headless for `seconds`, rendering audio to a WAV without
    /// a window, so we can verify the DSP pipeline produces real CW audio.
    ///
    /// There are two modes:
    ///  - `--test-audio N`        : manual render loop (no Core Audio playback)
    ///  - `--test-run N`          : use the real `run(.pileUp)` path, which
    ///                               STARTS the Core Audio engine — exercises the
    ///                               audio-thread → main-thread UI handoff that the
    ///                               Run button triggers in the GUI.
    static func runHeadlessAudioTest(seconds: Double) {
        let useRealRun = CommandLine.arguments.contains("--test-run")
        runTest(seconds: seconds, useRealRun: useRealRun)
    }

    static func runTest(seconds: Double, useRealRun: Bool) {
        // Bootstrap the controller without showing the window.
        let controller = MainController()
        MainController.shared = controller

        LoadCallList()
        ArrlList.shared.loadIfNeeded()
        Ini.load(into: controller)
        makeKeyer()
        Keyer.rate = DEFAULTRATE
        Keyer.bufSize = Settings.shared.bufSize

        print("Call list loaded: \(CallList.shared.calls.count) calls")
        print("Settings: call=\(Settings.shared.call) wpm=\(Settings.shared.wpm) pitch=\(Settings.shared.pitch) bw=\(Settings.shared.bandWidth)")

        if useRealRun {
            // Exercise the EXACT path the Run button takes: run(.pileUp) starts
            // the Core Audio engine, and the realtime callback drives the
            // contest. We spin a RunLoop so main-thread dispatches (UI updates,
            // score popups) get serviced — this is what the GUI does via
            // NSApplication.run(). Crash here = same crash as clicking Run.
            print("Mode: real run(.pileUp) with live Core Audio engine")
            Settings.shared.duration = max(1, Int(ceil(seconds / 60.0)) + 1)
            controller.run(.pileUp)
            // Kick off a CQ once the engine is up.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                Tst.me.sendMsg(.cq)
            }
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            let engine = controller.audioEngine
            controller.run(.stop)
            print("  survived \(seconds)s of live playback — no crash.")
            print("  stations active: \(Tst.stations.count)")
            print("  QSOs logged: \(QsoLog.shared.qsoList.count)")
            print("  audio callbacks: \(engine.totalCallbacks), underruns: \(engine.underruns)")
            if engine.underruns == 0 {
                print("  OK: continuous audio (no underruns).")
            } else {
                let pct = 100.0 * Double(engine.underruns) / Double(max(1, engine.totalCallbacks))
                print(String(format: "  NOTE: %.1f%% of callbacks had underruns.", pct))
            }
            return
        }

        // Manual render path: enter a Pile-Up session WITHOUT starting Core
        // Audio playback (we render to a WAV instead).
        Settings.shared.runMode = .pileUp
        Tst.initContest()
        Settings.shared.saveWav = false

        // Send a CQ so callers respond.
        Tst.me.sendMsg(.cq)

        // Open a WAV to capture output.
        let wav = WavFile()
        wav.fileName = FileManager.default.applicationSupportDirectory
            .appendingPathComponent("test.wav").path
        wav.openWrite()

        let bufSize = Settings.shared.bufSize
        let totalSamples = Int(seconds * Double(DEFAULTRATE))
        var rendered = 0
        var maxAbs: Float = 0
        var nonZero = 0
        while rendered < totalSamples {
            let block = Tst.getAudio(count: bufSize)
            let n = min(block.count, totalSamples - rendered)
            block.withUnsafeBufferPointer { ptr in
                wav.write(from: ptr.baseAddress!, right: nil, count: n)
            }
            for i in 0..<n {
                let a = abs(block[i])
                if a > maxAbs { maxAbs = a }
                if a > 1 { nonZero += 1 }
            }
            rendered += n
        }
        wav.close()

        print(String(format: "Rendered %.1f s (%d samples)", seconds, rendered))
        print(String(format: "  peak amplitude: %.1f  (expect non-zero, ~thousands)", maxAbs))
        print("  non-zero samples: \(nonZero) / \(rendered)  (\(String(format: "%.1f%%", 100.0 * Double(nonZero) / Double(max(1,rendered)))))")
        print("  stations active: \(Tst.stations.count)")
        print("  QSOs logged: \(QsoLog.shared.qsoList.count)")
        print("  WAV written to: \(wav.fileName)")
        if maxAbs < 1 {
            print("  WARNING: Audio is silent — DSP pipeline may have an issue.")
        } else {
            print("  OK: Audio pipeline producing signal.")
        }
    }
}
