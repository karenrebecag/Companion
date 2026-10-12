import CompanionCore
import CompanionUIPro
import SwiftUI

// Where a turn ends on the island: the reply and the receipt are one card
// (Incredible's mega card), so what it said, what it did and where to go on
// from there sit together instead of in three stacked pieces.
extension IslandView {
    /// The finished reply takes the card unless something else still needs
    /// the island: the sheet and the undo row keep the old rows they live in.
    static func showsCompletedCard(_ state: IslandState) -> Bool {
        state.line == .completed && state.approval == nil && state.receipt == nil
    }

    func completedCard() -> some View {
        let latest = latestReply
        let parts = latest.map { IslandResultCardModel.proseAndSources(of: $0.text) }
        let words: String = {
            guard var message = latest, let parts else { return "" }
            message.text = parts.prose
            return Self.replyText(for: message)
        }()
        let visuals = latest.map(Self.inlineVisuals) ?? (nil, [])
        return resultCard(
            icon: "text.bubble", spoken: words.isEmpty ? nil : words, steps: [],
            sources: parts?.sources ?? []
        ) {
            VStack(alignment: .leading, spacing: IslandGrid.groupGap) {
                if visuals.0 != nil || !visuals.1.isEmpty {
                    IslandInlineVisuals(card: visuals.0, blocks: visuals.1,
                                        width: IslandResultCardMetrics.bodyWidth, room: IslandFit.tallRoom)
                        .environment(\.diagramRenderer, diagrams)
                        .environment(\.fileSaver, saveFile)
                }
                if let latest { choiceCard(latest) }
            }
        }
        // What tapping the reply did before the card existed.
        .contentShape(Rectangle())
        .onTapGesture { if let latest { openResult(latest.id) } }
    }

    /// The one place a result card is dressed from the island's own data.
    func resultCard<Body: View>(
        icon: String, spoken: String?, steps: [AIResultStep],
        sources: [MarkdownSplitter.SourceLink],
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Body
    ) -> some View {
        IslandResultCard(
            title: IslandResultCardModel.title(
                question: chat.messages.last { $0.role == .user && !$0.isStatus }?.text,
                fallback: Localized.string("island.result.title")),
            icon: icon, spoken: spoken, steps: steps,
            links: IslandResultCardModel.links(apps: chat.session.projection.touched, sources: sources),
            maxHeight: IslandResultCardMetrics.regionHeight(bandHeight: geometry.notch.height),
            onOpenURL: { openURL($0) },
            onDismiss: onDismiss, onContinue: continueInChat, content: content)
    }

    /// The window holds the whole thread and the composer; the reply tap
    /// already opens it, so this is the same road.
    func continueInChat() {
        resultAttention.attended()
        onShowMain()
    }
}
