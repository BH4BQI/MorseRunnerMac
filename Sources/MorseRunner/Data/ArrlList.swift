//
//  ArrlList.swift
//  Port of ARRL.pas — DXCC country lookup from ARRL.LIST.
//
//  Each line of ARRL.LIST is a ';'-delimited record; column 2 is a regex prefix
//  pattern. Given a callsign we extract its callsign + prefix and find the
//  matching DXCC entity/continent/ITU/CQ zone for the info bar.
//

import Foundation

public final class ArrlRecord {
    public let prefixReg: String
    public let entity: String
    public let continent: String
    public let itu: String
    public let cq: String

    public init(prefixReg: String, entity: String, continent: String, itu: String, cq: String) {
        self.prefixReg = prefixReg
        self.entity = entity
        self.continent = continent
        self.itu = itu
        self.cq = cq
    }

    public var displayString: String {
        return "\(entity)/\(continent);  ITU Zone:\(itu);  CQ Zone:\(cq)"
    }
}

public final class ArrlList {
    public static let shared = ArrlList()

    private var records: [ArrlRecord] = []
    private var loaded = false

    private init() {}

    public func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let url = Bundle.main.url(forResource: "ARRL", withExtension: "LIST"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return
        }
        // skip the two-line header (title + url)
        var recs: [ArrlRecord] = []
        recs.reserveCapacity(400)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 7 else { continue }
            // fields[0] is the full prefix column; fields[1] is the regex.
            recs.append(ArrlRecord(
                prefixReg: fields[1],
                entity: fields[2],
                continent: fields[3],
                itu: fields[4],
                cq: fields[5]))
        }
        records = recs
    }

    public func search(_ callsign: String) -> String {
        loadIfNeeded()
        let call = extractCallsign(callsign)
        let prefix = extractPrefix(call)
        if prefix.isEmpty { return "" }
        // iterate in reverse (matches original ordering)
        for rec in records.reversed() {
            guard let re = try? NSRegularExpression(pattern: "^(\(rec.prefixReg))") else { continue }
            let range = NSRange(prefix.startIndex..., in: prefix)
            if re.firstMatch(in: prefix, range: range) != nil {
                return "\(call)  \(rec.displayString)"
            }
        }
        return ""
    }
}

// MARK: - callsign extraction (Log.pas: ExtractCallsign / ExtractPrefix)

/// Extract a callsign substring via the WPX regex.
public func extractCallsign(_ call: String) -> String {
    let pattern = "(([0-9][A-Z])|([A-Z]{1,2}))[0-9][A-Z0-9]*[A-Z]"
    guard let re = try? NSRegularExpression(pattern: pattern) else { return "" }
    let range = NSRange(call.startIndex..., in: call)
    guard let m = re.firstMatch(in: call, range: range) else { return "" }
    // Original: only accept if preceded by '/' at position MatchedOffset-1.
    if let matchedRange = Range(m.range, in: call) {
        let startIdx = matchedRange.lowerBound
        if startIdx > call.startIndex {
            let prev = call.index(before: startIdx)
            if call[prev] != "/" { return "" }
        }
        return String(call[matchedRange])
    }
    return ""
}

/// Extract the WPX prefix.
public func extractPrefix(_ call: String) -> String {
    let pattern = "(([0-9][A-Z])|([A-Z]{1,2}))[0-9]"
    guard let re = try? NSRegularExpression(pattern: pattern) else { return "-" }
    let range = NSRange(call.startIndex..., in: call)
    if let m = re.firstMatch(in: call, range: range),
       let r = Range(m.range, in: call) {
        return String(call[r])
    }
    return "-"
}
