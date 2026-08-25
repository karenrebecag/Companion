import CompanionCore
import Foundation
import Observation

/// How a message enters the model's memory, when that differs from how the
/// reader sees it. The thread and the model's history used to be one array,
/// and their requirements are opposite: the reader wants the whole report, the
/// model wants a bounded, correctly attributed trace of it.
public struct Recall: Sendable, Equatable {
    public var role: TurnRole
    public var content: String
    public var toolCalls: [ToolCallRef]
    public var toolCallID: String?

    public init(
        role: TurnRole,
        content: String,
        toolCalls: [ToolCallRef] = [],
        toolCallID: String? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }
}

public struct ChatMessage: Identifiable, Equatable {
    public let id: UUID
    public var role: TurnRole?
    public var isStatus: Bool
    public var text: String
    public var attachments: [AttachmentRef]
    /// Painted from its own channel, not parsed out of the text. A card that
    /// is here never passed through the model.
    public var card: Card?
    /// nil means "remember me as you read me", which is every ordinary
    /// message and therefore changes nothing for them.
    public var recall: Recall?

    public init(
        id: UUID = UUID(),
        role: TurnRole? = nil,
        isStatus: Bool = false,
        text: String,
        attachments: [AttachmentRef] = [],
        card: Card? = nil,
        recall: Recall? = nil
    ) {
        self.id = id
        self.role = role
        self.isStatus = isStatus
        self.text = text
        self.attachments = attachments
        self.card = card
        self.recall = recall
    }
}

@Observable
@MainActor
public final class ChatViewModel: ConversationPresenting {
    public internal(set) var needsOnboarding = true
    /// How the launch resolved. `needsOnboarding` stays true until this
    /// settles, so the root never paints the thread and takes it back.
    public internal(set) var startup: StartupState = .probing
    public internal(set) var messages: [ChatMessage] = []
    public private(set) var streaming = ""
    public private(set) var busy = false
    public private(set) var queued: [String] = []
    public internal(set) var pendingAttachments: [AttachmentRef] = []
    public var dropTargeted = false
    public private(set) var busySince: Date?
    /// Non-nil while a specialist works: the live card owns the steps.
    public internal(set) var job: JobTimeline?
    /// Set by the brake so the job's own ending knows it was stopped rather
    /// than broken.
    var cancelledJob = false
    /// Whether this job has had anything approved yet. A job whose FIRST
    /// action you refuse is almost never one you want carrying on by another
    /// route — which is exactly what happened when a denial stopped `diskutil`
    /// and the job finished with `df -h` anyway.
    var jobHasApprovedAction = false

    public var folderName: String?

