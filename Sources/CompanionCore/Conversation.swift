import Foundation

public enum TurnRole: String, Sendable, Equatable {
    case user, assistant, system, tool
}

public enum AttachmentKind: Sendable, Equatable {
    case image, file
}

public struct AttachmentRef: Sendable, Equatable {
    public var id: UUID
    public var name: String
    public var path: String
    public var kind: AttachmentKind
    public var byteCount: Int

    /// Path, not URL: the model (or an executor) opens the file itself.
    public var promptLine: String { "\(name) → \(path)" }

    public init(
        name: String,
        path: String,
        kind: AttachmentKind,
        byteCount: Int = 0,
        id: UUID = UUID()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.kind = kind
        self.byteCount = byteCount
    }
}

/// One tool the model asked for. The provider needs the id back on the result
/// message, so the whole call must survive in the history.
public struct ToolCallRef: Sendable, Equatable {
    public var id: String
    public var name: String
    public var arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public struct Turn: Sendable, Equatable {
    public var role: TurnRole
    public var content: String
    public var attachments: [AttachmentRef]
    /// Set on the assistant turn that requested tools.
    public var toolCalls: [ToolCallRef]
    /// Set on a `.tool` turn: which call this result answers. The API rejects
    /// a tool message without it.
    public var toolCallID: String?

    public init(
        role: TurnRole,
        content: String,
        attachments: [AttachmentRef] = [],
        toolCalls: [ToolCallRef] = [],
        toolCallID: String? = nil
    ) {
        self.role = role
        self.content = content
        self.attachments = attachments
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    /// Numbering is how the model tells three attachments apart.
    public static func numbered(
        _ text: String,
        _ attachments: [AttachmentRef]
    ) -> String {
        guard !attachments.isEmpty else { return text }
        let tags = attachments.enumerated().map { index, attachment in
            attachment.kind == .image
                ? "[Imagen \(index + 1)]"
                : "[Archivo \(index + 1): \(attachment.name)]"
        }.joined(separator: " ")
        return text.isEmpty ? tags : tags + " " + text
    }
}
