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
    static func caption(name: String) -> String {
        "El usuario adjuntó \(name). Míralo y espera a que te pregunte."
    }
}

extension VoiceSession {
    public func push(attachment: AttachmentRef) async {
        guard isLiveRealtime else { return }
        guard attachment.kind == .image else { return }
        let name = attachment.name
        let payload = await VoiceAttachmentCodec.resolve(attachment)
        guard isLiveRealtime else { return }
        guard case .imageDataURL(let dataURL) = payload else { return }
        await realtime.send(RealtimeCodec.imageItem(
            dataURL: dataURL, caption: VoiceAttachmentCopy.caption(name: name)))
    }

    var isLiveRealtime: Bool {
        let snap = machine.snapshot
        return snap.pipeline == .realtime
            && snap.state != .idle
            && snap.state != .error
    }
}
