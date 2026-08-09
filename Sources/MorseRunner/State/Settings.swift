//
//  Settings.swift
//  Port of Ini.pas — global configuration variables.
//
//  These mirror the Delphi `Ini` unit's module-level vars so that the rest of
//  the engine can reference them exactly as the original code did.
//

import Foundation

// MARK: - Run mode (Ini.pas: TRunMode)

public enum RunMode: Int {
    case stop = 0
    case pileUp = 1
    case single = 2
    case wpx = 3
    case hst = 4
}

// MARK: - Constants (Ini.pas)

public let SEC_STN = "Station"
public let SEC_BND = "Band"
public let SEC_TST = "Contest"
public let SEC_SYS = "System"

public let DEFAULTBUFCOUNT = 8
public let DEFAULTBUFSIZE = 512
public let DEFAULTRATE = 11025
public let DEFAULTWEBSERVER = "http://www.dxatlas.com/MorseRunner/MrScore.asp"

/// Sentinel used throughout Station.pas for "no timeout".
public let NEVER = Int.max

// MARK: - Global settings (Ini.pas vars)

/// Global, mutable configuration state — the single source of truth shared by
/// the engine. Access via `Settings.shared`.
public final class Settings {
    public static let shared = Settings()

    // Station
    public var call: String = "VE3NEA"
    public var hamName: String = ""
    public var wpm: Int = 30
    public var bandWidth: Int = 500
    public var pitch: Int = 600
    public var qsk: Bool = true
    public var rit: Int = 0
    public var bufSize: Int = DEFAULTBUFSIZE
    public var selfMonVolume: Float = 0.75   // VolumeSlider1.Value, range 0..1, default 0.75

    // System / web
    public var webServer: String = DEFAULTWEBSERVER
    public var submitHiScoreURL: String = ""
    public var postMethod: String = "POST"
    public var showCallsignInfo: Bool = true
    /// URL for downloading the latest MASTER.DTA call database.
    public var callDatabaseURL: String = "https://supercheckpartial.com/downloads/MASTER.DTA"
    /// UI theme: 0 = follow system, 1 = light, 2 = dark.
    public var theme: Int = 0
    /// UI zoom level: 0 = 100%, 1 = 150%, 2 = 200%.
    public var zoom: Int = 0

    // Band conditions
    public var activity: Int = 2
    public var qrn: Bool = true
    public var qrm: Bool = true
    public var qsb: Bool = true
    public var flutter: Bool = true
    public var lids: Bool = true

    // Contest
    public var duration: Int = 30
    public var runMode: RunMode = .stop
    public var hiScore: Int = 0
    public var compDuration: Int = 60

    // Misc
    public var saveWav: Bool = false
    public var callsFromKeyer: Bool = false

    private init() {}
}

/// Convenience accessor mirroring the Delphi unit's bare global names.
public var Ini: Settings { Settings.shared }

// MARK: - UI synchronizer

/// Implemented by the main UI controller so that loaded settings can be pushed
/// back into the on-screen controls. Decouples Settings from AppKit.
public protocol SettingsSynchronizer: AnyObject {
    var pitchIndex: Int { get }
    var bandwidthIndex: Int { get }
    var selfMonValue: Float { get }
    func setMyCall(_ call: String)
    func setPitch(_ idx: Int)
    func setBw(_ idx: Int)
    func setWpm(clamping wpm: Int, lo: Int, hi: Int)
    func setQsk(_ value: Bool)
    func setSelfMonVolume(raw: Int)
    func setActivity(_ value: Int)
    func setDuration(_ value: Int)
}

// MARK: - Persistence (FromIni / ToIni) — classic Windows INI text format

extension Settings {
    /// User settings file: `~/Library/Application Support/MorseRunner/MorseRunner.ini`.
    private var iniURL: URL {
        FileManager.default.applicationSupportDirectory
            .appendingPathComponent("MorseRunner.ini")
    }

    /// Default settings: the MorseRunner.ini shipped in the app bundle.
    private var bundledIniURL: URL? {
        Bundle.main.url(forResource: "MorseRunner", withExtension: "ini")
    }

