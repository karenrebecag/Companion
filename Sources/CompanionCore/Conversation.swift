import Foundation

public enum TurnRole: String, Sendable, Equatable {
    case user, assistant, system
}

public enum AttachmentKind: Sendable, Equatable {
    case image, file
}

public struct AttachmentRef: Sendable, Equatable {
    public var name: String
    public var path: String
    public var kind: AttachmentKind

    /// Path, not URL: the model (or an executor) opens the file itself.
    public var promptLine: String { "\(name) → \(path)" }

    public init(name: String, path: String, kind: AttachmentKind) {
        self.name = name
        self.path = path
        self.kind = kind
    }
}

public struct Turn: Sendable, Equatable {
    public var role: TurnRole
    public var content: String
    public var attachments: [AttachmentRef]

    public init(
        role: TurnRole,
        content: String,
        attachments: [AttachmentRef] = []
    ) {
        self.role = role
        self.content = content
        self.attachments = attachments
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
