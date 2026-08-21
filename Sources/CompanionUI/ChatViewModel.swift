import CompanionCore
import Foundation
import Observation

public struct ChatMessage: Identifiable, Equatable {
    public let id: UUID
    public var role: TurnRole?
    public var isStatus: Bool
    public var text: String

    public init(
        id: UUID = UUID(),
        role: TurnRole? = nil,
        isStatus: Bool = false,
        text: String
    ) {
        self.id = id
        self.role = role
        self.isStatus = isStatus
        self.text = text
    }
}

@Observable
@MainActor
public final class ChatViewModel: ConversationPresenting {
    public private(set) var needsOnboarding = true
    public private(set) var messages: [ChatMessage] = []
    public private(set) var streaming = ""
    public private(set) var busy = false
    public private(set) var queued: [String] = []
    public private(set) var recents: [ConversationMeta] = []
    public private(set) var errorText: String?
    public var draft = ""
    public var onboardingKey = ""
    public private(set) var onboardingBusy = false

    private let chat: any ChatProvider
    private let secrets: any SecretStore
    private let store: any ConversationStoring
    private let config: Config
    private var conversationId = UUID().uuidString
    private var inFlight: Task<Void, Never>?

    public init(
        chat: any ChatProvider,
        secrets: any SecretStore,
        store: any ConversationStoring,
        config: Config
    ) {
        self.chat = chat
        self.secrets = secrets
        self.store = store
        self.config = config
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
        streaming = ""
        busy = false
        needsOnboarding = true
        onboardingKey = ""
        errorText = nil
    }

    public func send() {
        guard !needsOnboarding else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
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
        errorText = nil
        persist()
        conversationId = UUID().uuidString
        messages = []
        streaming = ""
        busy = false
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
        messages.append(ChatMessage(role: .assistant, text: text))
        persist()
    }

    public func appendStatus(_ text: String) async {
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
        messages.append(ChatMessage(role: .user, text: text))
        persist()
        busy = true
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
            let stream = chat.stream(history, tools: [.delegate])
            for try await delta in stream {
                guard isCurrent(id) else { return }
                switch delta {
                case .text(let chunk):
                    preface += chunk
                    streaming = preface
                case .handoff(let value):
                    handoff = value
                }
            }
            guard isCurrent(id) else { return }
            streaming = ""
            commit(preface: preface, handoff: handoff)
            persist()
            busy = false
            drain()
        } catch is CancellationError {
            guard isCurrent(id) else { return }
            streaming = ""
            busy = false
        } catch {
            guard isCurrent(id) else { return }
            streaming = ""
            errorText = ChatCopy.error(error)
            persist()
            busy = false
            drain()
        }
    }

    private func commit(preface: String, handoff: Handoff?) {
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
            return Turn(role: role, content: message.text)
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

    private func persist() {
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