    /// Parse a classic INI file into `[Section: [Key: Value]]`.
    /// Values are kept as raw strings; typed accessors do the conversion.
    private func parseINI(_ text: String) -> [String: [String: String]] {
        var sections: [String: [String: String]] = [:]
        var current = ""
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                current = String(line.dropFirst().dropLast())
                sections[current] = [:]
            } else if let eq = line.firstIndex(of: "=") {
                let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
                let val = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                sections[current, default: [:]][key] = val
            }
        }
        return sections
    }

    /// On first run, copy the bundled data files (MASTER.DTA, ARRL.LIST) into
    /// `~/Library/Application Support/MorseRunner/` so the user can find, edit,
    /// and replace them. The INI is NOT seeded here — it's created by save()
    /// on first quit, which correctly reflects the loaded settings.
    /// Files that already exist are never overwritten (user edits preserved).
    /// Call this once at launch, before load().
    public func seedUserDataIfNeeded() {
        let dir = FileManager.default.applicationSupportDirectory
        let fm = FileManager.default
        let resources: [(bundle: String, ext: String, fileName: String)] = [
            ("MASTER", "DTA",  "MASTER.DTA"),
            ("ARRL",   "LIST", "ARRL.LIST"),
        ]
        for (name, ext, fileName) in resources {
            let dest = dir.appendingPathComponent(fileName)
            guard !fm.fileExists(atPath: dest.path) else { continue }  // don't overwrite
            guard let src = Bundle.main.url(forResource: name, withExtension: ext) else { continue }
            try? fm.copyItem(at: src, to: dest)
        }
    }

    /// Load defaults from the bundled INI, then overlay the user INI if present.
    public func load(into sync: SettingsSynchronizer? = nil) {
        var sections: [String: [String: String]] = [:]
        if let url = bundledIniURL, let txt = try? String(contentsOf: url, encoding: .utf8) {
            sections = parseINI(txt)
        }
        if let txt = try? String(contentsOf: iniURL, encoding: .utf8) {
            let user = parseINI(txt)
            for (k, v) in user { sections[k, default: [:]].merge(v, uniquingKeysWith: { _, new in new }) }
        }

        let stn = sections[SEC_STN] ?? [:]
        let bnd = sections[SEC_BND] ?? [:]
        let tst = sections[SEC_TST] ?? [:]
        let sys = sections[SEC_SYS] ?? [:]

        // typed helpers
        func sInt(_ d: [String: String], _ k: String) -> Int? { d[k].flatMap { Int($0) } }
        func sBool(_ d: [String: String], _ k: String) -> Bool? {
            guard let v = d[k] else { return nil }
            return v == "1" || v.lowercased() == "true"
        }
        func sStr(_ d: [String: String], _ k: String) -> String? { d[k] }

        if let s = sync {
            if let c = sStr(stn, "Call") { s.setMyCall(c.trimmingCharacters(in: .whitespaces)) }
            if let p = sInt(stn, "Pitch") { s.setPitch(p) }
            if let b = sInt(stn, "BandWidth") { s.setBw(b) }
            if let w = sInt(stn, "Wpm") { s.setWpm(clamping: w, lo: 10, hi: 120) }
            if let q = sBool(stn, "Qsk") { s.setQsk(q) }
            if let sm = sInt(stn, "SelfMonVolume") { s.setSelfMonVolume(raw: sm) }
            if let sw = sBool(stn, "SaveWav") { saveWav = sw }
            callsFromKeyer = sBool(stn, "CallsFromKeyer") ?? callsFromKeyer
            hamName = sStr(stn, "Name") ?? hamName
            if let a = sInt(bnd, "Activity") { s.setActivity(a) }
            if let v = sBool(bnd, "Qrn") { qrn = v }
            if let v = sBool(bnd, "Qrm") { qrm = v }
            if let v = sBool(bnd, "Qsb") { qsb = v }
            if let v = sBool(bnd, "Flutter") { flutter = v }
            if let v = sBool(bnd, "Lids") { lids = v }
            if let dur = sInt(tst, "Duration") { s.setDuration(dur) }
            hiScore = sInt(tst, "HiScore") ?? hiScore
            if let cd = sInt(tst, "CompetitionDuration") {
                compDuration = max(1, min(60, cd))
            }
        } else {
            call = sStr(stn, "Call") ?? call
            pitch = 300 + (sInt(stn, "Pitch") ?? 3) * 50
            bandWidth = 100 + (sInt(stn, "BandWidth") ?? 9) * 50
            wpm = max(10, min(120, sInt(stn, "Wpm") ?? wpm))
            qsk = sBool(stn, "Qsk") ?? qsk
            callsFromKeyer = sBool(stn, "CallsFromKeyer") ?? callsFromKeyer
            hamName = sStr(stn, "Name") ?? hamName
            activity = sInt(bnd, "Activity") ?? activity
            qrn = sBool(bnd, "Qrn") ?? qrn
            qrm = sBool(bnd, "Qrm") ?? qrm
            qsb = sBool(bnd, "Qsb") ?? qsb
            flutter = sBool(bnd, "Flutter") ?? flutter
            lids = sBool(bnd, "Lids") ?? lids
            duration = sInt(tst, "Duration") ?? duration
            hiScore = sInt(tst, "HiScore") ?? hiScore
            if let cd = sInt(tst, "CompetitionDuration") { compDuration = max(1, min(60, cd)) }
        }

        webServer = sStr(sys, "WebServer") ?? webServer
        submitHiScoreURL = sStr(sys, "SubmitHiScoreURL") ?? submitHiScoreURL
        postMethod = (sStr(sys, "PostMethod") ?? "POST").uppercased()
        showCallsignInfo = sBool(sys, "ShowCallsignInfo") ?? showCallsignInfo
        callDatabaseURL = sStr(sys, "CallDatabaseURL") ?? callDatabaseURL
        theme = sInt(sys, "Theme") ?? theme
        zoom = sInt(sys, "Zoom") ?? zoom

        // BufSize: 1..5, default 3 → 64 << V
        var v = sInt(sys, "BufSize") ?? 3
        if v == 0 { v = 3 }
        v = max(1, min(5, v))
        bufSize = 64 << v
    }

    public func save(from sync: SettingsSynchronizer? = nil) {
        let pitchIdx = sync?.pitchIndex ?? ((pitch - 300) / 50)
        let bwIdx = sync?.bandwidthIndex ?? ((bandWidth - 100) / 50)
        let smValue: Float = sync?.selfMonValue ?? selfMonVolume
        let smRaw = Int(((smValue - 0.75) * 80.0).rounded())
        let bufV = Int(log2(Double(bufSize)) - 6)   // inverse of 64 << V

        func b2i(_ b: Bool) -> String { b ? "1" : "0" }

        var lines: [String] = []
        lines.append("[\(SEC_SYS)]")
        lines.append("BufSize=\(bufV)")
        lines.append("WebServer=\(webServer)")
        lines.append("PostMethod=\(postMethod)")
        lines.append("SubmitHiScoreURL=\(submitHiScoreURL)")
        lines.append("ShowCallsignInfo=\(b2i(showCallsignInfo))")
        lines.append("CallDatabaseURL=\(callDatabaseURL)")
        lines.append("Theme=\(theme)")
        lines.append("Zoom=\(zoom)")
        lines.append("[\(SEC_STN)]")
        lines.append("Call=\(call)")
        lines.append("Pitch=\(pitchIdx)")
        lines.append("BandWidth=\(bwIdx)")
        lines.append("Wpm=\(wpm)")
        lines.append("Qsk=\(b2i(qsk))")
        lines.append("SelfMonVolume=\(smRaw)")
        lines.append("SaveWav=\(b2i(saveWav))")
        lines.append("CallsFromKeyer=\(b2i(callsFromKeyer))")
        lines.append("Name=\(hamName)")
        lines.append("[\(SEC_BND)]")
        lines.append("Activity=\(activity)")
        lines.append("Qrn=\(b2i(qrn))")
        lines.append("Qrm=\(b2i(qrm))")
        lines.append("Qsb=\(b2i(qsb))")
        lines.append("Flutter=\(b2i(flutter))")
        lines.append("Lids=\(b2i(lids))")
        lines.append("[\(SEC_TST)]")
        lines.append("Duration=\(duration)")
        lines.append("HiScore=\(hiScore)")
        lines.append("CompetitionDuration=\(compDuration)")

        let text = lines.joined(separator: "\n") + "\n"
        try? FileManager.default.createDirectory(
            at: iniURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: iniURL, atomically: true, encoding: .utf8)
    }
}

// MARK: - App support directory helper

extension FileManager {
    /// `~/Library/Application Support/MorseRunner/` (created lazily).
    var applicationSupportDirectory: URL {
        let base = urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("MorseRunner", isDirectory: true)
        try? createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
