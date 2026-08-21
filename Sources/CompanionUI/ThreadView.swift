import CompanionCore
import SwiftUI

public enum ChatIdle {
    public static let phrases = [
        "Lista cuando tú lo estés",
        "¿En qué andamos hoy?",
        "Cuéntame qué sigue",
        "Tu Mac y yo, a tus órdenes",
        "Dime y lo hacemos",
        "Empecemos cuando quieras",
    ]

    public static let bubbleRadius: CGFloat = Radius.xl

    public static func caption(_ mode: InteractionMode) -> String {
        switch mode {
        case .voice:
            "Toca el orb de abajo para empezar a hablar"
        case .text:
            "Escribe abajo y presiona Enter"
        }
    }
}

public struct ThreadView: View {
    @Bindable var model: ChatViewModel
    var mode: InteractionMode
    public init(
        chat: ChatViewModel,
        mode: InteractionMode = .voice
    ) {
        self.model = chat
        self.mode = mode
    }

    public var body: some View {
        VStack(spacing: Space.none) {
            Group {
                if isIdle {
                    idleHero
                } else {
                    invertedThread
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let error = model.errorText {
                Text(error)
                    .font(Font.uiCaption)
                    .foregroundStyle(Semantic.destructive)
                    .padding(.horizontal, Space.x4)
                    .padding(.vertical, Space.x2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isIdle: Bool {
        model.messages.isEmpty && model.streaming.isEmpty && !model.busy
    }

    /// The rest state: the mascot greets and a phrase invites (prototype's
    /// idle hero). GeometryReader READS the space instead of asking for it —
    /// a hard size becomes a minimum height and stretches the window.
    private var idleHero: some View {
        GeometryReader { geo in
            // What remains after reserving room for the two text lines.
            let side = min(69 * Space.x1, max(0, geo.size.height - 24 * Space.x1))
            VStack(spacing: Space.x3) {
                MascotView(excited: !model.draft.isEmpty)
                    .frame(width: side * mascotAspect, height: side)
                VStack(spacing: Space.x1) {
                    TypewriterView(phrases: ChatIdle.phrases)
                        .font(.uiTitle)
                        .foregroundStyle(Semantic.foreground)
                    Text(ChatIdle.caption(mode))
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                        .transition(.opacity)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(.horizontal, Space.x4)
    }

    /// Artboard 475x453; el ancho sale del alto disponible.
    private var mascotAspect: CGFloat { 475.0 / 453.0 }

    private var invertedThread: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Space.stack) {
                    if model.busy, model.streaming.isEmpty {
                        skeleton
                            .upsideDown()
                    }
                    if !model.streaming.isEmpty {
                        assistantRow(
                            model.streaming.trimmingCharacters(
                                in: .whitespacesAndNewlines) + " ▍")
                            .upsideDown()
                            .id("streaming")
                    }
                    queuedRows
                    ForEach(model.messages.reversed()) { message in
                        messageRow(message)
                            .upsideDown()
                            .id(message.id)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, Space.x4)
            .upsideDown()
            .onChange(of: model.messages.count) { _, _ in
                proxy.scrollTo(model.messages.last?.id)
            }
            .onChange(of: model.streaming) { _, _ in
                proxy.scrollTo("streaming")
            }
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Space.x1 + Space.x1 / 2) {
            Capsule().fill(Semantic.hover)
                .frame(width: Space.x1 * 52, height: Space.x2)
            Capsule().fill(Semantic.hover)
                .frame(width: Space.x1 * 38, height: Space.x2)
        }
        .shimmering(active: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Space.x3)
    }

    @ViewBuilder
    private var queuedRows: some View {
        if !model.queued.isEmpty {
            VStack(alignment: .leading, spacing: Space.x1) {
                ForEach(Array(model.queued.enumerated()), id: \.offset) { _, text in
                    Text("En cola: \(text)")
                        .font(Font.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                        .lineLimit(1)
                }
            }
            .upsideDown()
        }
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        if message.isStatus {
            Text(message.text)
                .font(.uiMono)
                .foregroundStyle(Semantic.mutedForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, Space.x1)
        } else if message.role == .user {
            userTurn(message)
        } else {
            assistantRow(message.text)
        }
    }

    private func userTurn(_ message: ChatMessage) -> some View {
        VStack(alignment: .trailing, spacing: Space.x1 + Space.x1 / 2) {
            if !message.attachments.isEmpty {
                HStack {
                    Spacer(minLength: Space.x4)
                    MessageAttachments(attachments: message.attachments)
                }
            }
            let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                userBubble(text)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: Space.x4)
            Text(text)
                .font(.uiBody)
                .lineSpacing(TypeScale.bodyLead)
                .padding(.horizontal, Space.x4)
                .padding(.vertical, Space.x3)
                .foregroundStyle(Semantic.accentForeground)
                .background(
                    RoundedRectangle(cornerRadius: ChatIdle.bubbleRadius)
                        .fill(Semantic.accent)
                )
                .textSelection(.enabled)
        }
    }

    private func assistantRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.none) {
            MarkdownView(text: text)
                .padding(.vertical, Space.x3)
            Spacer(minLength: Space.x4)
        }
    }
}

private struct UpsideDown: ViewModifier {
    func body(content: Content) -> some View {
        content
            .rotationEffect(.radians(.pi))
            .scaleEffect(x: -1, y: 1, anchor: .center)
    }
}

private extension View {
    func upsideDown() -> some View {
        modifier(UpsideDown())
    }
}
