import CompanionCore
import CompanionUIPro
import SwiftUI

// The island's written conversation (`.chat`): Arc's ai-chat thread and
// composer on the result document's paper. The turns come from the same
// mapping the task window uses (`ChatTurns`), so a reply, its tools, its
// sources and the specialist's run read the same in both places.

enum IslandChatModel {
    /// The last few conversations of the thread: the panel is a glance, the
    /// window holds the rest. A cut lands on a user's message, so a reply is
    /// never shown without what it answers.
    static func recent(_ messages: [ChatMessage], turns: Int = DocChatMetrics.turns) -> [ChatMessage] {
        let asks = messages.indices.filter { messages[$0].role == .user && !messages[$0].isStatus }
        guard asks.count > turns else { return messages }
        return Array(messages[asks[asks.count - turns]...])
    }

    static func thread(_ messages: [ChatMessage], live: ChatLive?) -> ChatTurns.Thread {
        ChatTurns.thread(recent(messages), live: live)
    }

    /// The `companion:` fences are drawn under the answer by the island's own
    /// visuals and choice card, so in the text they take no room. Any other
    /// fence stays the port's code block.
    static func fence(_ fence: AIChatFence) -> AnyView? {
        fence.language.hasPrefix("companion:") ? AnyView(EmptyView()) : nil
    }

    /// What a turn draws under its words: the card its reply carried on its
    /// own channel, and the diagrams and cards its fences hold.
    static func visuals(of turn: AIChatTurn, cards: [String: [Card]]) -> IslandView.InlineVisuals {
        guard let answer = turn.answer else { return ([], []) }
        let fenced = IslandView.inlineVisuals(ChatMessage(role: .assistant, text: answer.text), turnCards: [])
        return (cards[turn.id] ?? [], fenced.blocks)
    }
}

extension AIThreadStyle {
    /// The chat on the result document: the card's white inks over its own
    /// fill, Arc's raised surface for the composer.
    static var notchChat: AIThreadStyle {
        let white = Color.white
        return AIThreadStyle(
            foreground: white.opacity(DocCardInk.value),
            secondary: white.opacity(DocCardInk.secondary),
            muted: white.opacity(DocCardInk.label),
            surface: DocCardInk.surface.color,
            surfaceMuted: DocCardInk.toolFill.color,
            border: white.opacity(DocCardInk.edge),
            borderStrong: white.opacity(DocCardInk.edgeFocus),
            userBubble: DocCardInk.toolFill.color,
            primary: ArcTone.accent.color,
            primaryForeground: DocCardInk.surface.color,
            success: DocCardInk.checkMark.color,
            body: Fonts.geist(DocChatMetrics.bodySize),
            caption: Fonts.geist(DocChatMetrics.captionSize),
            mono: .uiMono,
            heading: Fonts.geist(DocChatMetrics.headingSize).weight(.medium),
            danger: ArcTone.danger.color,
            raised: DocCardInk.raised.color)
    }

    /// The composer's one filled button is white on the dark paper, as the
    /// notch bar's send always was; blue stays the run's.
    static var notchComposer: AIThreadStyle {
        var style = notchChat
        style.primary = Color.white.opacity(DocCardInk.title)
        return style
    }
}

/// The panel itself, from plain inputs so it can be drawn without a session.
struct IslandChatPanel<Composer: View, Rows: View>: View {
    let thread: ChatTurns.Thread
    let maxHeight: CGFloat
    let onOpenURL: (URL) -> Void
    /// What sits between the thread and the composer: a choice card, the
    /// staged files, the undo, a caption. Empty rows take no room.
    @ViewBuilder let rows: () -> Rows
    @ViewBuilder let composer: () -> Composer

    var body: some View {
        IslandChatLayout(maxHeight: maxHeight, gap: DocChatMetrics.gap) {
            AIChatThread(
                turns: thread.turns, strings: TaskThread.chatStrings, style: .notchChat,
                padding: EdgeInsets(top: DocChatMetrics.threadTop, leading: DocChatMetrics.inset,
                                    bottom: DocChatMetrics.threadBottom, trailing: DocChatMetrics.inset),
                // The panel is a glance: the newest steps, the whole run in the window.
                runDensity: .compact(rows: IslandResultCardMetrics.runRows),
                allowsLink: { label, url in !MarkdownView.disguises(label, url) },
                fence: IslandChatModel.fence, onOpenURL: onOpenURL
            ) { turn in
                let visuals = IslandChatModel.visuals(of: turn, cards: thread.cards)
                if !visuals.cards.isEmpty || !visuals.blocks.isEmpty {
                    IslandInlineVisuals(cards: visuals.cards, blocks: visuals.blocks,
                                        width: IslandResultCardMetrics.bodyWidth, room: IslandFit.tallRoom)
                }
            }
            rows()
                .padding(.horizontal, DocChatMetrics.inset)
            composer()
                .padding(.horizontal, DocChatMetrics.composerInset)
                .padding(.bottom, DocChatMetrics.composerInset)
        }
        .frame(width: DocCardMetrics.width)
        .modifier(DocCardSurface(accent: DocCardInk.narrative))
        .accessibilityElement(children: .contain)
    }
}

/// The thread takes whatever the rows and the composer leave under the cap,
/// and no more than its own content: a short conversation hugs it, a long
/// one scrolls inside the card instead of pushing the composer out of it.
struct IslandChatLayout: Layout {
    let maxHeight: CGFloat
    let gap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let heights = measure(width: width, subviews: subviews)
        return CGSize(width: width, height: heights.reduce(0, +) + spacing(heights))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let heights = measure(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (view, height) in zip(subviews, heights) {
            view.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                       proposal: ProposedViewSize(width: bounds.width, height: height))
            if height > 0 { y += height + gap }
        }
    }

    private func measure(width: CGFloat, subviews: Subviews) -> [CGFloat] {
        let natural = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        guard let thread = natural.first else { return [] }
        let rest = Array(natural.dropFirst())
        let room = maxHeight - rest.reduce(0, +) - spacing(natural)
        return [min(thread, max(room, 0))] + rest
    }

    private func spacing(_ heights: [CGFloat]) -> CGFloat {
        gap * CGFloat(max(0, heights.filter { $0 > 0 }.count - 1))
    }
}
