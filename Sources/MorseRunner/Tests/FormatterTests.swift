//
//  Tests/FormatterTests.swift
//  Tests for the input-field formatters — especially UpperCaseFormatter, which
//  ensures callsign input is always uppercase (a user-requested behaviour).
//

import Foundation

enum FormatterTests {
    static let suite = TestRunner.register("Input formatters", [

        TestCase("UpperCaseFormatter upper-cases letters as typed") {
            let f = UpperCaseFormatter()
            for input in ["b", "bh", "bh4", "bh4bqI", "w1aw"] {
                let result = filterSample(formatter: f, input: input)
                if result != input.uppercased() {
                    return .fail("\"\(input)\" → \"\(result)\" (expected all-uppercase)")
                }
            }
            return .pass
        },

        TestCase("UpperCaseFormatter rejects non-callsign characters") {
            let f = UpperCaseFormatter()
            let cases: [(String, String)] = [
                ("w1 aw", "W1AW"),       // space removed
                ("w1@aw", "W1AW"),       // @ removed
                ("cañon", "CAON"),       // ñ (non-ASCII) stripped; rest kept
                ("vk/?", "VK/?"),        // / and ? kept
            ]
            for (input, expected) in cases {
                let result = filterSample(formatter: f, input: input)
                if result != expected {
                    return .fail("\"\(input)\" → \"\(result)\" (expected \"\(expected)\")")
                }
            }
            return .pass
        },

        TestCase("DigitsOnlyFormatter keeps only digits, respects max length") {
            let f = DigitsOnlyFormatter(maxLength: 3)
            let cases: [(String, String)] = [
                ("599", "599"),          // passes through
                ("59a9", "599"),         // letter removed
                ("12345", "123"),        // truncated to 3
                ("", ""),                // empty stays empty
            ]
            for (input, expected) in cases {
                let result = filterSample(formatter: f, input: input)
                if result != expected {
                    return .fail("\"\(input)\" → \"\(result)\" (expected \"\(expected)\")")
                }
            }
            return .pass
        },
    ])
}

/// Run a formatter's partial-string validation on `input` and return the result.
/// The autoreleasing-pointer plumbing is fiddly, so isolate it here.
private func filterSample(formatter: Formatter, input: String) -> String {
    var nsObj: NSString = input as NSString
    var selRange = NSRange(location: input.count, length: 0)
    var err: NSString? = nil
    withUnsafeMutablePointer(to: &nsObj) { objPtr in
        withUnsafeMutablePointer(to: &selRange) { selPtr in
            withUnsafeMutablePointer(to: &err) { errPtr in
                let aObjPtr = AutoreleasingUnsafeMutablePointer<NSString>(objPtr)
                let aSelPtr = NSRangePointer(selPtr)
                let aErrPtr = AutoreleasingUnsafeMutablePointer<NSString?>(errPtr)
                _ = formatter.isPartialStringValid(
                    aObjPtr,
                    proposedSelectedRange: aSelPtr,
                    originalString: "",
                    originalSelectedRange: NSRange(),
                    errorDescription: aErrPtr)
            }
        }
    }
    return nsObj as String
}

