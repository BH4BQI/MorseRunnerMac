//
//  CallList.swift
//  Port of CallLst.pas.
//
//  Loads the MASTER.DTA callsign database. The file format is:
//    [0 .. INDEXSIZE*4)  : int32 index array (sorted start offsets)
//    [INDEXSIZE*4 ..)    : null-terminated ASCII callsign strings
//  Duplicate calls are removed. In HST mode, a picked call is consumed.
//

import Foundation

public final class CallList {
    public static let shared = CallList()

    public private(set) var calls: [String] = []

    private init() {}

    /// Characters used to compute the 2-D index. (Length 37 → 37² + 1 entries.)
    private static let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/"
    private static var indexSize: Int { CallList.chars.count * CallList.chars.count + 1 }

    public func load() {
        calls.removeAll()
        // Prefer the user-replaceable copy in ~/Library/Application Support/MorseRunner/,
        // fall back to the bundled read-only copy.
        let dir = FileManager.default.applicationSupportDirectory
        let userURL = dir.appendingPathComponent("MASTER.DTA")
        let url: URL
        if FileManager.default.fileExists(atPath: userURL.path) {
            url = userURL
        } else if let bundled = Bundle.main.url(forResource: "MASTER", withExtension: "DTA") {
            url = bundled
        } else {
            return
        }
        guard let data = try? Data(contentsOf: url) else {
            return
        }
        let indexBytes = CallList.indexSize * 4
        guard data.count >= indexBytes else { return }

        // Read index array (little-endian int32).
        var index = [Int32](repeating: 0, count: CallList.indexSize)
        data.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: Int32.self)
            for i in 0..<CallList.indexSize { index[i] = p[i] }
        }

        // Validate header markers.
        guard Int(index[0]) == indexBytes,
              Int(index[CallList.indexSize - 1]) == data.count else {
            return
        }

        // The callsign region is null-terminated ASCII strings.
        let region = data.subdata(in: indexBytes..<data.count)
        let parsed = region.split(separator: 0).compactMap { String(bytes: $0, encoding: .ascii) }

        // Sort and remove duplicates (the original sorts then drops adjacent dupes).
        var sorted = parsed.sorted()
        sorted.sort()
        var unique: [String] = []
        unique.reserveCapacity(sorted.count)
        var prev = ""
        for c in sorted {
            if c != prev { unique.append(c); prev = c }
        }
        calls = unique
    }

    /// Pick a random callsign. In HST mode, remove it from the pool.
    public func pick() -> String {
        if calls.isEmpty { return "P29SX" }
        let idx = Int(rnd() * Float(calls.count)) % calls.count
        let result = calls[idx]
        if Settings.shared.runMode == .hst {
            calls.remove(at: idx)
        }
        return result
    }
}

/// Global free function mirroring the original `PickCall`.
public func PickCall() -> String {
    return CallList.shared.pick()
}

/// Global free function mirroring the original `LoadCallList`.
public func LoadCallList() {
    CallList.shared.load()
}
