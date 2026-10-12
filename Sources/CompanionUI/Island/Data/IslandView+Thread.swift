import CompanionCore
import CompanionUIPro
import SwiftUI

// The island's conversation is CompanionUIPro's AIThread, the same block the
// task window uses, in the island's dark tokens: the user's turns as bubbles,
// the replies as plain text, newest at the bottom.

enum IslandThreadModel {
    /// The last few turns; the window holds the rest.
    static let limit = 6
    /// The tallest the thread gets before it scrolls; below that it takes its
    /// content's height (`ThreadHug`).
    static let height: CGFloat = 300
    /// Air between the field and the thread's faded top edge.
    static let fieldGap: CGFloat = Space.x4

    /// A visual needs more than a short turn: the thread grows to a share of the notch's cap.
    static func height(drawsVisual: Bool) -> CGFloat {
        drawsVisual ? max(height, IslandFit.tallRoom) : height
    }

    static func items(_ messages: [ChatMessage]) -> [AIThreadItem] {
        TaskThread.items(Array(TaskThread.visible(messages).suffix(limit)))
    }
}

extension AIThreadStyle {
    static var island: AIThreadStyle {
        AIThreadStyle(
            foreground: ArcTone.foreground.color,
            secondary: ArcTone.textSecondary.color,
            muted: ArcTone.textMuted.color,
            surface: ArcTone.surface.color,
            surfaceMuted: ArcTone.surfaceMuted.color,
            border: ArcTone.border.color,
            borderStrong: IslandArc.borderStrong.color,
            userBubble: ArcTone.surfaceMuted.color,
            primary: ArcTone.foreground.color,
            primaryForeground: IslandInk.panel,
            success: ArcTone.success.color,
            body: GeistFont.uiBody,
            caption: GeistFont.uiCaption,
            mono: .uiMono)
    }
}

extension IslandView {
    @ViewBuilder
    func thread(_ state: IslandState) -> some View {
        let items = IslandThreadModel.items(chat.messages)
        if !items.isEmpty {
            AIThread(items: items, strings: TaskThread.strings, style: .island) { item in
                threadReply(item, state)
            }
            // The package fades its top 36 pt; without a gap the oldest turn
            // sat half-dissolved against the field.
            .padding(.top, IslandThreadModel.fieldGap)
            .modifier(ThreadHug(maxHeight: IslandThreadModel.height(drawsVisual: chat.messages.contains { message in
                items.contains { $0.id == message.id.uuidString } && Self.drawsInline(message)
            })))
            .environment(\.diagramRenderer, diagrams)
            .environment(\.fileSaver, saveFile)
        }
        if let latest = latestReply {
            choiceCard(latest)
        } else {
            // A realtime reply reaches the thread only at transcript.done; until then the caption is all there is.
            IslandLiveReply(voice: voice, text: "", startedAt: replyStart, speaking: false, look: .thread)
                .islandContentColumn()
        }
    }

    /// The same split the result card makes: the "Sources" list leaves the
    /// prose and becomes chips, so it is not read twice as bare text.
    static func threadWords(_ message: ChatMessage) -> (text: String, sources: [MarkdownSplitter.SourceLink]) {
        let parts = IslandResultCardModel.proseAndSources(of: message.text)
        var prose = message
        prose.text = parts.prose
        return (replyText(for: prose), parts.sources)
    }

    @ViewBuilder
    private func threadReply(_ item: AIThreadItem, _ state: IslandState) -> some View {
        if let message = chat.messages.first(where: { $0.id.uuidString == item.id }) {
            let (text, sources) = Self.threadWords(message)
            VStack(alignment: .leading, spacing: Space.x1) {
                // Only the newest reply follows the live caption; older ones are settled text.
                if message.id == latestReply?.id {
                    IslandLiveReply(voice: voice, text: text, startedAt: replyStart,
                                    speaking: state.meter == .agent, look: .thread)
                } else {
                    IslandReply(text: text, startedAt: replyStart, speaking: false, look: .thread)
                }
                IslandSourceChips(
                    links: IslandResultCardModel.links(apps: [], sources: sources), onOpen: { openURL($0) })
                let visuals = Self.inlineVisuals(message)
                if visuals.card != nil || !visuals.blocks.isEmpty {
                    IslandInlineVisuals(card: visuals.card, blocks: visuals.blocks,
                                        width: IslandFit.threadWidth,
                                        room: IslandThreadModel.height(drawsVisual: true))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { openResult(message.id) }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Localized.string("island.reply.open"))
            .accessibilityAction { openResult(message.id) }
        }
    }
}

/// The thread's ScrollView is greedy under a proposed height, which is why it
/// had a fixed one. Asked for its ideal size it reports its content's, so the
/// height is that, capped, and the child is then handed the capped height to
/// scroll within.
private struct ThreadHug: ViewModifier {
    let maxHeight: CGFloat

    func body(content: Content) -> some View {
        HuggedHeight(maxHeight: maxHeight) { content }
    }
}

private struct HuggedHeight: Layout {
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let natural = content.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? natural.width, height: min(natural.height, maxHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}
