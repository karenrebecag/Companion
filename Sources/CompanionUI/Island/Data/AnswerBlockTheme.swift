import SwiftUI

// Wave 16m-1: the rich answer popup's own ink and measures, from the ovx-*
// classes measured in docs/research/incredible-isla-componentes.md §1. The
// ovx surface is NOT the ci ink of 16l (95/64/42): the popup reads at
// 94/72/46 over rgb(14,14,16), and the two scales must not blur.

package enum AnswerInk {
    package static let text = 0.94
    package static let secondary = 0.72
    package static let muted = 0.46
    package static let line = 0.07
    package static let lineStrong = 0.14
    package static let fill = 0.05
    package static let fillHover = 0.09
    package static let fillStrong = 0.13
    /// The popup's own accent, not the island's 78AAFF.
    package static let accent = Swatch("4A9CFF")
    /// rgb(14,14,16): between the island (n800) and the code well.
    package static let surface = Color(red: 14 / 255, green: 14 / 255, blue: 16 / 255)
    /// rgb(6,6,8): the code block sits deeper than its popup.
    package static let codeWell = Color(red: 6 / 255, green: 6 / 255, blue: 8 / 255)

    package static func white(_ alpha: Double) -> Color { .white.opacity(alpha) }
}

package enum AnswerBlockMetrics {
    package static let surfaceRadius: CGFloat = 20
    package static let surfaceBorder = 0.12
    /// Every interior block (table frame, callout, code, quote) shares it.
    package static let innerRadius: CGFloat = 12

    /// The × that closes the popup.
    package static let closeSide: CGFloat = 22
    /// 66 characters of Geist at 14 land near this; the popup is wider.
    package static let bodyMaxWidth: CGFloat = 490
    /// The glyph column of a step/tool row.
    package static let glyphWidth: CGFloat = 14

    package static let titleSize: CGFloat = AnswerType.title
    package static let sectionSize: CGFloat = AnswerType.section
    package static let subheadingSize: CGFloat = AnswerType.subheading
    package static let captionSize: CGFloat = AnswerType.caption
    package static let bodySize: CGFloat = AnswerType.body
    /// One leading for every block: two densities in one reply read as two voices.
    package static let bodyLeading: CGFloat = AnswerType.leading
    package static let bodyMeasure: CGFloat = 66
    package static let listLeading: CGFloat = AnswerType.leading
    package static let tableSize: CGFloat = 12.5
    package static let tableLeading: CGFloat = 1.45

    package static let calloutPaddingY: CGFloat = AnswerType.calloutPadY
    package static let calloutPaddingX: CGFloat = AnswerType.calloutPadX
    package static let calloutGap: CGFloat = Space.x3
    package static let calloutTone = 0.11
    package static let calloutBorder = 0.26

    /// The code bar carries the language, copy and fold.
    package static let codeBar: CGFloat = 26
    package static let inlineCodeSize: CGFloat = 12
    package static let inlineCodePaddingY: CGFloat = 1.5
    package static let inlineCodePaddingX: CGFloat = 6
    package static let inlineCodeRadius: CGFloat = 6

    package static let chipSize: CGFloat = AnswerType.caption
    package static let chipPaddingLeading: CGFloat = 6
    package static let chipPaddingTrailing: CGFloat = 7
    package static let chipPaddingY: CGFloat = 1
    package static let chipRadius: CGFloat = 6

    package static let quoteSize: CGFloat = AnswerType.body
    package static let quoteLeading: CGFloat = AnswerType.leading
    package static let quotePaddingY: CGFloat = AnswerType.quotePadY
    package static let quotePaddingX: CGFloat = AnswerType.quotePadX

    /// SwiftUI spacing from a CSS line height: the extra space per line.
    package static func lineSpacing(size: CGFloat, leading: CGFloat) -> CGFloat {
        (size * (leading - 1)).rounded()
    }
}
