import CompanionCore
import Foundation

extension ChatViewModel {
    public func attach(_ url: URL) -> AttachmentRef? {
        guard let attachments else { return nil }
        do {
            let ref = try attachments.adopt(url, conversationId: conversationId)
            toast(ChatCopy.attached(ref.name))
            return ref
        } catch let error as AttachmentError {
            toast(ChatCopy.attachFailed(error), level: .error)
            return nil
        } catch {
            toast(ChatCopy.attachFailed(.io), level: .error)
            return nil
        }
    }
}
