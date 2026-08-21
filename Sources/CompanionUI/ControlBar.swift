import CompanionCore
import SwiftUI

public enum ControlBarMetrics {
    public static let orbVoice: CGFloat = 68
    public static let orbText: CGFloat = 46
    public static let roundIcon: CGFloat = 34

    public static func orbSize(_ mode: InteractionMode) -> CGFloat {
        mode == .voice ? orbVoice : orbText
    }
}

public enum MuteChrome {
    public static func bordered(muted: Bool) -> Bool { !muted }
}

private struct ControlSwapChrome: ViewModifier {
    var blur: CGFloat
    var scale: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .scaleEffect(scale)
            .opacity(opacity)
    }
}

private extension AnyTransition {
    static var controlSwap: AnyTransition {
        .modifier(
            active: ControlSwapChrome(blur: 8, scale: 0.8, opacity: 0),
            identity: ControlSwapChrome(blur: 0, scale: 1, opacity: 1))
    }
}

struct RoundIconButton: View {
    var symbol: String = ""
    var icon: CompanionIcon? = nil
    let foreground: Color
    let background: Color
    var bordered = true
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if let icon {
                    IconGlyph(icon: icon, size: 14)
                } else {
                    Image(systemName: symbol)
                        .font(.uiCaption)
                }
            }
            .foregroundStyle(foreground)
            .frame(
                width: ControlBarMetrics.roundIcon,
                height: ControlBarMetrics.roundIcon)
            .background(Circle().fill(background))
            .overlay(
                Circle().stroke(
                    Semantic.border,
                    lineWidth: bordered ? Stroke.hairline : 0))
            .scaleEffect(hovering ? 1.08 : 1)
            .animation(.springHover, value: hovering)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}

struct OrbButton: View {
    var voice: VoiceViewModel
    var mode: InteractionMode
    @State private var hovering = false

    var body: some View {
        let size = ControlBarMetrics.orbSize(mode)
        Button {
            switch VoiceTapAction.forState(voice.snapshot.state) {
            case .start: voice.start()
            case .interrupt: voice.advance()
            case .hangUp: voice.hangUp()
            }
        } label: {
            Orb(
                state: voice.snapshot.state,
                levels: voice.levels,
                accentColor: Semantic.accent
            )
            .frame(width: size, height: size)
            .scaleEffect(hovering && !voice.isActive ? 1.06 : 1)
            .animation(.springHover, value: hovering)
            .opacity(voice.isActive || hovering ? 1 : 0.85)
        }
        .buttonStyle(OrbPressStyle())
        .onHover { hovering = $0 }
        .help(voice.isActive ? "Interrumpir / colgar" : "Hablar")
        .accessibilityLabel(voice.isActive ? "Interrumpir / colgar" : "Hablar")
    }
}

public struct ControlBar: View {
    var voice: VoiceViewModel
    var mode: InteractionMode

    public init(voice: VoiceViewModel, mode: InteractionMode) {
        self.voice = voice
        self.mode = mode
    }

    public var body: some View {
        HStack(spacing: Space.x3) {
            if !voice.isActive {
                OrbButton(voice: voice, mode: mode)
                    .transition(.controlSwap)
            }
            if voice.isActive {
                muteButton
                    .transition(.controlSwap)
                hangButton
                    .transition(.controlSwap)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.snappy, value: voice.isActive)
        .animation(.snappy, value: voice.snapshot.muted)
    }

    private var muteButton: some View {
        let muted = voice.snapshot.muted
        return RoundIconButton(
            symbol: muted ? "mic.slash.fill" : "mic.fill",
            foreground: muted
                ? Semantic.destructiveForeground
                : Semantic.foreground,
            background: muted ? Semantic.destructive : Semantic.surface,
            bordered: MuteChrome.bordered(muted: muted),
            help: muted ? "Activar micrófono" : "Silenciar micrófono"
        ) { voice.toggleMute() }
    }

    private var hangButton: some View {
        RoundIconButton(
            icon: .cross,
            foreground: Semantic.foreground,
            background: Semantic.surface,
            help: "Colgar"
        ) { voice.hangUp() }
    }
}
