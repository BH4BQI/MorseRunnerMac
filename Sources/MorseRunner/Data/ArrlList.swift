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
        // Prefer the user-replaceable copy in ~/Library/Application Support/MorseRunner/,
        // fall back to the bundled read-only copy.
        let dir = FileManager.default.applicationSupportDirectory
        let userURL = dir.appendingPathComponent("ARRL.LIST")
        let url: URL
        if FileManager.default.fileExists(atPath: userURL.path) {
            url = userURL
        } else if let bundled = Bundle.main.url(forResource: "ARRL", withExtension: "LIST") {
            url = bundled
        } else {
            return
        }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
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

    /// Number of loaded records (for display after an update).
    public var count: Int { records.count }

    /// Force a reload from disk (used after downloading a new ARRL.LIST).
    public func reload() {
        loaded = false
        records.removeAll()
        loadIfNeeded()
    }

    /// Convert the ARRL "Current_Deleted.txt" text format into the semicolon-
    /// delimited ARRL.LIST format used by this app. Returns the generated text,
    /// or nil if parsing failed.
    ///
    /// The source text has fixed-width columns:
    /// ```
    ///     Prefix              Entity                    Continent ITU  CQ  Code
    ///     3B6,7               Agalega & St. Brandon Is. AF    53   39  004
    /// ```
    /// We parse by anchoring on the trailing 4 fields (Continent, ITU, CQ,
    /// EntityCode) and splitting the remainder into Prefix + Entity.
    /// The regex column is auto-generated from the human-readable prefix.
    public static func generateFromTXT(_ text: String) -> String? {
        var output: [String] = []
        // Header matching the original ARRL.LIST format.
        let dateStr = ISO8601DateFormatter().string(from: Date()).prefix(7)
        output.append("ARRL DXCC List (converted \(dateStr))")
        output.append("https://www.arrl.org/files/file/DXCC/Current_Deleted.txt")
        output.append("")

        // Regex to match the trailing 4 columns of a data row:
        //   <2-letter continent> <ITU zone digits/ranges> <CQ zone digits/ranges> <3-digit entity code>
        // anchored at end of line. Everything before is "Prefix ... Entity".
        let rowPattern = #"^(.+?)\s{2,}([A-Z]{2})\s+(\d[\d,]*|\d+-\d+)\s+(\d[\d,]*|\d+-\d+)\s+(\d{3})\s*$"#

        guard let rowRE = try? NSRegularExpression(pattern: rowPattern) else { return nil }

        var count = 0
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            // Skip headers, notes, separator lines, section titles.
            if line.isEmpty { continue }
            if line.hasPrefix("ARRL") || line.hasPrefix("CURRENT") || line.hasPrefix("DELETED") { continue }
            if line.hasPrefix("Notes:") || line.hasPrefix("#") { continue }
            if line.contains("Total:") || line.contains("Edition") { continue }
            if line.contains("Publication") || line.contains("paper copy") { continue }
            if line.contains("Effective") || line.contains("Card Checkers") { continue }
            if line.contains("Credit for") || line.contains("entry level") { continue }
            if line.contains("http:") || line.contains("https:") { continue }
            if line.hasPrefix("Prefix") || line.contains("Continent") { continue }
            if line.contains("___") { continue }

            let range = NSRange(line.startIndex..., in: line)
            guard let m = rowRE.firstMatch(in: line, range: range) else { continue }

            // Extract the 5 capture groups.
            func cap(_ n: Int) -> String {
                guard let r = Range(m.range(at: n), in: line) else { return "" }
                return String(line[r])
            }
            let prefixAndEntity = cap(1)    // "3B6,7  Agalega & St. Brandon Is."
            let continent = cap(2)          // "AF"
            let itu = cap(3)                // "53"
            let cq = cap(4)                 // "39"
            let code = cap(5)               // "004"

            // Split prefixAndEntity into prefix + entity on 2+ spaces.
            let parts = prefixAndEntity.split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)
            // Find the split point: the prefix is the first token(s) before a
            // gap of 2+ spaces. Use regex to find the first run of 2+ spaces.
            let gapRE = try? NSRegularExpression(pattern: #"\s{2,}"#)
            let gapRange = NSRange(prefixAndEntity.startIndex..., in: prefixAndEntity)
            guard let gap = gapRE?.firstMatch(in: prefixAndEntity, range: gapRange),
                  let gapR = Range(gap.range, in: prefixAndEntity) else { continue }
            let prefixCol = String(prefixAndEntity[..<gapR.lowerBound]).trimmingCharacters(in: .whitespaces)
            let entityCol = String(prefixAndEntity[gapR.upperBound...]).trimmingCharacters(in: .whitespaces)

            if prefixCol.isEmpty || entityCol.isEmpty { continue }

            // Generate the regex column from the human-readable prefix.
            let regex = prefixToRegex(prefixCol)

            output.append("\(prefixCol);\(regex);\(entityCol);\(continent);\(itu);\(cq);\(code)")
            count += 1
        }

        guard count > 0 else { return nil }
        return output.joined(separator: "\n") + "\n"
    }

    /// Convert a human-readable prefix string into a regex pattern for matching.
    ///
    /// Rules (matching BG4FQD's original hand-written conversions):
    /// - Remove markers: `*`, `#`, `(n)` footnotes, trailing spaces.
    /// - `AA-AK` → `A[A-K]` (letter range → character class)
    /// - `A0-A9` → `A[0-9]` (digit range → character class)
    /// - `3B6,7` → `3B6|3B7` (comma-separated suffix shorthand: common base
    ///   prefix detected when a part is shorter and shares a leading prefix)
    /// - `K,W,N` → `K|W|N` (distinct prefixes → alternation)
    /// - `4U_ITU` → `4U_ITU` (simple prefix unchanged)
    static func prefixToRegex(_ prefix: String) -> String {
        var s = prefix
        // Remove footnote markers: (n), *, #
        while let parenStart = s.firstIndex(of: "(") {
            if let parenEnd = s[s.index(after: parenStart)...].firstIndex(of: ")") {
                s.removeSubrange(parenStart...parenEnd)
            } else { break }
        }
        s = s.replacingOccurrences(of: "*", with: "")
        s = s.replacingOccurrences(of: "#", with: "")
        s = s.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return s }

        // If no comma, just expand a possible range (e.g. AA-AK).
        if !s.contains(",") {
            return expandRange(s)
        }

        // Split on comma and process each part.
        var parts = s.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }

        // Handle ARRL shorthand: "3B6,7" means "3B6 or 3B7". When a part is a
        // single trailing character (digit or letter) and the previous part is
        // longer, the short part inherits the base of the previous part.
        // e.g. ["3B6","7"] → ["3B6","3B7"]; ["5H","5I"] stays as-is.
        var fixed: [String] = []
        for (_, part) in parts.enumerated() {
            if part.count == 1, let prev = fixed.last, prev.count > 1 {
                let base = String(prev.dropLast())
                fixed.append(base + part)
            } else {
                fixed.append(part)
            }
        }
        parts = fixed

        var expanded: [String] = []
        for part in parts {
            expanded.append(expandRange(part))
        }

        // If any part contains a character class or there are multiple parts,
        // wrap in a group for proper alternation.
        if expanded.count > 1 {
            return "(" + expanded.joined(separator: "|") + ")"
        }
        return expanded.joined(separator: "|")
    }

    /// Expand a single prefix token that may contain a range like `AA-AK`.
    /// The common prefix before the `-` is the base; the single chars
    /// straddling the `-` define the character class range.
    ///   `AA-AK` → base `A`, range `A-K` → `A[A-K]`
    ///   `3B6-7` → base `3B`, range `6-7` → `3B[6-7]`
    ///   `KH2-KH6` → base `KH`, range `2-6` → `KH[2-6]`
    private static func expandRange(_ token: String) -> String {
        guard let dash = token.firstIndex(of: "-") else { return token }
        let beforeDash = String(token[..<dash])
        let afterDash = String(token[token.index(after: dash)...])
        // The varying character is the last char of beforeDash and the last
        // char of afterDash (handles multi-char suffixes like AK).
        guard let rangeStart = beforeDash.last,
              let rangeEnd = afterDash.last else { return token }
        let base = String(beforeDash.dropLast())
        // Sanity check: both range chars should be the same type (both letters
        // or both digits) to avoid false positives on prefixes containing "-".
        let startIsLetter = rangeStart.isLetter
        let endIsLetter = rangeEnd.isLetter
        guard startIsLetter == endIsLetter else { return token }
        return "\(base)[\(rangeStart)-\(rangeEnd)]"
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
