import CompanionCore
import CompanionUIPro
import SwiftUI

/// A task's conversation (spec 16j §8) as one focused thread, after Arc's
/// ai-composer block: the newest turn in view, and a composer whose words
/// become the task's next turn before the island carries it on.
struct TaskDetailSheet: View {
    let task: ConversationMeta
    let messages: [ChatMessage]
    /// False while another turn works: switching would drop it.
    let canFollowUp: Bool
    /// The words to continue with, empty to continue without any. False when
    /// the task could not be taken over, so the sheet gives the words back.
    let onFollowUp: (String) -> Bool
    let onClose: () -> Void

    @State private var draft: String
    @State private var sending = false
    /// The message on its way, drawn in the thread while it lifts.
    @State private var sent: AIThreadItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        task: ConversationMeta, messages: [ChatMessage], canFollowUp: Bool,
        draft: String = "", onFollowUp: @escaping (String) -> Bool, onClose: @escaping () -> Void
    ) {
        self.task = task
        self.messages = messages
        self.canFollowUp = canFollowUp
        self._draft = State(initialValue: draft)
        self.onFollowUp = onFollowUp
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: Space.none) {
            header
            AIThread(items: items, strings: TaskThread.strings, style: .companion) { item in
                MarkdownView(text: item.text)
                    .textSelection(.enabled)
            }
            AIComposer(
                text: $draft, phase: phase, strings: TaskThread.strings, style: .companion,
                focusOnAppear: true, onSubmit: submit)
                .padding(.horizontal, Space.x5)
                .padding(.bottom, Space.x5)
        }
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(Semantic.background))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Semantic.border, lineWidth: Stroke.hairline))
    }

    private var items: [AIThreadItem] {
        TaskThread.items(messages) + (sent.map { [$0] } ?? [])
    }

    private var phase: AIComposerPhase {
        AIComposerPhase.resolve(draft: draft, sending: sending, available: canFollowUp)
    }

    /// The title starts where the thread's text does; only the close button
    /// sits out at the sheet's corner.
    private var header: some View {
        VStack(alignment: .leading, spacing: Space.x0_5) {
            Text(task.title)
                .font(.uiSubtitle)
                .foregroundStyle(Semantic.foreground)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Text(TaskThread.subtitle(ago: HomeCopy.ago(task.updatedAt), count: TaskThread.visible(messages).count))
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
                .lineLimit(1)
        }
        .padding(.horizontal, Space.x7)
        .frame(maxWidth: AIThreadLayout.columnWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Space.x12)
        .padding(.top, Space.x6)
        .padding(.bottom, Space.x2)
        .overlay(alignment: .topTrailing) {
            CloseButton(action: onClose).padding(Space.x4)
        }
    }

    private func submit() {
        guard phase.acceptsInput else { return }
        let words = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        sending = true
        // Without words, or without motion, there is nothing to watch land.
        guard !words.isEmpty, !reduceMotion else { return handOff(words) }
        // The thread plays the lift itself; the sheet only waits for it to land.
        sent = AIThreadItem(id: "sent", role: .user, text: words)
        draft = ""
        Task {
            do {
                try await Task.sleep(for: .seconds(AIThreadStyle.companion.motion.liftDuration))
            } catch {
                // Only cancellation throws here, and a cancelled wait sends nothing.
                return
            }
            handOff(words)
        }
    }

    private func handOff(_ words: String) {
        guard !onFollowUp(words) else { return }
        // Another turn started while the message lifted: nothing was sent,
        // so the words go back where she wrote them.
        sending = false
        sent = nil
        draft = words
    }
}

/// The rows a saved task shows.
enum TaskThread {
    /// Status lines are the island's to say (16j-1); the thread keeps the
    /// user's turns and the replies, as Incredible's conversation does.
    static func visible(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.filter { !$0.isStatus }
    }

    static func items(_ messages: [ChatMessage]) -> [AIThreadItem] {
        visible(messages).map { message in
            AIThreadItem(
                id: message.id.uuidString,
                role: message.role == .user ? .user : .assistant,
                text: message.text,
                attachments: message.attachments.map(\.name),
                tools: tools(of: message))
        }
    }

    /// The tools a reply called, once each, in the order it called them. Only
    /// live replies carry them: a task read back from disk has no record, and
    /// then the thread shows none rather than guessing.
    static func tools(of message: ChatMessage) -> [String] {
        guard message.role != .user, let calls = message.recall?.toolCalls else { return [] }
        return calls.map(\.name).reduce(into: []) { names, name in
            if !names.contains(name) { names.append(name) }
        }
    }

    static func subtitle(ago: String, count: Int) -> String {
        let messages = count == 1
            ? Localized.string("task.count.one")
            : String(format: Localized.string("task.count.other"), count)
        return "\(ago) · \(messages)"
    }

    static var strings: AIThreadStrings {
        AIThreadStrings(
            userPrefix: Localized.string("task.you"),
            assistantPrefix: Localized.string("task.assistant"),
            toolsLabel: Localized.string("task.tools"),
            placeholder: Localized.string("task.placeholder"),
            send: Localized.string("task.send"),
            continue: Localized.string("task.followUp"),
            sending: Localized.string("task.sending"),
            hint: Localized.string("task.next"),
            unavailableHint: Localized.string("task.busy"),
            emptyTitle: Localized.string("task.empty.title"),
            emptyText: Localized.string("task.empty.text"))
    }
}

extension AIThreadStyle {
    /// The thread in Companion's tokens: neutral surfaces, the user's turn on
    /// the muted fill, primary ink for the one action.
    static var companion: AIThreadStyle {
        AIThreadStyle(
            foreground: Semantic.foreground,
            secondary: Semantic.mutedForeground,
            muted: Semantic.textMuted,
            surface: Semantic.surface,
            surfaceMuted: Semantic.muted,
            border: Semantic.border,
            borderStrong: Semantic.borderStrong,
            userBubble: Semantic.muted,
            primary: Semantic.primary,
            primaryForeground: Semantic.primaryForeground,
            success: Semantic.success,
            body: .uiBody,
            caption: .uiCaption,
            mono: .uiMono)
    }
}
