// swift-tools-version:5.9
//
// MorseRunner - macOS port of VE3NEA's CW Contest Simulator
// Copyright (C) 2004-2016 Alex Shovkoplyas, VE3NEA (original Delphi)
// macOS port preserves the MPL-2.0 license of the original.
//
// Single executable target. Tests run via the `--run-tests` flag (a tiny
// built-in runner) so they work without Xcode/XCTest — this environment only
// has the Command Line Tools. See Sources/MorseRunner/Tests/TestRunner.swift.

import PackageDescription

let package = Package(
    name: "MorseRunner",
    platforms: [.macOS(.v11)],
    targets: [
        .executableTarget(
            name: "MorseRunner",
            path: "Sources/MorseRunner",
            exclude: ["Tests/README.md"],
            resources: [
                .copy("Resources/MASTER.DTA"),
                .copy("Resources/ARRL.LIST"),
                .copy("Resources/MorseRunner.ini"),
                .copy("Resources/MorseRunner.ico"),
            ]
        )
    ]
)
