import SwiftUI

// Wave 16m-1: the rich answer popup's own ink and measures, from the ovx-*
// classes measured in docs/research/incredible-isla-componentes.md §1. The
// ovx surface is NOT the ci ink of 16l (95/64/42): the popup reads at
// 94/72/46 over rgb(14,14,16), and the two scales must not blur.

public enum AnswerInk {
    public static let text = 0.94
    public static let secondary = 0.72
    public static let muted = 0.46
    public static let line = 0.07
    public static let lineStrong = 0.14
    public static let fill = 0.05
    public static let fillHover = 0.09
    public static let fillStrong = 0.13
    /// The popup's own accent, not the island's 78AAFF.
    public static let accent = Swatch("4A9CFF")
    /// rgb(14,14,16): between the island (n800) and the code well.
    public static let surface = Color(red: 14 / 255, green: 14 / 255, blue: 16 / 255)
    /// rgb(6,6,8): the code block sits deeper than its popup.
    public static let codeWell = Color(red: 6 / 255, green: 6 / 255, blue: 8 / 255)

    public static func white(_ alpha: Double) -> Color { .white.opacity(alpha) }
}

public enum AnswerBlockMetrics {
    public static let surfaceRadius: CGFloat = 20
    public static let surfaceBorder = 0.12
    /// Every interior block (table frame, callout, code, quote) shares it.
    public static let innerRadius: CGFloat = 12

    /// The × that closes the popup.
    public static let closeSide: CGFloat = 22
    /// 66 characters of Geist at 13.5 land near this; the popup is wider.
    public static let bodyMaxWidth: CGFloat = 490
    /// The glyph column of a step/tool row.
    public static let glyphWidth: CGFloat = 14

    public static let titleSize: CGFloat = 21
    public static let sectionSize: CGFloat = 15.5
    public static let eyebrowSize: CGFloat = 11.5
    public static let bodySize: CGFloat = 13.5
    /// 1.62 line height and a 66-character measure keep long answers readable.
    public static let bodyLeading: CGFloat = 1.62
    public static let bodyMeasure: CGFloat = 66
    public static let listLeading: CGFloat = 1.6
    public static let tableSize: CGFloat = 12.5
    public static let tableLeading: CGFloat = 1.45

    public static let calloutPaddingY: CGFloat = 11
    public static let calloutPaddingX: CGFloat = 14
    public static let calloutGap: CGFloat = 11
    public static let calloutTone = 0.11
    public static let calloutBorder = 0.26

    /// The code bar carries the language, copy and fold.
    public static let codeBar: CGFloat = 26
    public static let inlineCodeSize: CGFloat = 12
    public static let inlineCodePaddingY: CGFloat = 1.5
    public static let inlineCodePaddingX: CGFloat = 6
    public static let inlineCodeRadius: CGFloat = 6

    public static let chipSize: CGFloat = 11.5
    public static let chipPaddingLeading: CGFloat = 6
    public static let chipPaddingTrailing: CGFloat = 7
    public static let chipPaddingY: CGFloat = 1
    public static let chipRadius: CGFloat = 6

    public static let quoteSize: CGFloat = 14
    public static let quoteLeading: CGFloat = 1.55
    public static let quotePaddingY: CGFloat = 10
    public static let quotePaddingX: CGFloat = 16

    /// SwiftUI spacing from a CSS line height: the extra space per line.
    public static func lineSpacing(size: CGFloat, leading: CGFloat) -> CGFloat {
        (size * (leading - 1)).rounded()
    }
}
