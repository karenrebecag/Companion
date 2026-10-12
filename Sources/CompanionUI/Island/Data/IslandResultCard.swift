import CompanionCore
import CompanionUIPro
import SwiftUI

// The island's result card (Incredible's "mega card"): one CompanionUIPro
// AIResultCard in the island's dark tokens. The block owns the header, the
// steps, the chips and the actions; the host owns every word and the body.

enum IslandResultCardMetrics {
    /// The block pads its own sides by this much; it does not export it.
    static let blockPadX: CGFloat = 18
    /// The body's widest: the card is widened by its own padding (see
    /// `IslandResultCard`), so content gets the shell's whole column.
    static let bodyWidth: CGFloat = IslandGrid.openColumn
    /// What the block spends outside its scroll region (header, footer with
    /// chips and actions): the region gets the column's cap minus this.
    static let outsideRegion: CGFloat = 160
    /// A column squeezed by a tall band still leaves room to read.
    static let minRegion: CGFloat = 120

    /// The region's height from the column the island can give the card.
    static func regionHeight(bandHeight: CGFloat) -> CGFloat {
        max(minRegion, IslandChrome.columnMaxHeight(bandHeight: bandHeight) - outsideRegion)
    }
}

extension AIResultStyle {
    static var island: AIResultStyle {
        AIResultStyle(
            // The open island is the card (Incredible): same black, no rim of its own.
            background: IslandInk.panel, border: .clear,
            foreground: ArcTone.foreground.color, secondary: ArcTone.textSecondary.color,
            muted: ArcTone.textMuted.color, surfaceMuted: ArcTone.surfaceMuted.color,
            accent: ArcTone.accent.color, success: ArcTone.success.color, danger: ArcTone.danger.color,
            title: Fonts.geist(TypeSize.rowTitle).weight(.medium), body: GeistFont.uiBody,
            caption: GeistFont.uiCaption)
    }
}

extension AIResultStrings {
    static func island(language: AppLanguage) -> AIResultStrings {
        func text(_ key: String) -> String { Localized.string("island.result." + key, language: language) }
        // The summary closure is Sendable, so it cannot reach the main-actor catalog itself.
        let one = text("steps.one")
        let other = text("steps.other")
        return AIResultStrings(
            statusWorking: text("status.working"), statusDone: text("status.done"),
            statusFailed: text("status.failed"), stepPending: text("step.pending"),
            stepRunning: text("step.running"), stepDone: text("step.done"), stepFailed: text("step.failed"),
            stepsSummary: { count in String(format: count == 1 ? one : other, count) },
            expanded: text("expanded"), collapsed: text("collapsed"), loading: text("loading"),
            dismiss: text("dismiss"), continueInChat: text("continue"), linksLabel: text("links"))
    }
}

/// The adapter: what a finished turn or errand hands over, painted by the block.
struct IslandResultCard<Body: View>: View {
    let title: String
    let icon: String
    let spoken: String?
    let steps: [AIResultStep]
    let links: IslandResultCardModel.Links
    let maxHeight: CGFloat
    let onOpenURL: (URL) -> Void
    var onDismiss: (() -> Void)?
    var onContinue: (() -> Void)?
    @ViewBuilder let content: () -> Body

    var body: some View {
        AIResultCard(
            title: title, icon: .symbol(icon), status: .done, spoken: spoken, steps: steps,
            links: links.chips, maxHeight: maxHeight, strings: .island(language: Localized.language()),
            style: .island,
            // Without addresses the chips are labels: a button needs somewhere to go.
            onOpen: links.urls.isEmpty ? nil : { link in
                if let url = links.urls[link.id] { onOpenURL(url) }
            },
            onDismiss: onDismiss, onContinue: onContinue, content: content)
        // The block cannot drop its own side padding or radius, so it is made
        // as much wider as that padding: its content lands on the shell's
        // margin and its black edge hides under the island's.
        .padding(.horizontal, -IslandResultCardMetrics.blockPadX)
    }
}
