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
                // What the specialist did, folded to its newest steps: the
                // whole run is one tap away in the chat.
                if let record = ChatAgentRun.latestRecord(chat.messages) {
                    AIAgentRunView(
                        run: ChatAgentRun.finished(record), strings: ChatAgentRun.strings, style: .notchRun,
                        density: .compact(rows: IslandResultCardMetrics.runRows))
                }
                if let latest { choiceCard(latest) }
            }
        }
        // The card already shows the whole document: a tap anywhere goes on
        // in the chat, like its button, instead of a popup of the same text.
        .contentShape(Rectangle())
        .onTapGesture { continueInChat() }
        .onExitCommand(perform: dismissResult)
    }

    /// The card has no clock when it needs scroll, so this is its way out.
    func dismissResult() {
        resultAttention.attended()
        chat.session.send(.resultDismissed)
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
        // No heading means no title of the reply's own: the generic one, not
        // the user's question cut short.
        let headed = IslandResultCardModel.splitHeading(blocks)
        return IslandResultCard(
            title: headed.title ?? Localized.string("island.result.title"), blocks: headed.body,
            links: IslandResultCardModel.links(apps: chat.session.projection.touched, sources: sources),
            maxHeight: IslandChrome.columnMaxHeight(bandHeight: geometry.notch.height),
            onOpenURL: { openURL($0) },
            onDismiss: dismissResult, onContinue: continueInChat, content: content)
    }

    /// The window holds the whole thread and the composer, so it opens on
    /// this reply's conversation, not on Home where she would have to find it.
    func continueInChat() {
        resultAttention.attended()
        NotificationCenter.default.post(name: .companionOpenConversation, object: nil)
        onShowMain()
        // The window has the whole thread now; the card has nothing left to do.
        chat.session.send(.resultDismissed)
    }
}
