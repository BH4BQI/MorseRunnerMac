//
//  UpperCaseFormatter.swift
//  Formatters for the input fields:
//   - UpperCaseFormatter : callsign field — upper-cases letters, rejects any
//     character not valid in a callsign (A-Z 0-9 / ?). Mirrors the original's
//     Edit1KeyPress filtering and ensures input is always uppercase.
//   - DigitsOnlyFormatter : RST / NR fields — digits only, with an optional
//     max length.
//

import AppKit

final class UpperCaseFormatter: Formatter {
    private static let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/?")

    override func isPartialStringValid(_ partialStringPtr: AutoreleasingUnsafeMutablePointer<NSString>,
                                       proposedSelectedRange proposedSelRangePtr: NSRangePointer?,
                                       originalString origString: String,
                                       originalSelectedRange origSelRange: NSRange,
                                       errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        // Filter to allowed chars, then upper-case.
        let raw = partialStringPtr.pointee as String
        let scalars = raw.unicodeScalars.filter { UpperCaseFormatter.allowed.contains($0) }
        let cleaned = String(String.UnicodeScalarView(scalars)).uppercased()
        if cleaned != raw {
            partialStringPtr.pointee = cleaned as NSString
            return false
        }
        if cleaned.uppercased() != raw {
            partialStringPtr.pointee = cleaned as NSString
            return false
        }
        return true
    }

    override func string(for obj: Any?) -> String? {
        guard let s = obj as? String else { return nil }
        return s.uppercased()
    }

    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
                                 for string: String,
                                 errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        obj?.pointee = string.uppercased() as AnyObject
        return true
    }

    required init?(coder: NSCoder) { super.init(coder: coder) }
    override init() { super.init() }
}

final class DigitsOnlyFormatter: Formatter {
    private static let allowed = CharacterSet(charactersIn: "0123456789")
    private var maxLength: Int

    init(maxLength: Int = .max) {
        self.maxLength = maxLength
        super.init()
    }

    required init?(coder: NSCoder) {
        self.maxLength = .max
        super.init(coder: coder)
    }

    override func isPartialStringValid(_ partialStringPtr: AutoreleasingUnsafeMutablePointer<NSString>,
                                       proposedSelectedRange proposedSelRangePtr: NSRangePointer?,
                                       originalString origString: String,
                                       originalSelectedRange origSelRange: NSRange,
                                       errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        let raw = partialStringPtr.pointee as String
        let scalars = raw.unicodeScalars.filter { DigitsOnlyFormatter.allowed.contains($0) }
        var cleaned = String(String.UnicodeScalarView(scalars))
        if cleaned.count > maxLength {
            cleaned = String(cleaned.prefix(maxLength))
        }
        if cleaned != raw {
            partialStringPtr.pointee = cleaned as NSString
            return false
        }
        return true
    }

    override func string(for obj: Any?) -> String? { obj as? String }

    override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
                                 for string: String,
                                 errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        obj?.pointee = string as AnyObject
        return true
    }
}
