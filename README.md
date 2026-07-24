# MorseRunner (macOS port)

A native macOS port of **Morse Runner 1.71**, the CW (Morse code) contest
simulator originally written in Delphi by Alex Shovkoplyas, VE3NEA
(http://www.dxatlas.com/MorseRunner/), with later modifications by BG4FQD.

This is a faithful Swift + AppKit reimplementation that preserves the original's
real-time audio DSP, CW keying, operator AI, four contest modes, and full
keyboard control — running natively on Apple Silicon and Intel Macs.

---

## Features

### Ported from the original

- **Four contest modes**: Pile-Up, Single Calls, WPX Competition, HST Competition.
- **Realistic band conditions**: QRM (interference), QRN (static), QSB (Rayleigh
  fading), Flutter (auroral), LIDS (imperfect operators).
- **Authentic CW audio**: PARIS-standard WPM timing, Blackman-Harris keying
  ramps (click-free), 11025 Hz sample rate, band-pass filtering + AGC.
- **Operator AI**: DX stations use a dynamic-programming callsign matcher and a
  finite-state operating protocol, with skill/patience variation.
- **Full keyboard control**: F1–F8 messages, ESM (Enter Sends Messages), RIT,
  bandwidth & speed hotkeys, wipe/abort, etc. (see Key Assignments below).
- **Scoring**: WPX (points × prefixes) and HST (character-count) scores,
  duplicate/error checking (NIL/DUP/RST/NR), 5-minute QSO-rate histogram.
- **Audio recording** to WAV, **DXCC callsign info bar** (from ARRL.LIST),
  **online score submission** (CRC32-authenticated, compatible with the original
  server format).
- **Settings persistence** via classic INI (`~/Library/Application Support/
  MorseRunner/MorseRunner.ini`).

### New in the macOS port

- **Light / Dark / System theme switching** — via the Settings → Theme menu.
  All controls, the QSO log, histogram, and group boxes adapt to the chosen
  appearance.
- **Window zoom (100% / 150% / 200%)** — via Settings → Zoom. The entire
  window — controls, fonts, spacing — scales proportionally using AppKit's
  frame/bounds coordinate scaling. Useful for high-DPI displays or accessibility.
- **Run/Stop toggle button with dropdown** — the Run button toggles
  Run/Stop (matching the original `tbsDropDown`); the arrow opens a menu to
  pick the contest mode. Stopping and re-running starts a **fresh session**
  (log cleared, scores reset, NR back to 1 — no resume).
- **Callsign-info bar follows selection** — clicking a QSO row in the log
  shows that contact's DXCC info; during a contest the latest QSO is shown.
- **Correct Chk column** — the QSO log's Chk column shows NIL/DUP/RST/NR error
  flags, and each DX station's true data lands in the correct log row even when
  multiple QSOs are saved before DX stations finish (a race-condition fix over
  the original's "last row only" logic).
- **Tab cycling between Call → RST → NR** — Tab/Shift-Tab cycles through the
  three contest input fields, so you can correct a mis-copied callsign without
  losing focus.
- **Custom Morse-code app icon** — a programmatically generated 1024×1024 icon
  depicting the Morse pattern for "CQ" (`-·-· --·-`) on a deep-blue gradient.

---

## Requirements

- macOS 11.0 (Big Sur) or newer.
- Swift 5.9+ toolchain (shipped with Xcode / Command Line Tools).
- Python 3 + Pillow (PIL) — only needed to regenerate the app icon;
  a pre-built `AppIcon-1024.png` is included.

---

## Build & run

### Quick way (builds the `.app` bundle)

```bash
./package.sh
open MorseRunner.app
```

`package.sh` runs `swift build -c release`, executes the built-in test suite,
assembles `MorseRunner.app` with the bundled resources (`MASTER.DTA`,
`ARRL.LIST`, `MorseRunner.ini`), and builds `AppIcon.icns` from
`AppIcon-1024.png` via `sips`/`iconutil`.

> **Note:** if the default `swift` toolchain is unavailable (e.g. the full
> Xcode license hasn't been accepted), `package.sh` auto-detects and falls back
> to the Command Line Tools at `/Library/Developer/CommandLineTools`.

### Debug build (no bundling)

```bash
swift build
.build/debug/MorseRunner       # note: resources load only from the .app bundle
```

### Headless audio smoke test

Render N seconds of engine audio to a WAV without a window (handy for verifying
the DSP pipeline):

```bash
MorseRunner.app/Contents/MacOS/MorseRunner --test-audio 8
# → writes ~/Library/Application Support/MorseRunner/test.wav
```

### Run the test suite

The project ships a built-in test runner (no Xcode/XCTest required — works with
just the Command Line Tools). `package.sh` runs it automatically before bundling.

```bash
swift build && .build/debug/MorseRunner --run-tests
```

**70 tests across 16 suites:**

| Suite | Coverage |
|-------|----------|
| MyStation | Call-field crash regression, incremental typing, call updates. |
| MorseKey | Encoding, PARIS WPM timing, dit/dah ratio, Blackman-Harris ramp shape. |
| DxOperator | Callsign matching (exact / wildcard / one-char-off / too-short). |
| AudioPipeline | `getAudio` produces non-silent signal. |
| ContestFlow (BA4ALC guide) | Pile-Up callers, QSO save, DUP/NIL/RST/NR error codes, NR auto-increment, WPX score, late-DX-truth row matching. |
| Function-key messages (BA4ALC) | F1–F8 + AGN expand to the documented CW text. |
| CW round-trip readability | text → Morse → decode → text for all letters, digits, callsigns. |
| Input formatters | Uppercase callsign field, digit-only RST/NR fields. |
| ESM flow | Enter Sends Messages state machine (Main.pas logic). |
| Field-editor dispatch | GUI thread-safety for text-field command interception. |
| Run button | Toggle, dropdown mode selection, fresh-session reset on re-run. |
| Audio-thread safety | No AppKit calls on the realtime audio thread. |
| Histogram | 5-minute QSO-rate bar chart counts and rendering. |
| Tab field cycling | Call → RST → NR cycling, RST auto-fill. |
| Window & theme | Fixed design size, non-resizable, theme persistence, zoom. |
| Probe (diagnostic) | Prints the message→text mapping for inspection. |

The contest-flow and message suites are modelled on BA4ALC's Morse Runner guide
(https://www.qsl.net/ba4alc/chinese/MORSERUNNER/morserunner.html).

---

## Key assignments (matching the original)

| Key                     | Action                                            |
|-------------------------|---------------------------------------------------|
| `F1`–`F8`               | Send CQ / NR / TU / his-call / my-call / NR? / ? / NIL |
| `Enter`                 | ESM — context-dependent (CQ / call / NR / save)   |
| `Esc`                   | Abort current send                                |
| `Space`                 | Auto-complete input, jump between fields          |
| `;` / `Ins`             | Send his-call + NR                                |
| `.` `+` `,` `[`         | TU + save QSO                                     |
| `Tab` / `Shift-Tab`     | Next / previous field (Call → RST → NR cycle)     |
| `↑` / `↓`               | RIT ±50 Hz                                        |
| `Ctrl-↑` / `Ctrl-↓`     | RX bandwidth ±50 Hz                               |
| `PgUp` / `PgDn`         | CW speed ±5 WPM                                   |
| `Ctrl/Alt-F9` / `Ctrl/Alt-F10` | CW speed ±5 WPM                            |
| `F11` / `Ctrl-W` / `Alt-W` | Wipe input fields                              |

---

## Project layout

```
Sources/MorseRunner/
├── Audio/      DSP: MorseKey, MovingAverage, QuickAverage, Modulator, AgcVolume, AudioEngine, WavFile, SndTypes
├── Core/       Simulation: Station, MyStation, DxStation, DxOperator, QrnStation, QrmStation, Qsb, Stations, Contest, Random
├── Data/       MASTER.DTA + ARRL.LIST loaders (CallList, ArrlList)
├── Log/        QsoLog, Histo (5-min histogram), Crc32
├── State/      Settings (INI persistence), global Keyer
├── App/        AppDelegate, MainController (+Build/+Keys), MainWindow, MainWindowClass,
│               ContestTextField, FlippedView, UpperCaseFormatter, QsoTableModel, ScoreDialog
├── Tests/      16 test suites, 70 tests (TestRunner — no XCTest needed)
└── main.swift / HeadlessTest.swift
Sources/MorseRunner/Resources/   MASTER.DTA, ARRL.LIST, MorseRunner.ini, AppIcon-1024.png, make_icon.py
package.sh                       Build + test + bundle script
```

Each Swift module maps to the original Delphi unit of the same name (e.g.
`MorseKey.swift` ← `MorseKey.pas`), so behaviour can be cross-checked against
the original source.

---

## How it works

The simulation is driven by a single audio callback. Every output buffer:

1. A complex noise floor is generated; QRN/QRM bursts are spawned probabilistically.
2. Each active station's CW envelope block is mixed in (with its own BFO phase
   and RIT offset); the local station's self-monitor audio is added (with QSK
   half-duplex gain reduction).
3. The composite I/Q signal passes through the cascaded moving-average band-pass
   filter, is up-converted to the CW pitch by the modulator, and runs through
   the log-domain AGC.
4. Every station is ticked; finished DX QSOs are scored into the log; the
   pile-up scheduler spawns new callers as needed; the session ends on timeout.

The numeric constants (filter lengths, AGC beta, probability thresholds,
callsign-match weights, PARIS timing) are copied verbatim from the Delphi
source so the audio character and operating behaviour match the original.

---

## Data files

`MASTER.DTA` (1.1 MB) is the callsign pool: a 1370-int32 index header followed
by null-terminated ASCII callsigns (~44k unique after de-duplication).
`ARRL.LIST` is the DXCC country/prefix table used for the callsign info bar.
Both are bundled in the app and read from `Bundle.main` resources at launch.

---

## App icon

The icon is generated by `Sources/MorseRunner/Resources/make_icon.py` (Python +
Pillow). It renders the Morse code for "CQ" — the universal CW call:

- **C** = `-·-·` (dah dit dah dit)
- **Q** = `--·-` (dah dah dit dah)

Drawn as bright cyan dots and dashes on a deep-blue gradient with rounded
corners (the macOS "squircle"). The 1024×1024 master PNG is downscaled to all
10 standard `.iconset` sizes (16–512, including @2x Retina) and assembled into
`AppIcon.icns` by `package.sh`. To regenerate:

```bash
cd Sources/MorseRunner/Resources && python3 make_icon.py
```

---

## Development notes

### Coordinate system & layout

The window uses a flipped content view (`isFlipped = true`, top-left origin)
so all controls can be placed using the original Delphi DFM `Left`/`Top`
coordinates directly — no Auto Layout, no constraints. The layout code in
`MainController+Build.swift` mirrors `Main.dfm` line-for-line.

### Audio thread safety

The realtime Core Audio callback must never touch AppKit (it runs on a
high-priority thread where `makeFirstResponder`, `reloadData`, etc. would
crash). All UI mutations triggered from the audio thread (score updates, log
inserts, mode changes) are dispatched to the main thread via
`DispatchQueue.main.async`.

### Zoom implementation

Window zoom uses AppKit's frame/bounds coordinate scaling: the contentView's
`frame` is set to the scaled window size while its `bounds` stays at the design
size (730×470). AppKit automatically scales all subview positions and drawing
by the frame/bounds ratio — clean, reversible, and GPU-accelerated.

---

## Tools & technology

| Component | Technology |
|-----------|-----------|
| Language | Swift 5.9+ |
| UI framework | AppKit (native macOS, no Electron/web) |
| Audio | Core Audio (`AudioUnit`, 11025 Hz mono Float32) |
| Build | Swift Package Manager (`swift build`) |
| Bundling | `package.sh` (shell + `sips` + `iconutil`) |
| Testing | Built-in test runner (no Xcode/XCTest dependency) |
| Icon generation | Python 3 + Pillow (PIL) |
| Thread safety | `os_unfair_lock`, `DispatchQueue.main.async` |
| Settings | Classic Windows INI format (backwards-compatible keys) |

### AI-assisted development

This port was developed with the assistance of **ZCode** (powered by
**GLM-5.2** by Z.ai), an AI coding agent. The AI was used for:

- Translating 22 Delphi units (~3000 lines of Pascal) to Swift, preserving
  numeric constants and algorithm semantics.
- Debugging realtime audio crashes (audio-thread → AppKit violations).
- Designing the macOS-native UI layout matching the original DFM coordinates.
- Generating the Morse-code app icon and the build/packaging pipeline.
- Writing and maintaining the 70-test suite.

All AI-generated code was reviewed and tested against the original's behaviour.

---

## License

The original Morse Runner is licensed under the Mozilla Public License 2.0
(MPL-2.0); this macOS port preserves that license. Original copyright
© 2004–2016 Alex Shovkoplyas, VE3NEA; modifications by BG4FQD; macOS port
by BH4BQI.
