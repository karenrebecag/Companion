import CompanionCore
import Foundation
import Observation

@Observable
@MainActor
package final class ChatViewModel: ConversationPresenting {
    package internal(set) var needsOnboarding = true
    /// How the launch resolved. `needsOnboarding` stays true until this
    /// settles, so the root never paints the thread and takes it back.
    package internal(set) var startup: StartupState = .probing
    package internal(set) var messages: [ChatMessage] = []
    package internal(set) var streaming = ""
    package internal(set) var busy = false
    struct QueuedMessage: Equatable {
        let text: String
        let origin: MessageOrigin
        var mentions: [Mention] = []
    }

    var queue: [QueuedMessage] = []
    /// What is waiting behind the running turn, in order.
    package var queued: [String] { queue.map(\.text) }
    package internal(set) var pendingAttachments: [AttachmentRef] = []
    package internal(set) var pendingMentions: [Mention] = []
    /// The field changed: a mention whose `@name` is no longer in it is gone,
    /// with its channel, and typing the name again by hand does not bring it back.
    func syncMentions(with words: String) {
        pendingMentions = MentionContext.referenced(pendingMentions, in: words)
    }

    /// A pick from the `@` selector, waiting for the message it belongs to.
    package func addMention(_ mention: Mention) {
        pendingMentions.append(mention)
    }
    package var dropTargeted = false
    package internal(set) var busySince: Date?
    /// The session's state (Wave 12a): kind, job, sheet queue. This model
    /// sends events into it and paints from it; it never writes it.
    package let session: SessionModel
    /// Set by the brake so the job's own ending knows it was stopped rather
    /// than broken.
    var cancelledJob = false
    /// 16h-2: the id of the chat's own job, so its events never land on a
    /// voice-born job's row (or the other way round).
    var chatJobID: JobID?

    package var folderName: String?

    package var folderLabel: String? {
        folderName
            ?? WorkdirPreference.label
            ?? config.workdir.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    package func setFolder(_ path: String) {
        guard WorkdirPreference.isAllowed(path) else { return }
        WorkdirPreference.stored = path
        folderName = WorkdirPreference.label
    }

    /// Asked instead of comparing the label: a translated string deciding
    /// whether a button is enabled breaks the moment the language changes.
    package var hasStoredAttachments: Bool {
        (attachments?.storedBytes() ?? 0) > 0
    }

    package var attachmentsStorageLabel: String {
        let bytes = attachments?.storedBytes() ?? 0
        if bytes <= 0 { return Localized.string("settings.storage.empty") }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    package func purgeStoredAttachments() {
        attachments?.purge()
        pendingAttachments = []
    }
    package internal(set) var recents: [ConversationMeta] = []
    /// The task Follow up handed to the island (spec 16j §8); the next turn
    /// continues it.
    package var followUp: String?
    package internal(set) var errorText: String? {
        // A cleared error re-arms the island for the next identical one.
        didSet { if errorText == nil { dismissedIslandError = nil } }
    }
    /// The chat error the island already showed or was outranked on; it
    /// lives here so a recreated view cannot resurrect it. Home keeps its own.
    package internal(set) var dismissedIslandError: String?
    package var draft = ""
    package var onboardingKey = ""
    package private(set) var onboardingBusy = false

    let chat: any ChatProvider
    let secrets: any SecretStore
    let store: any ConversationStoring
    let config: Config
    /// Spec 15d §5: while the user's words are written to disk, the window
    /// and the island say so.
    package var debugTranscripts: Bool { config.debugTranscripts }
    let startupProbe: (any StartupProbing)?
    /// The local path this user accepted, held in memory so a stale
    /// preference can never unlock the app on its own: it only counts once
    /// the probe has seen that path alive in THIS launch.
    var acceptedLocal: LocalPath?
    var probeTask: Task<Void, Never>?
    let jobSubmitter: (any JobSubmitter)?
    package let notices: NoticeCenter
    let attachments: (any AttachmentStoring)?
    /// The parent's hands (Wave 10b): what the turn does itself, no job.
    let parentTools: (any ParentToolExecuting)?
    /// What the app perceives around the turn (Wave 10a). Sensed for the
    /// current turn only; the thread never shows it, the store never keeps it.
    let sensor: (any ContextSensing)?
    /// Probed at launch and shown in Settings; the sensor reads it per turn.
    package let accessibility: (any AccessibilityChecking)?
    package let screenRecording: (any ScreenRecordingChecking)?
    /// Where `open_url` waits for the sheet (Wave 10c 3D): the same actor
    /// the specialist's permissions go through.
    let approvals: (any ApprovalsProvider)?
    /// A safety, not a goal: normal use is one or two rounds.
    static let maxParentRounds = ParentToolCopy.maxRounds
    var conversationId = UUID().uuidString
    /// Moves only when the history is cleared. Work that started before a
    /// clear compares it, so a thread switch never drops anything.
    var historyEpoch = 0
    /// Jobs a clear stopped: a voice job has no run loop to compare epochs in.
    var jobsStoppedByClear: Set<JobID> = []
    /// Work state of this thread's latest turn; it follows `conversationId`.
    var run: TaskRun?
    var inFlight: Task<Void, Never>?
    /// The thread's own clock (Wave 15a): last `persist()` or `restore()`; nil
    /// while empty. Ephemeral rollover reads this, never a timer.
    var lastActivity: Date?
    let now: @Sendable () -> Date
    let log: @Sendable (String) -> Void

    package init(
        chat: any ChatProvider,
        secrets: any SecretStore,
        store: any ConversationStoring,
        config: Config,
        jobSubmitter: (any JobSubmitter)? = nil,
        notices: NoticeCenter = NoticeCenter(),
        attachments: (any AttachmentStoring)? = nil,
        startupProbe: (any StartupProbing)? = nil,
        parentTools: (any ParentToolExecuting)? = nil,
        sensor: (any ContextSensing)? = nil,
        accessibility: (any AccessibilityChecking)? = nil,
        screenRecording: (any ScreenRecordingChecking)? = nil,
        approvals: (any ApprovalsProvider)? = nil,
        session: SessionModel? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.chat = chat
        self.session = session ?? SessionModel(jobs: jobSubmitter, approvals: approvals)
        self.parentTools = parentTools
        self.sensor = sensor
        self.accessibility = accessibility
        self.screenRecording = screenRecording
        self.approvals = approvals
        self.secrets = secrets
        self.store = store
        self.config = config
        self.startupProbe = startupProbe
        self.jobSubmitter = jobSubmitter
        self.notices = notices
        self.attachments = attachments
        self.now = now
        self.log = log
        self.folderName = WorkdirPreference.label
            ?? config.workdir.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    package func dismissError() {
        errorText = nil
    }

    package func toast(_ text: String, level: NoticeLevel = .info) {
        notices.toast(text, level: level)
    }

    package func submitOnboarding() async {
        guard !onboardingBusy else { return }
        let key = onboardingKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            errorText = ChatCopy.emptyKey
            return
        }
        // A pasted URL or a truncation is answerable here: sending it out
        // buys the same rejection two seconds later and blames the key.
        if !APIKeyShape.looksPlausible(key) {
            errorText = ChatCopy.malformedKey
            return
        }
        onboardingBusy = true
        errorText = nil
        defer { onboardingBusy = false }
        do {
            try await chat.verify(key, provider: .openAI)
            try secrets.write(.openAI, value: key)
            onboardingKey = ""
            startup = .premium
            needsOnboarding = false
            try loadMostRecent()
        } catch {
            errorText = ChatCopy.error(error)
        }
    }

    package func changeKey() {
        abandonTurn()
        dropParentApprovals()
        queue = []
        pendingAttachments = []
        pendingMentions = []
        streaming = ""
        onboardingKey = ""
        errorText = nil
        // Someone already talking to a local model must not go mute for
        // touching the premium field. The door closes only if nothing is left.
        if acceptedLocal == nil { needsOnboarding = true }
    }

    package func send() {
        guard !needsOnboarding else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }
        draft = ""
        errorText = nil
        // Only the mentions whose @name is still in the words travel; what
        // she deleted is gone with it.
        let sent = MentionContext.referenced(pendingMentions, in: text)
        pendingMentions = []
        dispatch(text, origin: .typed, mentions: sent)
    }

    /// A pick from a question card (16m-6) is a typed message: same guards,
    /// same queue, same turn. Not through `draft`: whatever she had half
    /// written in the composer stays.
    /// False when nothing was sent (no key yet, empty label): the card must
    /// not show an answer that never left. The message is marked as a card
    /// pick and never takes the staged attachments.
    @discardableResult
    package func choose(_ label: String) -> Bool {
        guard !needsOnboarding else { return false }
        let text = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        errorText = nil
        dispatch(text, origin: .choice)
        return true
    }

    private func dispatch(_ text: String, origin: MessageOrigin, mentions: [Mention] = []) {
        if busy {
            queue.append(QueuedMessage(text: text, origin: origin, mentions: mentions))
            return
        }
        startTurn(text, origin: origin, mentions: mentions)
    }

    package func newConversation() {
        abandonTurn()
        dropParentApprovals()
        queue = []
        pendingAttachments = []
        pendingMentions = []
        errorText = nil
        persist()
        conversationId = UUID().uuidString
        run = nil
        messages = []
        streaming = ""
        draft = ""
    }

    package func openConversation(_ id: String) {
        guard id != conversationId else { return }
        abandonTurn()
        dropParentApprovals()
        queue = []
        errorText = nil
        persist()
        do {
            guard let record = try store.load(id) else { return }
            restore(record)
            streaming = ""
            pendingAttachments = []
            recents = try store.list()
        } catch {
            errorText = ChatCopy.error(error)
        }
    }

    /// A task's conversation for its detail sheet, read without switching
    /// away from the one in progress.
    package func transcript(_ id: String) -> [ChatMessage] {
        guard id != conversationId else { return messages }
        do {
            return try store.load(id).map { Self.messages(of: $0) } ?? []
        } catch {
            errorText = ChatCopy.error(error)
            return []
        }
    }

    /// Switching conversations abandons the turn in progress; Follow up
    /// waits for it instead of dropping it (code review 16j-2).
    package var canFollowUp: Bool {
        !busy && session.projection.job == nil
    }

    /// Follow up: the task becomes the conversation, and the island carries it.
    @discardableResult
    package func followUp(_ task: ConversationMeta) -> Bool {
        guard canFollowUp else { return false }
        openConversation(task.id)
        followUp = task.title
        return true
    }

    /// Follow up with words from the task sheet: they go straight to the
    /// task, never through `draft`, which holds what she left in Home.
    @discardableResult
    package func followUp(_ task: ConversationMeta, saying text: String) -> Bool {
        guard followUp(task) else { return false }
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !words.isEmpty && !needsOnboarding { dispatch(words, origin: .typed) }
        return true
    }

    package func historyTurns() async -> [Turn] {
        rolloverIfDue()
        return windowedTurns()
    }

    /// Wave 15b-9: what the NEXT turn's clock should read. Nil for an empty
    /// thread, and nil when a rollover is due — read before it actually
    /// happens, so the stale thread's clock never appears as a tag on the
    /// fresh one about to replace it.
    package func lastInteraction() async -> Date? {
        ConversationRollover.shouldRollover(activity(), now: now()) ? nil : lastActivity
    }

    /// Raw words only, in order, no status lines: the session note must not
    /// learn which app was in front (security review 2026-09-05).
    package func memoryTurns() async -> [Turn] {
        messages.compactMap { message in
            guard !message.isStatus, let role = message.role, !message.text.isEmpty
            else { return nil }
            // A job's report is shown whole and remembered bounded; the
            // memory takes the bounded one. A user turn's recall carries the
            // compact context line, so there the painted words win.
            if let recall = message.recall, recall.role == .tool {
                return Turn(role: role, content: recall.content)
            }
            return Turn(role: role, content: message.text)
        }
    }

    package func appendUser(_ text: String) async {
        await appendUser(text, context: nil)
    }

    package func appendUser(_ text: String, context: TurnContext?) async {
        rolloverIfDue()
        messages.append(ChatMessage(
            role: .user, text: text, recall: context.map { recall(text, $0) }))
        persist()
    }

    /// Remembered as "[voice · Safari · 2 docs] text": that there WAS context,
    /// and of what kind — never the clipboard's content.
    func recall(_ text: String, _ ctx: TurnContext) -> Recall {
        Recall(role: .user,
               content: ContextBlock.compact(ctx, language: config.language) + " " + text)
    }

    /// Not a job's end: the voice's replies land here too, and every job
    /// sends its own tagged end (review 16h-2 round 3).
    package func appendAssistant(_ text: String) async {
        // A tool's card lands before the words about it. The island shows one
        // reply per turn, so a separate text message buried the card the
        // moment the voice finished (show_card, 2026-10-06).
        if let last = messages.indices.last, let card = Self.cardOnly(messages[last]) {
            let marker = messages[last].recall?.content ?? ChatCopy.cardShown(card)
            messages[last].text = text
            messages[last].recall = Recall(
                role: .assistant,
                content: ConversationMemory.recall(text) + "\n" + marker)
        } else {
            messages.append(ChatMessage(role: .assistant, text: text))
        }
        persist()
    }

    private static func cardOnly(_ message: ChatMessage) -> Card? {
        guard message.role == .assistant, !message.isStatus, !message.restored,
              message.text.isEmpty else { return nil }
        return message.card
    }

    package func appendStatus(_ text: String) async {
        messages.append(ChatMessage(isStatus: true, text: text))
        persist()
    }

    package func showStream(_ text: String) async {
        streaming = text
    }

    package func finishStream() async {
        streaming = ""
    }
}
