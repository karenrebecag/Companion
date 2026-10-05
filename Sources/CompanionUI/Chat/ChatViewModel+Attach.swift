import CompanionCore
import Foundation

extension ChatViewModel {
    package func attach(_ url: URL) -> AttachmentRef? {
        try? attachResult(url).get()
    }

    /// The same staging with its refusal kept, for callers that tell the
    /// user why a file did not go in (the island's drop zone).
    package func attachResult(_ url: URL) -> Result<AttachmentRef, AttachmentError> {
        guard let attachments else { return .failure(.io) }
        do {
            let ref = try attachments.adopt(url, conversationId: conversationId)
            pendingAttachments.append(ref)
            toast(ChatCopy.attached(ref.name))
            return .success(ref)
        } catch let error as AttachmentError {
            toast(ChatCopy.attachFailed(error), level: .error)
            return .failure(error)
        } catch {
            toast(ChatCopy.attachFailed(.io), level: .error)
            return .failure(.io)
        }
    }

    package func removePending(_ ref: AttachmentRef) {
        pendingAttachments.removeAll { $0.id == ref.id }
        attachments?.discard(ref)
    }
}
