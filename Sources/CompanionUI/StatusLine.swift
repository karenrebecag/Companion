import SwiftUI

public struct StatusLine: View {
    var chat: ChatViewModel
    var voice: VoiceViewModel

    public init(chat: ChatViewModel, voice: VoiceViewModel) {
        self.chat = chat
        self.voice = voice
    }

    public var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: Space.x1 + Space.x1 / 2) {
                if let name = chat.folderLabel {
                    Text(name)
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                }
                if let status = voice.statusText, !status.isEmpty {
                    Text(status)
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                        .shimmering(active: ShimmerMotion.isActive(for: voice.snapshot.state))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                if chat.pendingApproval != nil {
                    Text("El especialista espera tu permiso")
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.accentText)
                }
                workingMeter
                if !chat.queued.isEmpty {
                    Text(chat.queued.count == 1
                         ? "En cola: \(chat.queued[0])"
                         : "\(chat.queued.count) mensajes en cola")
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.x4)
            .padding(.top, Space.x2)
            .padding(.bottom, Space.x1)
        }
    }

    private var isVisible: Bool {
        chat.folderLabel != nil
            || !(voice.statusText ?? "").isEmpty
            || chat.pendingApproval != nil
            || chat.busySince != nil
            || !chat.queued.isEmpty
    }

    @ViewBuilder
    private var workingMeter: some View {
        if let since = chat.busySince {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let secs = Int(context.date.timeIntervalSince(since))
                Text("\(secs / 60):\(String(format: "%02d", secs % 60)) · Esc para cortar")
                    .font(.uiMicro)
                    .foregroundStyle(Semantic.mutedForeground)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
