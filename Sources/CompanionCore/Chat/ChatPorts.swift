import Foundation

package enum ChatDelta: Sendable, Equatable {
    case text(String)
    case handoff(Handoff)
    /// Every call of the round together, on purpose: the assistant turn that
    /// remembers the round needs all of them, and the provider rejects a
    /// history where a call is missing its answer (Wave 10c).
    case toolCalls([ToolCallRef])
}

package enum ChatError: Error, Sendable, Equatable {
    case unauthorized, forbidden, rateLimited, timeout, unreachable
    case httpStatus(Int)
    case empty
    case noProvider
    case invalidKey
}

package enum SecretStoreError: Error, Sendable, Equatable {
    case emptyValue, denied, notAvailable
    /// A host-bound secret was asked for with no usable host (20c D6).
    case invalidHost
    case unexpected(Int)
}

package enum PersistenceError: Error, Sendable, Equatable {
    case encoding, decoding, io
}

package protocol SecretStore: Sendable {
    func read(_ key: SecretKey) throws -> String?
    func write(_ key: SecretKey, value: String) throws
    func delete(_ key: SecretKey) throws
}

package protocol ChatProvider: Sendable {
    func stream(_ history: [Turn], tools: [ToolSpec])
        -> AsyncThrowingStream<ChatDelta, Error>
    func verify(_ key: String, provider: ProviderDescriptor) async throws
}

package protocol CapabilityProbe: Sendable {
    func isAvailable(_ provider: ProviderDescriptor) async -> Bool
}

package protocol ConversationStoring: Sendable {
    func list() throws -> [ConversationMeta]
    func save(_ record: ConversationRecord) throws
    func load(_ id: String) throws -> ConversationRecord?
    /// Chats on this computer, and the tasks started inside them. Nothing else.
    func clearHistory() throws
}

package struct ConversationMeta: Sendable, Equatable, Identifiable {
    package var id: String
    package var title: String
    package var updatedAt: Date

    package init(id: String, title: String, updatedAt: Date) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
    }
}

package struct ConversationRecord: Sendable, Equatable, Identifiable {
    package var id: String
    package var title: String
    package var updatedAt: Date
    package var messages: [ConversationMessage]

    package init(
        id: String,
        title: String,
        updatedAt: Date,
        messages: [ConversationMessage]
    ) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
        self.messages = messages
    }
}

package struct ConversationMessage: Sendable, Equatable {
    package var role: String
    package var text: String
    package var attachmentPaths: [String]
    /// The message was a pick on a question card: it stays marked for the
    /// model after a restart (16m-6).
    package var fromChoice: Bool

    package init(role: String, text: String, attachmentPaths: [String] = [], fromChoice: Bool = false) {
        self.role = role
        self.text = text
        self.attachmentPaths = attachmentPaths
        self.fromChoice = fromChoice
    }
}

package protocol ConversationPresenting: Sendable {
    func historyTurns() async -> [Turn]
    func appendUser(_ text: String) async
    /// The thread paints `text`; the memory keeps the compact context line
    /// (Wave 10a). Presenters without a memory of their own take the default.
    func appendUser(_ text: String, context: TurnContext?) async
    /// What the cross-session memory may see: the words, never the context.
    /// What the model sees (`historyTurns`) and what gets written to disk
    /// for next month are two different things.
    func memoryTurns() async -> [Turn]
    func appendAssistant(_ text: String) async
    func appendStatus(_ text: String) async
    func showStream(_ text: String) async
    func finishStream() async
    /// Wave 15b-9: when the thread last had a real turn — spoken, typed, or a
    /// job result landing — so the NEXT turn can say how long it has been.
    /// Nil for a thread with no clock of its own (every fake but the real
    /// presenter) and nil once a rollover is due, so a stale thread's clock
    /// never leaks a tag into the fresh one about to replace it.
    func lastInteraction() async -> Date?
}

extension ConversationPresenting {
    package func appendUser(_ text: String, context: TurnContext?) async {
        await appendUser(text)
    }

    package func memoryTurns() async -> [Turn] {
        await historyTurns()
    }

    package func lastInteraction() async -> Date? { nil }
}
