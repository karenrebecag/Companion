import CompanionCore
import Foundation

/// Test seam: encoding is I/O and must not sit on the VoiceSession actor.
enum VoiceAttachmentCodec: Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var boxed:
        @Sendable (AttachmentRef) async -> AttachmentPayload? = decode

    static var resolve: @Sendable (AttachmentRef) async -> AttachmentPayload? {
        get { lock.withLock { boxed } }
        set { lock.withLock { boxed = newValue } }
    }

    static func reset() { resolve = decode }

    static func decode(_ ref: AttachmentRef) async -> AttachmentPayload? {
        let root = URL(fileURLWithPath: ref.path).deletingLastPathComponent()
        return AttachmentStore(root: root).payload(for: ref)
    }
}

enum VoiceAttachmentCopy {
    /// Model-facing, so it travels in the session's language: an English
    /// session getting a Spanish instruction was the last monolingual string
    /// the Wave 9 audit flagged (9j-4).
    static func caption(name: String, language: AppLanguage) -> String {
        switch language {
        case .en:
            return "The user attached \(name). Look at it and wait to be asked."
        case .es:
            return "El usuario adjuntó \(name). Míralo y espera a que te pregunte."
        }
    }
}

extension VoiceSession {
    package func push(attachment: AttachmentRef) async {
        guard isLiveRealtime else { return }
        guard attachment.kind == .image else { return }
        let name = attachment.name
        let payload = await VoiceAttachmentCodec.resolve(attachment)
        guard isLiveRealtime else { return }
        guard case .imageDataURL(let dataURL) = payload else { return }
        await realtime.send(RealtimeCodec.imageItem(
            dataURL: dataURL,
            caption: VoiceAttachmentCopy.caption(
                name: name, language: configProvider.current.language)))
    }

    var isLiveRealtime: Bool {
        let snap = machine.snapshot
        return snap.pipeline == .realtime
            && snap.state != .idle
            && snap.state != .error
    }
}
