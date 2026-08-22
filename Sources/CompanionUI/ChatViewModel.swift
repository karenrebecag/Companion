import CompanionCore
import Foundation
import Observation

public struct ChatMessage: Identifiable, Equatable {
    public let id: UUID
    public var role: TurnRole?
    public var isStatus: Bool
    public var text: String
    public var attachments: [AttachmentRef]

    public init(
        id: UUID = UUID(),
        role: TurnRole? = nil,
        isStatus: Bool = false,
        text: String,
        attachments: [AttachmentRef] = []
    ) {
        self.id = id
        self.role = role
        self.isStatus = isStatus
        self.text = text
        self.attachments = attachments
    }
}

@Observable
@MainActor
public final class ChatViewModel: ConversationPresenting {
    public private(set) var needsOnboarding = true
    public internal(set) var messages: [ChatMessage] = []
    public private(set) var streaming = ""
    public private(set) var busy = false
    public private(set) var queued: [String] = []
    public internal(set) var pendingAttachments: [AttachmentRef] = []
    public var dropTargeted = false
    public private(set) var busySince: Date?
    /// Non-nil while a specialist works: the live card owns the steps.
    public internal(set) var job: JobTimeline?

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

    public var attachmentsStorageLabel: String {
        let bytes = attachments?.storedBytes() ?? 0
        if bytes <= 0 { return "Nada guardado" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    public func purgeStoredAttachments() {
        attachments?.purge()
        pendingAttachments = []
    }
    public private(set) var recents: [ConversationMeta] = []
    public private(set) var errorText: String?
    /// Non-nil while the specialist waits for a decision; the sheet binds here.
    public internal(set) var pendingApproval: ApprovalRequest?
    public var draft = ""
    public var onboardingKey = ""
    public private(set) var onboardingBusy = false

    private let chat: any ChatProvider
    private let secrets: any SecretStore
    private let store: any ConversationStoring
    private let config: Config
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
        attachments: (any AttachmentStoring)? = nil
    ) {
        self.chat = chat
        self.secrets = secrets
        self.store = store
        self.config = config
        self.jobSubmitter = jobSubmitter
        self.notices = notices
        self.attachments = attachments
        self.folderName = WorkdirPreference.label
            ?? config.workdir.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    public func toast(_ text: String, level: NoticeLevel = .info) {
        notices.toast(text, level: level)
    }

    public func onAppear() {
        do {
            let raw = try secrets.read(.openAI)
            let key = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if key.isEmpty {
                needsOnboarding = true
                return
            }
            needsOnboarding = false
        } catch {
            needsOnboarding = true
            errorText = ChatCopy.error(error)
            return
        }
        do {
            try loadMostRecent()
        } catch {
            errorText = ChatCopy.error(error)
        }
    }

    public func submitOnboarding() async {
        guard !onboardingBusy else { return }
        let key = onboardingKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty {
            errorText = ChatCopy.emptyKey
            return
        }
        onboardingBusy = true
        errorText = nil
        defer { onboardingBusy = false }
        do {
            try await chat.verify(key, provider: .openAI)
            try secrets.write(.openAI, value: key)
            onboardingKey = ""
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
        needsOnboarding = true
        onboardingKey = ""
        errorText = nil
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
                isStatus: true, text: ChatCopy.handoff(handoff)))
            return
        }

        if !preface.isEmpty {
            messages.append(ChatMessage(role: .assistant, text: preface))
        }
    }

    private func drain() {
        guard !needsOnboarding, !queued.isEmpty else { return }
        startTurn(queued.removeFirst())
    }

    private func isCurrent(_ id: String) -> Bool {
        conversationId == id && !Task.isCancelled
    }

    private func windowedTurns() -> [Turn] {
        let turns: [Turn] = messages.compactMap { message in
            if message.isStatus { return nil }
            guard let role = message.role else { return nil }
            return Turn(
                role: role, content: message.text,
                attachments: message.attachments)
        }
        let window = max(0, config.chat.historyWindow)
        guard window > 0, turns.count > window else { return turns }
        return Array(turns.suffix(window))
    }

    private func loadMostRecent() throws {
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
            .map { String($0.text.prefix(48)) } ?? "Conversación"
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
