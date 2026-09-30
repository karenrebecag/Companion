import Foundation

/// Text the model wrote that will be drawn or exported. Invisible format
/// characters (bidi overrides, zero-width spaces, Unicode tags) let a label
/// read differently than it is or hide a spreadsheet trigger; controls
/// corrupt a sheet or a PDF; unbounded strings break any layout.
package enum TextSanitizer {
    /// Labels, titles, units and series names.
    package static let maxLabel = 120
    /// A table cell may be a sentence.
    package static let maxCell = 500
    /// Combining marks stack without limit ("zalgo"); this many scalars per
    /// visible character is more than any real script needs.
    static let scalarsPerCharacter = 4

    /// Newline and tab survive: they are text, and CSV quoting handles them.
    /// ZWJ and ZWNJ survive too: emoji families and several scripts need them.
    package static func display(_ text: String, maxLength: Int) -> String {
        let limit = max(maxLength, 0)
        var kept = String.UnicodeScalarView()
        var count = 0
        for scalar in text.unicodeScalars where keeps(scalar) {
            kept.append(scalar)
            count += 1
            if count >= limit * scalarsPerCharacter { break }
        }
        return String(String(kept).prefix(limit))
    }

    private static func keeps(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        if value == 0x0A || value == 0x09 { return true }
        if value < 0x20 || (0x7F ... 0x9F).contains(value) { return false }
        if (0xE0000 ... 0xE007F).contains(value) || (0xE0100 ... 0xE01EF).contains(value) { return false }
        switch scalar.properties.generalCategory {
        case .format: return value == 0x200C || value == 0x200D
        case .lineSeparator, .paragraphSeparator: return false
        default: return true
        }
    }
}
