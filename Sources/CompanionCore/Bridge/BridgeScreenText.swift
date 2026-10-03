import Foundation

/// Audit H6. A bridge result is whatever is on screen, so a page or a message
/// can carry text written for the agent. Scalars that render as nothing or
/// reorder text are dropped before the result leaves Companion, so a person
/// looking at the same screen sees what the agent reads. The set matches the
/// shim's `stripInvisible`; the shim strips again because it cannot trust an
/// older Companion.
package enum BridgeScreenText {
    /// Tag characters, variation selectors other than the emoji ones (FE0E,
    /// FE0F), bidi embeddings, overrides and isolates, zero-width and word
    /// joiners, invisible operators, blank fillers (Hangul, Mongolian, Khmer,
    /// braille), the soft hyphen, interlinear annotations, the BOM, and
    /// controls other than newline and tab.
    /// HACK: dropping ZWJ and ZWNJ splits emoji sequences and changes how
    /// Persian and Indic text joins. Keep them between letters when an agent
    /// has to quote such text verbatim.
    private static let invisible: [ClosedRange<UInt32>] = [
        0xE0000...0xE007F, 0xE0100...0xE01EF, 0xFE00...0xFE0D, 0x202A...0x202E,
        0x2060...0x206F, 0x200B...0x200F, 0xFEFF...0xFEFF, 0x00AD...0x00AD,
        0x034F...0x034F, 0x061C...0x061C, 0x115F...0x1160, 0x17B4...0x17B5,
        0x180B...0x180F, 0x2800...0x2800, 0x3164...0x3164, 0xFFA0...0xFFA0,
        0xFFF9...0xFFFC, 0x0000...0x0008, 0x000B...0x001F, 0x007F...0x009F,
    ]

    package static func strip(_ raw: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            // Line and paragraph separators still break the line the person sees.
            if scalar.value == 0x2028 || scalar.value == 0x2029 {
                scalars.append("\n")
            } else if !invisible.contains(where: { $0.contains(scalar.value) }) {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }
}
