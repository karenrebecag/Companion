import CompanionCore
import SwiftUI

/// Incredible's task detail (spec 16j §8): the conversation, the details on
/// the side, and Follow up, which hands the task to the island.
struct TaskDetailSheet: View {
    let task: ConversationMeta
    let messages: [ChatMessage]
    /// False while another turn works: switching would drop it.
    let canFollowUp: Bool
    let onFollowUp: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            header
            HStack(alignment: .top, spacing: Space.x4) {
                VStack(alignment: .leading, spacing: Space.x3) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Space.x3) {
                            ForEach(TaskThread.visible(messages)) { message in
                                bubble(message)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                    footer
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                details
                    .frame(width: MainWindowMetrics.detailSide)
            }
        }
        .padding(Space.x6)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(Semantic.background))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Semantic.border, lineWidth: Stroke.hairline))
    }

    private var header: some View {
        HStack(spacing: Space.x3) {
            Text(task.title)
                .font(.uiSubtitle)
                .foregroundStyle(Semantic.foreground)
                .lineLimit(1)
            Spacer()
            Text(HomeCopy.ago(task.updatedAt))
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
            CloseButton(action: onClose)
        }
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: Space.x8)
                Text(message.text)
                    .font(.uiBody)
                    .foregroundStyle(IslandInk.text)
                    .padding(.horizontal, Space.x4)
                    .padding(.vertical, Space.x3)
                    .background(RoundedRectangle(cornerRadius: Radius.xl).fill(IslandInk.panel))
                    .textSelection(.enabled)
            }
        } else {
            MarkdownView(text: message.text)
                .padding(.horizontal, Space.x4)
                .padding(.vertical, Space.x3)
                .background(RoundedRectangle(cornerRadius: Radius.xl).fill(Semantic.muted))
                .padding(.trailing, Space.x8)
        }
    }

    private var footer: some View {
        HStack {
            Text(footerLine)
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
            Spacer()
            // The sheet's one primary action.
            Button(action: onFollowUp) {
                Label(Localized.string("task.followUp"), systemImage: "arrowshape.turn.up.left")
            }
            .buttonStyle(.shadcn(.default, size: .sm))
            .disabled(!canFollowUp)
        }
    }

    private var footerLine: String {
        Localized.string(canFollowUp ? "task.next" : "task.busy")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text(Localized.string("task.details"))
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
            detail(Localized.string("task.updated"), HomeCopy.ago(task.updatedAt))
            detail(Localized.string("task.messages"), "\(TaskThread.visible(messages).count)")
            Spacer(minLength: Space.none)
        }
        .padding(Space.x4)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: Radius.xl).fill(Semantic.muted))
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Semantic.foreground)
            Spacer()
            Text(value).foregroundStyle(Semantic.mutedForeground)
        }
        .font(.uiCaption)
    }
}

/// The rows a saved task shows.
enum TaskThread {
    /// Status lines are the island's to say (16j-1); the thread keeps the
    /// user's turns and the replies, as Incredible's conversation does.
    static func visible(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.filter { !$0.isStatus }
    }
}
