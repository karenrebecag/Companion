import Foundation

public enum ChatDelta: Sendable, Equatable {
    case text(String)
    case handoff(Handoff)
}

public enum ChatError: Error, Sendable, Equatable {
    case unauthorized, forbidden, rateLimited, timeout, unreachable
    case httpStatus(Int)
    case empty
    case noProvider
    case invalidKey
}

public enum SecretStoreError: Error, Sendable, Equatable {
    case emptyValue, denied, notAvailable
    case unexpected(Int)
}

public enum PersistenceError: Error, Sendable, Equatable {
    case encoding, decoding, io
}

public protocol SecretStore: Sendable {
    func read(_ key: SecretKey) throws -> String?
    func write(_ key: SecretKey, value: String) throws
    func delete(_ key: SecretKey) throws
}

public protocol ChatProvider: Sendable {
    func stream(_ history: [Turn], tools: [ToolSpec])
        -> AsyncThrowingStream<ChatDelta, Error>
    func verify(_ key: String, provider: ProviderDescriptor) async throws
}

public protocol CapabilityProbe: Sendable {
    func isAvailable(_ provider: ProviderDescriptor) async -> Bool
}

public protocol ConversationStoring: Sendable {
    func list() throws -> [ConversationMeta]
    func save(_ record: ConversationRecord) throws
    func load(_ id: String) throws -> ConversationRecord?
}

public struct ConversationMeta: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var updatedAt: Date

    public init(id: String, title: String, updatedAt: Date) {
        self.id = id
        self.title = title
        self.updatedAt = updatedAt
    }
}

public struct ConversationRecord: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var updatedAt: Date
    public var messages: [ConversationMessage]

    public init(
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

public struct ConversationMessage: Sendable, Equatable {
    public var role: String
    public var text: String
    public var attachmentPaths: [String]

    public init(role: String, text: String, attachmentPaths: [String] = []) {
        self.role = role
        self.text = text
        self.attachmentPaths = attachmentPaths
    }
}
