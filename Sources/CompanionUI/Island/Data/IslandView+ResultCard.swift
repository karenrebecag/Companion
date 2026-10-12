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
        let document = latest.map { IslandResultCardModel.document(of: $0.text) }
        // The words are gated by the same rule the card always used: a reply
        // that only repeats the choice's question has no prose of its own.
        let hasWords = latest.map { !Self.replyText(for: $0).isEmpty } ?? false
        let visuals = latest.map(Self.inlineVisuals) ?? (nil, [])
        return resultCard(blocks: hasWords ? document?.blocks ?? [] : [], sources: document?.sources ?? []) {
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

    /// What the turn was asked, on one line: the document's title.
    var resultTitle: String {
        IslandResultCardModel.title(
            question: chat.messages.last { $0.role == .user && !$0.isStatus }?.text,
            fallback: Localized.string("island.result.title"))
    }

    /// The one place a result card is dressed from the island's own data.
    func resultCard<Body: View>(
        blocks: [AnswerBlock], sources: [MarkdownSplitter.SourceLink],
        @ViewBuilder content: @escaping () -> Body
    ) -> some View {
        IslandResultCard(
            title: resultTitle, blocks: blocks,
            links: IslandResultCardModel.links(apps: chat.session.projection.touched, sources: sources),
            maxHeight: IslandChrome.columnMaxHeight(bandHeight: geometry.notch.height),
            onOpenURL: { openURL($0) },
            onDismiss: nil, onContinue: continueInChat, content: content)
    }

    /// The window holds the whole thread and the composer; the reply tap
    /// already opens it, so this is the same road.
    func continueInChat() {
        resultAttention.attended()
        onShowMain()
    }
}
