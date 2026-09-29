import Foundation

/// Text from outside (a window title, a file name, a tool's target) that is
/// about to sit inside a prompt or a card.
public enum TextHygiene {
    /// One line with nothing invisible: format scalars (tag characters
    /// U+E0000-E007F, bidi overrides, zero-width spaces; not the joiners) are removed, and line
    /// breaks and control characters become a space.
    /// ZWJ and ZWNJ carry meaning (family emoji, Persian and Indic scripts).
    private static let joiners: Set<Unicode.Scalar> = ["\u{200D}", "\u{200C}"]

    public static func oneLine(_ text: String) -> String {
        let breaks = CharacterSet.newlines.union(.controlCharacters)
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            // Checked by category, not by CharacterSet: `controlCharacters`
            // misses the tag block in plane 14, which is exactly where
            // invisible instructions hide.
            if joiners.contains(scalar) {
                out.append(scalar)
                continue
            }
            if scalar.properties.generalCategory == .format { continue }
            out.append(breaks.contains(scalar) ? " " : scalar)
        }
        return String(out)
    }
}
