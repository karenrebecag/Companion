import CompanionCore
import SwiftUI

public struct VoiceControlsView: View {
    @Bindable var voice: VoiceViewModel

    public init(voice: VoiceViewModel) {
        self.voice = voice
    }

    public var body: some View {
        HStack(spacing: Space.x2) {
            Button(tapLabel, action: tapMic)
                .font(Font.uiBody)
                .foregroundStyle(Semantic.foreground)
            // On speakers the user cannot talk over the agent, so the escape
            // hatch must be visible. On headphones the flow stays clean: just
            // speak.
            if voice.snapshot.state == .speaking,
               voice.interruptCapability == .tapOnly {
                Button("Interrumpir") { voice.advance() }
                    .font(Font.uiBody)
                    .foregroundStyle(Semantic.accent)
                    .keyboardShortcut(.escape, modifiers: [])
            }
            Button(voice.snapshot.muted ? "Unmute" : "Mute", action: voice.toggleMute)
                .font(Font.uiCaption)
                .foregroundStyle(Semantic.foreground)
                .disabled(!voice.isActive)
            Text(phaseLabel)
                .font(Font.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
            level(voice.levels.mic)
            level(voice.levels.agent)
        }
    }

    private var tapLabel: String {
        VoiceTapAction.label(forState: voice.snapshot.state)
    }

    private func tapMic() {
        let action = VoiceTapAction.forState(voice.snapshot.state)
        switch action {
        case .start:
            voice.start()
        case .interrupt:
            voice.advance()
        case .hangUp:
            voice.hangUp()
        }
    }

    private var phaseLabel: String {
        switch voice.snapshot.state {
        case .idle: "Listo"
        case .connecting: "Conectando"
        case .listening: "Escuchando"
        case .thinking: "Pensando"
        case .speaking: "Hablando"
        case .error: "Error"
        }
    }

    private func level(_ value: Double) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Semantic.accent)
            .frame(width: 6, height: 8 + CGFloat(min(max(value, 0), 1)) * 16)
    }
}
