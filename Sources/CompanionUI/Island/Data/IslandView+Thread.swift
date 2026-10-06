import CompanionCore
import CompanionUIPro
import SwiftUI

// The island's conversation is CompanionUIPro's AIThread, the same block the
// task window uses, in the island's dark tokens: the user's turns as bubbles,
// the replies as plain text, newest at the bottom.

enum IslandThreadModel {
    /// The last few turns; the window holds the rest.
    static let limit = 6
    /// The thread scrolls, so it cannot hug its content inside the island's
    /// fixed-size measurement: it gets a height of its own.
    // HACK: fixed height leaves room above a single short turn. Measure the rows when the package exposes their height.
    static let height: CGFloat = 300

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
            .frame(height: IslandThreadModel.height)
        }
        if let latest = latestReply {
            choiceCard(latest)
        } else {
            // A realtime reply reaches the thread only at transcript.done; until then the caption is all there is.
            IslandLiveReply(voice: voice, text: "", startedAt: replyStart, speaking: false, look: .thread)
                .islandContentColumn()
        }
    }

    @ViewBuilder
    private func threadReply(_ item: AIThreadItem, _ state: IslandState) -> some View {
        if let message = chat.messages.first(where: { $0.id.uuidString == item.id }) {
            let text = Self.replyText(for: message)
            VStack(alignment: .leading, spacing: Space.x1) {
                // Only the newest reply follows the live caption; older ones are settled text.
                if message.id == latestReply?.id {
                    IslandLiveReply(voice: voice, text: text, startedAt: replyStart,
                                    speaking: state.meter == .agent, look: .thread)
                } else {
                    IslandReply(text: text, startedAt: replyStart, speaking: false, look: .thread)
                }
                // A card or a diagram does not fit the thread: the window shows it.
                if results.contains(where: { $0.id == message.id }) {
                    Text(Localized.string("island.result.open"))
                        .font(GeistFont.uiCaption)
                        .foregroundStyle(ArcTone.textSecondary.color)
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
