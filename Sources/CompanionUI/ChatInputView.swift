import SwiftUI

public enum ChatInputCopy {
    public static let placeholder = "Escríbele a Companion"
}

private struct ModeSwapChrome: ViewModifier {
    var blur: CGFloat
    var opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: blur)
            .opacity(opacity)
    }
}

extension AnyTransition {
    static var modeSwap: AnyTransition {
        .modifier(
            active: ModeSwapChrome(blur: 8, opacity: 0),
            identity: ModeSwapChrome(blur: 0, opacity: 1))
    }
}

public struct ChatInputView: View {
    @Bindable var chat: ChatViewModel
    var voice: VoiceViewModel
    @FocusState private var focused: Bool
    @State private var hoveringSend = false

    public init(chat: ChatViewModel, voice: VoiceViewModel) {
        self.chat = chat
        self.voice = voice
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: Space.x3) {
            TextField(ChatInputCopy.placeholder, text: $chat.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.uiBody)
                .foregroundStyle(Semantic.foreground)
                .focused($focused)
                .lineLimit(3)
                .onSubmit(send)
                .padding(Space.x4)
            sendButton
        }
        .frame(minHeight: Space.x1 * 12)
        .background(Semantic.surfaceOverlay)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(Semantic.border, lineWidth: Stroke.hairline)
        )
        .animation(.easeOut(duration: MotionTime.base), value: focused)
    }

    private var empty: Bool {
        chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && chat.pendingAttachments.isEmpty
    }

    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: "arrow.up")
                .font(.uiCaption)
                .foregroundStyle(Semantic.accentForeground)
                .frame(width: Space.x8, height: Space.x8)
                .background(Circle().fill(Semantic.accent))
                .scaleEffect(hoveringSend && !empty ? 1.08 : 1)
                .animation(.springHover, value: hoveringSend)
        }
        .buttonStyle(.plain)
        .onHover { hoveringSend = $0 }
        .padding([.bottom, .trailing], Space.x2)
        .disabled(empty || voice.isActive)
        .opacity(empty ? 0.35 : 1)
        .animation(.easeOut(duration: MotionTime.fast), value: empty)
        .accessibilityLabel("Enviar")
    }

    private func send() {
        guard !empty else { return }
        voice.hangUp()
        chat.send()
    }
}
