import CompanionCore
import SwiftUI

public struct VoiceControlsView: View {
    @Bindable var voice: VoiceViewModel

    public init(voice: VoiceViewModel) {
        self.voice = voice
    }

    public var body: some View {
        HStack(spacing: Tokens.Space.s8) {
            Button(tapLabel, action: tapMic)
                .font(Tokens.Typography.body)
                .foregroundStyle(Tokens.Color.fg)
            // On speakers the user cannot talk over the agent, so the escape
            // hatch must be visible. On headphones the flow stays clean: just
            // speak.
            if voice.snapshot.state == .speaking,
               voice.interruptCapability == .tapOnly {
                Button("Interrumpir") { voice.advance() }
                    .font(Tokens.Typography.body)
                    .foregroundStyle(Tokens.Color.accent)
                    .keyboardShortcut(.escape, modifiers: [])
            }
            Button(voice.snapshot.muted ? "Unmute" : "Mute", action: voice.toggleMute)
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Color.fg)
                .disabled(!voice.isActive)
            Text(phaseLabel)
                .font(Tokens.Typography.caption)
                .foregroundStyle(Tokens.Color.muted)
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
            .fill(Tokens.Color.accent)
            .frame(width: 6, height: 8 + CGFloat(min(max(value, 0), 1)) * 16)
    }
}
