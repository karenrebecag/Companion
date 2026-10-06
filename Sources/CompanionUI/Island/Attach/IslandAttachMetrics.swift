import SwiftUI

// Wave 16m-3: the attachment pieces as Incredible's overlay CSS measures them
// (docs/research/incredible-isla-componentes.md §3, the `ci-att-*` classes).
// Pinned in IslandAttach16m3Tests: a value changes here and in the research
// together, or not at all.

package enum IslandAttachMetrics {
    /// As long as a notice card's countdown (spec 16i §9).
    package static let noteSeconds: Double = 6

    /// `ci-att-card`: 84 × 102, radius 10, padding 8; a picture bleeds to the
    /// edge instead. Arc's file row inks it: surface under a border.
    package static let cardWidth: CGFloat = 84
    package static let cardHeight: CGFloat = 102
    package static let cardRadius: CGFloat = 10
    package static let cardPadding: CGFloat = 8
    package static let cardFill = ArcTone.surface
    package static let cardRim = ArcTone.border
    /// Arc's failed file: a 26 % red border over the danger badge's 10 % wash.
    package static var errorFill: Swatch { ArcTone.mix(ArcTone.danger, 0.1, over: ArcTone.surface) }
    package static var errorRim: Swatch { ArcTone.mix(ArcTone.danger, 0.26, over: ArcTone.border) }

    /// The name: 12 / 500 on a 16 line — Geist's own line at 12, so the
    /// view adds no spacing to reach it.
    package static let nameSize: CGFloat = 12
    package static let nameLineHeight: CGFloat = 16
    /// The extension badge: 10 / 500, +0.04em, 3 × 6, radius 5, Arc's neutral badge.
    package static let extSize: CGFloat = 10
    package static let extTracking: CGFloat = 0.04
    package static let extPaddingY: CGFloat = 3
    package static let extPaddingX: CGFloat = 6
    package static let extRadius: CGFloat = 5
    package static let extFill = ArcTone.surfaceMuted

    /// The remove circle's disc and rim: `#141519` at 90 % under white 30 %.
    /// Its 24 side lives in `IconButtonSize.attachmentRemove`.
    package static let removeFill = Swatch("141519")
    package static let removeFillAlpha = 0.9
    package static let removeBorder = 0.3
    /// Its ink at rest is white 85 %; under its own pointer the disc goes
    /// black 85 % and the ink pure white. local reference; Incredible .ci-att-card
    package static let removeInkAlpha = 0.85
    package static let removeHoverFill = Neutral.black
    package static let removeHoverFillAlpha = 0.85
    /// The disc's centre sits on the card's top-right corner: it overhangs
    /// the card by this much on both axes, into the row's own padding.
    package static let removeOffset: CGFloat = 12
    /// The disc's opacity fade, in `MotionCurve.ease`.
    package static let revealSeconds = 0.14

    /// The chip row: gap 8, padding 12 / 12 / 0 / 0, fading at its end.
    package static let rowGap: CGFloat = 8
    package static let rowPaddingTop: CGFloat = 12
    package static let rowPaddingTrailing: CGFloat = 12
    /// How far the end fade reaches. Not measured (the CSS fades by mask
    /// without a length we could read): one gap plus its padding.
    package static let fadeLength: CGFloat = 20

    /// The capture stack: 96 × 64 with an 18-high count badge, radius 6,
    /// 10 / 600.
    package static let stackWidth: CGFloat = 96
    package static let stackHeight: CGFloat = 64
    package static let badgeHeight: CGFloat = 18
    package static let badgeRadius: CGFloat = 6
    package static let badgeSize: CGFloat = 10
    /// The cards peeking out under the top capture. Not measured: enough to
    /// read as a pile at 96 wide.
    package static let stackOffset: CGFloat = 3
    package static let stackLayers = 2

    /// The strip the stack opens into: gap 6, padding 10 / 10 / 0.
    package static let stripGap: CGFloat = 6
    package static let stripPaddingTop: CGFloat = 10
    package static let stripPaddingX: CGFloat = 10

    /// Downsample target for a card's picture: its longer side at 2x.
    nonisolated package static let thumbnailPixels: CGFloat = 204
    /// Above this declared canvas no picture is decoded: 100 MP covers any
    /// camera or screenshot and stops a crafted header from asking ImageIO
    /// for gigabytes (security review 16m-3, LOW-1).
    nonisolated package static let maxSourcePixels: CGFloat = 100_000_000
    /// The icon standing in for a picture that could not be read.
    package static let fallbackIcon: CGFloat = 22
    /// Pictures kept decoded; more than an island ever shows at once.
    nonisolated package static let thumbnailCacheLimit = 64
}

package enum IslandDropMetrics {
    /// `ci-drop`: 36 high, padding 0 × 16, radius 12, 12 / 500, with Arc's
    /// file-dropzone rim: 1 dashed border-strong at rest.
    package static let height: CGFloat = 36
    package static let paddingX: CGFloat = 16
    package static let dashWidth: CGFloat = 1
    package static var restStroke: Swatch { IslandArc.borderStrong }
    package static let radius: CGFloat = 12
    package static let textSize: CGFloat = 12
    /// Arc's `stroke-dasharray: 3.5 3.5`.
    package static let dash: [CGFloat] = [3.5, 3.5]
    /// Arc's drag-over: a breath of accent, and the rim turns solid accent.
    package static var litFill: Swatch { ArcTone.mix(ArcTone.accent, 0.025, over: ArcTone.surface) }
    package static var litStroke: Swatch { ArcTone.mix(ArcTone.accent, 0.4, over: ArcTone.border) }
}
