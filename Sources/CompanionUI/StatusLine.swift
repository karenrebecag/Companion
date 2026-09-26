import SwiftUI

public struct StatusLine: View {
    @Environment(\.openURL) private var openURL
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
                if let link = VoiceCopy.settingsLink(after: chat.session.projection.interruption) {
                    Button(Localized.string("permission.open")) { openURL(link) }
                        .buttonStyle(.link)
                        .font(.uiCaption)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                if chat.debugTranscripts {
                    Text(Localized.string("debug.transcriptsOn"))
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.accentText)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                if chat.session.projection.approval != nil {
                    Text(Localized.string("status.approvalWaiting"))
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
            || chat.session.projection.approval != nil
            || chat.debugTranscripts
            || chat.busySince != nil
            || !chat.queued.isEmpty
    }

    @ViewBuilder
    private var workingMeter: some View {
        if let since = chat.busySince {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let secs = Int(context.date.timeIntervalSince(since))
                Text("\(secs / 60):\(String(format: "%02d", secs % 60)) · "  // token-exempt: reloj
                    + Localized.string("status.escToStop"))
                    .font(.uiMicro)
                    .foregroundStyle(Semantic.mutedForeground)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
