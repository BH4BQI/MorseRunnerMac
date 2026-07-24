//
//  Tests/CWRoundTripTests.swift
//  CW readability round-trip: encode text → Morse → decode → text.
//  This directly guards "the CW is readable" — the user's original complaint.
//

import Foundation

enum CWRoundTripTests {
    static let suite = TestRunner.register("CW round-trip readability", [
        TestCase("single characters round-trip") {
            let k = MorseKey()
            // All standard characters should encode and decode back to themselves.
            let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
            for ch in chars {
                let code = k.encode(String(ch))
                // code looks like ".- ~" (trailing space + ~). Trim and decode.
                let cleaned = code.replacingOccurrences(of: "~", with: "")
                                   .trimmingCharacters(in: .whitespaces)
                guard let decoded = decodeMorse(cleaned) else {
                    return .fail("'\(ch)' → \"\(code)\" → decode failed")
                }
                if decoded != String(ch) {
                    return .fail("'\(ch)' round-tripped to '\(decoded)'")
                }
            }
            return .pass
        },

        TestCase("callsigns round-trip (the contest's core data)") {
            let k = MorseKey()
            let callsigns = ["BH4BQI", "W1AW", "VE3NEA", "JA1ABC", "BY8AA"]
            for call in callsigns {
                let code = k.encode(call).replacingOccurrences(of: "~", with: "")
                // Each letter is separated by a space in the encoded form.
                let letters = code.split(separator: " ").map(String.init)
                var decoded = ""
                for letter in letters {
                    guard let ch = decodeLetter(letter) else {
                        return .fail("'\(call)': cannot decode letter \"\(letter)\"")
                    }
                    decoded += ch
                }
                if decoded != call {
                    return .fail("'\(call)' round-tripped to '\(decoded)'")
                }
            }
            return .pass
        },

        TestCase("CQ message round-trips to readable text") {
            // The CQ message body is "CQ <my> TEST". With my=BH4BQI the encoded
            // text must decode back to "CQ BH4BQI TEST".
            let k = MorseKey()
            let body = "CQ BH4BQI TEST"
            let code = k.encode(body).replacingOccurrences(of: "~", with: "")
            // Words separated by 1 space (between letters) — but letters within a
            // word are also single-space-separated, matching Encode's output.
            // MorseKey.Encode uses single spaces for BOTH letter and word gaps,
            // so a clean per-letter decode (ignoring word boundaries) is the
            // strongest check here.
            let letters = code.split(separator: " ").map(String.init)
            var decoded = ""
            for letter in letters {
                if let ch = decodeLetter(letter) { decoded += ch }
            }
            // decoded should at least contain C, Q, B, H, 4, B, Q, I, T, E, S, T
            return expectAll(
                expectTrue(decoded.contains("CQ"), "decoded contains CQ (got \"\(decoded)\")"),
                expectTrue(decoded.contains("TEST"), "decoded contains TEST (got \"\(decoded)\")"),
                expectTrue(decoded.contains("BH4BQI"), "decoded contains my-call (got \"\(decoded)\")")
            )
        },
    ])
}

/// Decode a full morse string (letters separated by single spaces) → text.
private func decodeMorse(_ morse: String) -> String? {
    var out = ""
    for token in morse.split(separator: " ") {
        guard let ch = decodeLetter(String(token)) else { return nil }
        out += ch
    }
    return out
}

private func decodeLetter(_ code: String) -> String? {
    let table: [String: String] = [
        ".-":"A","-...":"B","-.-.":"C","-..":"D",".":"E","..-.":"F","--.":"G",
        "....":"H","..":"I",".---":"J","-.-":"K",".-..":"L","--":"M","-.":"N",
        "---":"O",".--.":"P","--.-":"Q",".-.":"R","...":"S","-":"T","..-":"U",
        "...-":"V",".--":"W","-..-":"X","-.--":"Y","--..":"Z",
        "-----":"0",".----":"1","..---":"2","...--":"3","....-":"4",".....":"5",
        "-....":"6","--...":"7","---..":"8","----.":"9",
    ]
    return table[code]
}

private func expectAll(_ results: TestResult...) -> TestResult {
    for r in results { if case .fail(let m) = r { return .fail(m) } }
    return .pass
}
