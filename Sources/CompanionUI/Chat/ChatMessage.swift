import CompanionCore
import Foundation

/// The message model: what a turn leaves in the transcript. Split out of
/// ChatViewModel when it crossed the 400-line gate.

/// How a message enters the model's memory, when that differs from how the
/// reader sees it. The thread and the model's history used to be one array,
/// and their requirements are opposite: the reader wants the whole report, the
/// model wants a bounded, correctly attributed trace of it.
package struct Recall: Sendable, Equatable {
    package var role: TurnRole
    package var content: String
    package var toolCalls: [ToolCallRef]
    package var toolCallID: String?

    package init(
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

/// Where a user message came from. A pick on a question card is an answer to
/// that question and nothing more; the model is told so (16m-6 security).
package enum MessageOrigin: Sendable, Equatable {
    case typed
    case choice
}

package struct ChatMessage: Identifiable, Equatable {
    package let id: UUID
    package var role: TurnRole?
    package var isStatus: Bool
    package var text: String
    package var attachments: [AttachmentRef]
    /// Painted from its own channel, not parsed out of the text. A card that
    /// is here never passed through the model.
    package var card: Card?
    /// nil means "remember me as you read me", which is every ordinary
    /// message and therefore changes nothing for them.
    package var recall: Recall?
    package var origin: MessageOrigin
    package var mentions: [Mention] = []
    /// The status line a failed turn leaves: what lets a question that was
    /// answered into a failure be asked again.
    package var isFailure: Bool
    /// Read back from disk, not made in this session: a question card in it
    /// has no live turn behind it.
    package var restored: Bool

    package init(
        id: UUID = UUID(),
        role: TurnRole? = nil,
        isStatus: Bool = false,
        text: String,
        attachments: [AttachmentRef] = [],
        card: Card? = nil,
        recall: Recall? = nil,
        origin: MessageOrigin = .typed,
        mentions: [Mention] = [],
        isFailure: Bool = false,
        restored: Bool = false
    ) {
        self.id = id
        self.role = role
        self.isStatus = isStatus
        self.text = text
        self.attachments = attachments
        self.card = card
        self.recall = recall
        self.mentions = mentions
        self.origin = origin
        self.isFailure = isFailure
        self.restored = restored
    }
}