    public var folderLabel: String? {
        folderName
            ?? WorkdirPreference.label
            ?? config.workdir.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    public func setFolder(_ path: String) {
        guard WorkdirPreference.isAllowed(path) else { return }
        WorkdirPreference.stored = path
        folderName = WorkdirPreference.label
    }

    /// Asked instead of comparing the label: a translated string deciding
    /// whether a button is enabled breaks the moment the language changes.
    public var hasStoredAttachments: Bool {
        (attachments?.storedBytes() ?? 0) > 0
    }

    public var attachmentsStorageLabel: String {
        let bytes = attachments?.storedBytes() ?? 0
        if bytes <= 0 { return Localized.string("settings.storage.empty") }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    public func purgeStoredAttachments() {
        attachments?.purge()
        pendingAttachments = []
    }
    public private(set) var recents: [ConversationMeta] = []
    public internal(set) var errorText: String?
    /// Non-nil while the specialist waits for a decision; the sheet binds here.
    public internal(set) var pendingApproval: ApprovalRequest?
    public var draft = ""
    public var onboardingKey = ""
    public private(set) var onboardingBusy = false

    private let chat: any ChatProvider
    let secrets: any SecretStore
    private let store: any ConversationStoring
    private let config: Config
    let startupProbe: (any StartupProbing)?
    /// The local path this user accepted, held in memory so a stale
    /// preference can never unlock the app on its own: it only counts once
    /// the probe has seen that path alive in THIS launch.
    var acceptedLocal: LocalPath?
    var probeTask: Task<Void, Never>?
    let jobSubmitter: (any JobSubmitter)?
    public let notices: NoticeCenter
    let attachments: (any AttachmentStoring)?
    var conversationId = UUID().uuidString
    private var inFlight: Task<Void, Never>?

    public init(
        chat: any ChatProvider,
        secrets: any SecretStore,
        store: any ConversationStoring,
        config: Config,
        jobSubmitter: (any JobSubmitter)? = nil,
        notices: NoticeCenter = NoticeCenter(),
        attachments: (any AttachmentStoring)? = nil,
        startupProbe: (any StartupProbing)? = nil
    ) {
        self.chat = chat
        self.secrets = secrets
        self.store = store
        self.config = config
        self.startupProbe = startupProbe
        self.jobSubmitter = jobSubmitter
        self.notices = notices
        self.attachments = attachments
        self.folderName = WorkdirPreference.label
            ?? config.workdir.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    public func toast(_ text: String, level: NoticeLevel = .info) {
        notices.toast(text, level: level)
    }

    public func submitOnboarding() async {
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

    public func changeKey() {
        inFlight?.cancel()
        inFlight = nil
        queued = []
        pendingAttachments = []
        streaming = ""
        busy = false
        busySince = nil
        onboardingKey = ""
        errorText = nil
        // Someone already talking to a local model must not go mute for
        // touching the premium field. The door closes only if nothing is left.
        if acceptedLocal == nil { needsOnboarding = true }
    }

    public func send() {
        guard !needsOnboarding else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !pendingAttachments.isEmpty else { return }
        draft = ""
        errorText = nil
        if busy {
            queued.append(text)
            return
        }
        startTurn(text)
    }

    public func newConversation() {
        inFlight?.cancel()
        inFlight = nil
        queued = []
        pendingAttachments = []
        errorText = nil
        persist()
        conversationId = UUID().uuidString
        messages = []
        streaming = ""
        busy = false
        busySince = nil
        draft = ""
    }

    public func openConversation(_ id: String) {
        guard id != conversationId else { return }
        inFlight?.cancel()
        inFlight = nil
        queued = []
        errorText = nil
        persist()
        do {
            guard let record = try store.load(id) else { return }
            restore(record)
            streaming = ""
            busy = false
            busySince = nil
            pendingAttachments = []
            recents = try store.list()
        } catch {
            errorText = ChatCopy.error(error)
        }
    }

    public func historyTurns() async -> [Turn] {
        windowedTurns()
    }

    public func appendUser(_ text: String) async {
        messages.append(ChatMessage(role: .user, text: text))
        persist()
    }

    public func appendAssistant(_ text: String) async {
        // A result landing means the job is over: a live card left running
        // under the report is the app lying about what it is doing.
        finishJob()
        messages.append(ChatMessage(role: .assistant, text: text))
        persist()
    }

    public func appendStatus(_ text: String) async {
        finishJob()
        messages.append(ChatMessage(isStatus: true, text: text))
        persist()
    }

    public func showStream(_ text: String) async {
        streaming = text
    }

    public func finishStream() async {
        streaming = ""
    }

    private func startTurn(_ text: String) {
        let staged = pendingAttachments
        pendingAttachments = []
        messages.append(ChatMessage(role: .user, text: text, attachments: staged))
        persist()
        busy = true
        busySince = Date()
        streaming = ""
        let history = windowedTurns()
        let id = conversationId
        inFlight = Task { [weak self] in
            await self?.consume(history: history, conversationId: id)
        }
    }

    private func consume(history: [Turn], conversationId id: String) async {
        guard isCurrent(id) else { return }
        var preface = ""
        var handoff: Handoff?
        do {
            let stream = chat.stream(history, tools: [.delegate(config.language)])
            for try await delta in stream {
                guard isCurrent(id) else { return }
                switch delta {
                case .text(let chunk):
                    preface += chunk
                    streaming = preface
                case .handoff(let value):
                    handoff = value
                case .toolCall:
                    // Tool calls other than delegate are for specialists only, ignore here
                    break
                }
            }
            guard isCurrent(id) else { return }
            streaming = ""
            await commit(preface: preface, handoff: handoff)
            persist()
            busy = false
            busySince = nil
            drain()
        } catch is CancellationError {
            guard isCurrent(id) else { return }
            streaming = ""
            busy = false
            busySince = nil
        } catch {
            guard isCurrent(id) else { return }
            streaming = ""
            errorText = ChatCopy.error(error)
            persist()
            busy = false
            busySince = nil
            drain()
        }
    }

    private func commit(preface: String, handoff: Handoff?) async {
        if let handoff, let submitter = jobSubmitter {
            await runJob(preface: preface, handoff: handoff, submitter: submitter)
            return
        }

        // Fallback: show status if no runner
        if let handoff {
            if !preface.isEmpty {
                messages.append(ChatMessage(role: .assistant, text: preface))
            }
            messages.append(ChatMessage(
                isStatus: true, text: ChatCopy.handoffUnavailable(handoff)))
            return
        }

        if !preface.isEmpty {
            messages.append(ChatMessage(role: .assistant, text: preface))
        }
    }

    /// Test seam: the history the provider would receive, which is now a
    /// different thing from what the thread shows.
    func historyForTests() -> [Turn] { windowedTurns() }

    private func drain() {
        guard !needsOnboarding, !queued.isEmpty else { return }
        startTurn(queued.removeFirst())
    }

    private func isCurrent(_ id: String) -> Bool {
        conversationId == id && !Task.isCancelled
    }

    func windowedTurns() -> [Turn] {
        let turns: [Turn] = messages.compactMap { message in
            // A status line carries no memory of its own — unless it was given
            // one, which is how the delegate call survives in the history.
            if let recall = message.recall {
                return Turn(
                    role: recall.role, content: recall.content,
                    attachments: message.attachments,
                    toolCalls: recall.toolCalls,
                    toolCallID: recall.toolCallID)
            }
            if message.isStatus { return nil }
            guard let role = message.role else { return nil }
            // What the assistant said goes through the same filter as a
            // specialist report: card payloads are interface, not context, and
            // the chat layer can emit them too now.
            let content = role == .assistant
                ? ConversationMemory.recall(message.text)
                : message.text
            return Turn(
                role: role, content: content,
                attachments: message.attachments)
        }
        let window = max(0, config.chat.historyWindow)
        guard window > 0, turns.count > window else { return turns }
        // What falls out of the window leaves a note instead of a hole.
        let kept = Self.dropOrphanedToolTurns(Array(turns.suffix(window)))
        let dropped = Array(turns.prefix(turns.count - window))
        guard let note = ConversationMemory.compaction(
            of: dropped, language: config.language)
        else { return kept }
        return [note] + kept
    }

    /// The window can fall between a delegate call and the result that answers
    /// it. A tool turn whose call was cut away is not merely useless: the
    /// provider rejects the whole request over it, so the turn after a long
    /// conversation would fail outright.
    static func dropOrphanedToolTurns(_ turns: [Turn]) -> [Turn] {
        var known: Set<String> = []
        var kept: [Turn] = []
        for turn in turns {
            for call in turn.toolCalls { known.insert(call.id) }
            if turn.role == .tool {
                guard let id = turn.toolCallID, known.contains(id) else {
                    continue
                }
            }
            kept.append(turn)
        }
        return kept
    }

    func loadMostRecent() throws {
        recents = try store.list()
        guard let meta = recents.first, let record = try store.load(meta.id) else {
            conversationId = UUID().uuidString
            messages = []
            return
        }
        restore(record)
    }

    private func restore(_ record: ConversationRecord) {
        conversationId = record.id
        messages = record.messages.map { item in
            if item.role == "status" {
                return ChatMessage(isStatus: true, text: item.text)
            }
            return ChatMessage(role: TurnRole(rawValue: item.role), text: item.text)
        }
    }

    func persist() {
        let stored = messages.map { message -> ConversationMessage in
            let role = message.isStatus ? "status" : (message.role?.rawValue ?? "assistant")
            return ConversationMessage(role: role, text: message.text)
        }
        guard !stored.isEmpty else { return }
        let title = messages.first { $0.role == .user }
            .map { String($0.text.prefix(48)) }
            ?? Localized.string("thread.untitled")
        let record = ConversationRecord(
            id: conversationId, title: title, updatedAt: Date(), messages: stored)
        do {
            try store.save(record)
            recents = try store.list()
        } catch {
            errorText = ChatCopy.error(error)
        }
    }
}
