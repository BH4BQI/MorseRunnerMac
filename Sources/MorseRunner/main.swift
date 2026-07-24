//
//  main.swift
//  Entry point — launches the NSApplication with our AppDelegate.
//
//  Supports a `--test-audio <seconds>` mode that runs the engine headless and
//  writes a WAV, so the audio path can be verified without a display.
//

import AppKit
import Foundation

let args = CommandLine.arguments

// --run-tests: run the built-in test suite (no Xcode/XCTest needed).
if args.contains("--run-tests") {
    let ok = TestRunner.runAll()
    exit(ok ? 0 : 1)
}

// --test-audio <seconds>: render N seconds of audio (Pile-Up) to a WAV file.
// --test-run <seconds>:   start the real audio engine via run(.pileUp) —
//                         exercises the same path as clicking the Run button.
for flag in ["--test-audio", "--test-run"] {
    if let idx = args.firstIndex(of: flag), idx + 1 < args.count {
        let seconds = Double(args[idx + 1]) ?? 5.0
        MainController.runHeadlessAudioTest(seconds: seconds)
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
