import SwiftUI

// Wave 16m-3: the attachment pieces as Incredible's overlay CSS measures them
// (docs/research/incredible-isla-componentes.md §3, the `ci-att-*` classes).
// Pinned in IslandAttach16m3Tests: a value changes here and in the research
// together, or not at all.

public enum IslandAttachMetrics {
    /// As long as a notice card's countdown (spec 16i §9).
    public static let noteSeconds: Double = 6

    /// `ci-att-card`: 84 × 102, radius 10, a 6 % tile under a 22 % white rim,
    /// padding 8; a picture bleeds to the edge instead.
    public static let cardWidth: CGFloat = 84
    public static let cardHeight: CGFloat = 102
    public static let cardRadius: CGFloat = 10
    public static let cardPadding: CGFloat = 8
    public static let cardTile = 0.06
    public static let cardBorder = 0.22
    /// The failed card's wash: Incredible's error `#ff7a64` at 8 %.
    public static let errorTint = Swatch("FF7A64")
    public static let errorAlpha = 0.08

    /// The name: 12 / 500 on a 16 line — Geist's own line at 12, so the
    /// view adds no spacing to reach it.
    public static let nameSize: CGFloat = 12
    public static let nameLineHeight: CGFloat = 16
    /// The extension badge: 10 / 600, +0.04em, 3 × 6 on white 13 %, radius 5.
    public static let extSize: CGFloat = 10
    public static let extTracking: CGFloat = 0.04
    public static let extPaddingY: CGFloat = 3
    public static let extPaddingX: CGFloat = 6
    public static let extRadius: CGFloat = 5
    public static let extFill = 0.13

    /// The remove circle's disc and rim: `#141519` at 90 % under white 30 %.
    /// Its 24 side lives in `IconButtonSize.attachmentRemove`.
    public static let removeFill = Swatch("141519")
    public static let removeFillAlpha = 0.9
    public static let removeBorder = 0.3

    /// The chip row: gap 8, padding 12 / 12 / 0 / 0, fading at its end.
    public static let rowGap: CGFloat = 8
    public static let rowPaddingTop: CGFloat = 12
    public static let rowPaddingTrailing: CGFloat = 12
    /// How far the end fade reaches. Not measured (the CSS fades by mask
    /// without a length we could read): one gap plus its padding.
    public static let fadeLength: CGFloat = 20

    /// The capture stack: 96 × 64 with an 18-high count badge, radius 6,
    /// 10 / 600.
    public static let stackWidth: CGFloat = 96
    public static let stackHeight: CGFloat = 64
    public static let badgeHeight: CGFloat = 18
    public static let badgeRadius: CGFloat = 6
    public static let badgeSize: CGFloat = 10
    /// The cards peeking out under the top capture. Not measured: enough to
    /// read as a pile at 96 wide.
    public static let stackOffset: CGFloat = 3
    public static let stackLayers = 2

    /// The strip the stack opens into: gap 6, padding 10 / 10 / 0.
    public static let stripGap: CGFloat = 6
    public static let stripPaddingTop: CGFloat = 10
    public static let stripPaddingX: CGFloat = 10

    /// Downsample target for a card's picture: its longer side at 2x.
    nonisolated public static let thumbnailPixels: CGFloat = 204
    /// Above this declared canvas no picture is decoded: 100 MP covers any
    /// camera or screenshot and stops a crafted header from asking ImageIO
    /// for gigabytes (security review 16m-3, LOW-1).
    nonisolated public static let maxSourcePixels: CGFloat = 100_000_000
    /// The icon standing in for a picture that could not be read.
    public static let fallbackIcon: CGFloat = 22
    /// Pictures kept decoded; more than an island ever shows at once.
    nonisolated public static let thumbnailCacheLimit = 64
}

public enum IslandDropMetrics {
    /// `ci-drop`: 36 high, padding 0 × 16, a 1.5 dashed white 28 % rim,
    /// radius 12, 12 / 500.
    public static let height: CGFloat = 36
    public static let paddingX: CGFloat = 16
    public static let dashWidth: CGFloat = 1.5
    public static let restStroke = 0.28
    public static let radius: CGFloat = 12
    public static let textSize: CGFloat = 12
    /// Dash and gap of the rim. Not in the CSS (the browser draws `dashed`
    /// its own way); these read like it at 1.5.
    public static let dash: [CGFloat] = [6, 4]
    /// NotchNook's lit zone, measured in the 18:11 recording.
    public static let litFill = Color(red: 0.06, green: 0.16, blue: 0.34)
    public static let litStroke = Color(red: 0.25, green: 0.55, blue: 1.0)
}
