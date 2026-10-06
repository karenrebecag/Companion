import CompanionCore
import SwiftUI

// Wave 16l-4: the island's own ink and the pieces Incredible draws inside
// it, measured in its overlay CSS (docs/research/incredible-componentes.md).

/// The island's signal tones are Arc's dark tones: one per meaning.
package enum IslandPalette {
    package static let accent = ArcTone.accent
    package static let error = ArcTone.danger
}

package enum IslandMetrics {
    package static let sendSide: CGFloat = 30
    package static let openRadius: CGFloat = Radius.panel
    /// The open island's edge: `--color-border-default` on the overlay.
    package static let rimAlpha = 0.12
}

package enum AnswerOptionMetrics {
    package static let paddingY: CGFloat = 11
    package static let paddingX: CGFloat = Space.x3
    package static let radius: CGFloat = 12
    package static let gap: CGFloat = 11
}

/// Arc's info badge (small): a pill, accent-subtle under a 24 % accent rim.
package enum ReferentChipMetrics {
    package static let paddingLeading: CGFloat = 8
    package static let paddingTrailing: CGFloat = 8
    package static let paddingY: CGFloat = 2
    package static let size: CGFloat = 12.5
    package static let maxWidth: CGFloat = 230
    package static let fill = 0.12
    package static let stroke = 0.24
}

package enum CaptureCardMetrics {
    package static let height: CGFloat = 64
    package static let radius: CGFloat = Radius.md
}

package enum CaptureKind: CaseIterable, Sendable {
    case text, screenshot, file, task

    package var width: CGFloat {
        switch self {
        case .text, .file: 120
        case .screenshot: 96
        case .task: 140
        }
    }
}

package enum AnswerPopupMetrics {
    package static let maxWidth: CGFloat = 580
    package static let screenFraction: CGFloat = 0.76
    package static let paddingTop: CGFloat = 18
    package static let paddingX: CGFloat = 22
    package static let paddingBottom: CGFloat = Space.x4

    /// min(580, 76 % of the screen), as Incredible's `min(580px, 76vw)`.
    package static func width(screen: CGFloat) -> CGFloat {
        min(maxWidth, (screen * screenFraction).rounded())
    }

    /// The gap between the close row and the first block.
    package static let closeGap: CGFloat = 12
    /// The air between the island's shape and the popup below it.
    package static let dropGap: CGFloat = 8

    /// What the popup adds OUTSIDE its scroll: top padding, the close row,
    /// the gap under it, bottom padding. The scroll's cap subtracts this or
    /// a tall answer clips at the panel's edge (review 16m H2).
    package static var chrome: CGFloat {
        paddingTop + AnswerBlockMetrics.closeSide + closeGap + paddingBottom
    }
}

/// "Abriendo Safari, Notas…" as a verb and one chip per target.
package enum ReferentLine {
    package static func parts(_ targets: [String], language: AppLanguage)
        -> (verb: String, referents: [String])
    {
        let referents = targets.filter(ParentTool.names)
        guard !referents.isEmpty else {
            return (ParentToolCopy.acting([], language), [])
        }
        return (Localized.string("island.opening", language: language), referents)
    }
}

/// The status words. Acting no longer chips its targets here: the reel
/// under the line carries the app (K9).
struct IslandStatusText: View {
    let line: IslandState.Line

    var body: some View {
        if let shown = IslandCopy.visibleLine(line) {
            Text(shown)
                .font(GeistFont.uiLabel)
                .foregroundStyle(IslandInk.text)
                .lineLimit(2)
        }
    }
}

/// A line the island does not paint still reaches VoiceOver: an overlay
/// takes no room, so the layout is the same as with no line at all. With
/// nothing painted the row under it has no height, and VoiceOver can skip
/// an element with an empty frame, so the element keeps the meter's.
struct IslandVoiceOverLine: ViewModifier {
    let line: IslandState.Line

    func body(content: Content) -> some View {
        content.overlay(alignment: .leading) {
            if IslandCopy.voiceOverOnly(line) {
                Color.clear
                    .frame(height: IslandChrome.meterSide)
                    .accessibilityElement()
                    .accessibilityLabel(IslandCopy.line(line))
            }
        }
    }
}

/// A tinted label for the thing Companion is pointing at.
struct ReferentChip: View {
    let text: String
    var tint: Color = IslandPalette.accent.color

    var body: some View {
        Text(text)
            .font(Fonts.geist(ReferentChipMetrics.size).weight(.medium))
            .foregroundStyle(tint)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.leading, ReferentChipMetrics.paddingLeading)
            .padding(.trailing, ReferentChipMetrics.paddingTrailing)
            .padding(.vertical, ReferentChipMetrics.paddingY)
            .modifier(HugsUpTo(maxWidth: ReferentChipMetrics.maxWidth))
            .background(Capsule().fill(tint.opacity(ReferentChipMetrics.fill)))
            .overlay(Capsule().strokeBorder(tint.opacity(ReferentChipMetrics.stroke), lineWidth: Stroke.hairline))
    }
}

/// `frame(maxWidth:)` takes whatever it is offered up to the cap, so a
/// short chip in a wide row grew to the cap. This takes the content's own
/// width, never more than the offer or the cap. A truncated label measures
/// a few points under its offer, so a long chip takes the limit outright.
struct HugsUpTo: ViewModifier {
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        CappedWidth(maxWidth: maxWidth) { content }
    }
}

struct CappedWidth: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let limit = min(proposal.width ?? maxWidth, maxWidth)
        let width = min(content.sizeThatFits(.unspecified).width, limit)
        let height = content.sizeThatFits(ProposedViewSize(width: width, height: proposal.height)).height
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

/// A captured thing waiting to go with the next turn: clipboard text, a
/// screenshot, a file or a task.
struct CaptureCard<Content: View>: View {
    let kind: CaptureKind
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(width: kind.width, height: CaptureCardMetrics.height, alignment: .topLeading)
            .padding(kind == .screenshot ? Space.none : Space.x2)
            .background(RoundedRectangle(cornerRadius: CaptureCardMetrics.radius).fill(IslandInk.popover))
            .clipShape(RoundedRectangle(cornerRadius: CaptureCardMetrics.radius))
            .shadow(color: .black.opacity(0.28), radius: 6, y: 4)
    }
}

/// The rich answer surface: headings, lists, tables and code live inside it.
/// 16m-1 moves it to the ovx skin — rgb(14,14,16) under a 12 % rim at radius
/// 20 — which is NOT the popover's n800: the popup reads as its own layer.
struct AnswerPopup<Content: View>: View {
    let screenWidth: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) { content() }
            .padding(.top, AnswerPopupMetrics.paddingTop)
            .padding(.horizontal, AnswerPopupMetrics.paddingX)
            .padding(.bottom, AnswerPopupMetrics.paddingBottom)
            .frame(width: AnswerPopupMetrics.width(screen: screenWidth), alignment: .leading)
            .background(RoundedRectangle(cornerRadius: AnswerBlockMetrics.surfaceRadius)
                .fill(AnswerInk.surface))
            .overlay(RoundedRectangle(cornerRadius: AnswerBlockMetrics.surfaceRadius)
                .strokeBorder(AnswerInk.white(AnswerBlockMetrics.surfaceBorder),
                              lineWidth: Stroke.hairline))
            .elevation(.sheet)
    }
}
