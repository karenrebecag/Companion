import CompanionCore
import SwiftUI

// Wave 16l-4: the island's own ink and the pieces Incredible draws inside
// it, measured in its overlay CSS (docs/research/incredible-componentes.md).

/// White over the black island, as Incredible's `--ci-*` alphas.
public enum IslandAlpha {
    public static let text = 0.95
    public static let secondary = 0.64
    public static let muted = 0.42
    public static let tile = 0.06
    public static let tileHover = 0.12
    public static let border = 0.09
    public static let divider = 0.07
}

public enum IslandPalette {
    public static let accent = Swatch("78AAFF")
    public static let error = Swatch("FF7A64")
    /// The answer option's hover.
    public static let indigo = Swatch("8184F8")
}

public enum IslandMetrics {
    public static let sendSide: CGFloat = 30
    public static let openRadius: CGFloat = Radius.panel
    /// The open island's edge: `--color-border-default` on the overlay.
    public static let rimAlpha = 0.12
}

public enum AnswerOptionMetrics {
    public static let paddingY: CGFloat = 11
    public static let paddingX: CGFloat = Space.x3
    public static let radius: CGFloat = 12
    public static let gap: CGFloat = 11
}

public enum ReferentChipMetrics {
    public static let radius: CGFloat = 7
    public static let paddingLeading: CGFloat = 5
    public static let paddingTrailing: CGFloat = 7
    public static let paddingY: CGFloat = 1
    public static let size: CGFloat = 12.5
    public static let maxWidth: CGFloat = 230
    public static let fill = 0.13
    public static let stroke = 0.24
}

public enum CaptureCardMetrics {
    public static let height: CGFloat = 64
    public static let radius: CGFloat = Radius.md
}

public enum CaptureKind: CaseIterable, Sendable {
    case text, screenshot, file, task

    public var width: CGFloat {
        switch self {
        case .text, .file: 120
        case .screenshot: 96
        case .task: 140
        }
    }
}

public enum AnswerPopupMetrics {
    public static let maxWidth: CGFloat = 580
    public static let screenFraction: CGFloat = 0.76
    public static let paddingTop: CGFloat = 18
    public static let paddingX: CGFloat = 22
    public static let paddingBottom: CGFloat = Space.x4

    /// min(580, 76 % of the screen), as Incredible's `min(580px, 76vw)`.
    public static func width(screen: CGFloat) -> CGFloat {
        min(maxWidth, (screen * screenFraction).rounded())
    }

    /// The gap between the close row and the first block.
    public static let closeGap: CGFloat = 12
    /// The air between the island's shape and the popup below it.
    public static let dropGap: CGFloat = 8

    /// What the popup adds OUTSIDE its scroll: top padding, the close row,
    /// the gap under it, bottom padding. The scroll's cap subtracts this or
    /// a tall answer clips at the panel's edge (review 16m H2).
    public static var chrome: CGFloat {
        paddingTop + AnswerBlockMetrics.closeSide + closeGap + paddingBottom
    }
}

/// "Abriendo Safari, Notas…" as a verb and one chip per target.
public enum ReferentLine {
    public static func parts(_ targets: [String], language: AppLanguage)
        -> (verb: String, referents: [String])
    {
        let referents = targets.filter { !$0.isEmpty }
        guard !referents.isEmpty else {
            return (ParentToolCopy.acting([], language), [])
        }
        return (Localized.string("island.opening", language: language), referents)
    }
}

/// "Abriendo" followed by a chip per target; any other line stays text.
struct IslandStatusText: View {
    let line: IslandState.Line

    var body: some View {
        if case .acting(let targets) = line,
           case let parts = ReferentLine.parts(targets, language: Localized.language()),
           !parts.referents.isEmpty
        {
            HStack(spacing: Space.x1) {
                Text(parts.verb)
                    .font(GeistFont.uiLabel)
                    .foregroundStyle(IslandInk.text)
                ForEach(parts.referents, id: \.self) { ReferentChip(text: $0) }
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(IslandCopy.line(line))
                .font(GeistFont.uiLabel)
                .foregroundStyle(IslandInk.text)
                .lineLimit(2)
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
            .frame(maxWidth: ReferentChipMetrics.maxWidth, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: ReferentChipMetrics.radius)
                .fill(tint.opacity(ReferentChipMetrics.fill)))
            .overlay(RoundedRectangle(cornerRadius: ReferentChipMetrics.radius)
                .strokeBorder(tint.opacity(ReferentChipMetrics.stroke), lineWidth: Stroke.hairline))
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
