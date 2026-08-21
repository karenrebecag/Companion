import SwiftUI

public struct AppButton: View {
    let title: String
    var kind: AppButtonKind = .primary
    var enabled: Bool = true
    let action: () -> Void

    @State private var hovering = false
    @FocusState private var focused: Bool

    public init(
        _ title: String,
        kind: AppButtonKind = .primary,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.kind = kind
        self.enabled = enabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.uiAction)
                .padding(.horizontal, Space.x4)
                .padding(.vertical, Space.x2)
        }
        .buttonStyle(
            AppButtonStyle(
                kind: kind, enabled: enabled,
                hovering: hovering, focused: focused))
        .disabled(!enabled)
        .onHover { hovering = $0 }
        .focusable()
        .focused($focused)
        .accessibilityAddTraits(.isButton)
    }
}

private struct AppButtonStyle: ButtonStyle {
    let kind: AppButtonKind
    let enabled: Bool
    var hovering: Bool
    var focused: Bool

    func makeBody(configuration: Configuration) -> some View {
        let state = ControlState.resolve(
            enabled: enabled,
            hovering: hovering,
            pressed: configuration.isPressed,
            focused: focused)
        let look = ControlLook.button(kind, state)
        configuration.label
            .foregroundStyle(ink(look))
            .background(fill(look))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(stroke(look), lineWidth: Stroke.hairline)
            }
            .overlay {
                if look.focusRing > 0 {
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(Semantic.accent, lineWidth: look.focusRing)
                }
            }
            .elevation(look.elevation)
            .opacity(look.opacity)
            .scaleEffect(state == .pressed ? 0.98 : 1)
            .animation(.springPress, value: configuration.isPressed)
    }

    private func fill(_ look: ControlLook) -> Color {
        switch look.fill {
        case .accent: Semantic.accent
        case .destructive: Semantic.destructive
        case .surface: Semantic.surface
        case .clear: Color.clear
        }
    }

    private func ink(_ look: ControlLook) -> Color {
        switch look.ink {
        case .onAccent: Semantic.accentForeground
        case .onDestructive: Semantic.destructiveForeground
        case .foreground: Semantic.foreground
        case .accentText: Semantic.accentText
        }
    }

    private func stroke(_ look: ControlLook) -> Color {
        switch look.stroke {
        case .none: Color.clear
        case .border: Semantic.border
        case .destructive: Semantic.destructive
        }
    }
}

public struct AppField: View {
    var title: String?
    var placeholder: String
    @Binding var text: String
    var error: String? = nil
    var secure = false
    var onSubmit: (() -> Void)? = nil

    @FocusState private var focused: Bool
    @State private var hovering = false

    public init(
        title: String? = nil,
        placeholder: String,
        text: Binding<String>,
        error: String? = nil,
        secure: Bool = false,
        onSubmit: (() -> Void)? = nil
    ) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
        self.error = error
        self.secure = secure
        self.onSubmit = onSubmit
    }

    public var body: some View {
        let state = ControlState.resolve(
            enabled: true, hovering: hovering,
            pressed: false, focused: focused)
        let look = ControlLook.field(state, error: error != nil)
        VStack(alignment: .leading, spacing: Space.x2) {
            if let title {
                Text(title)
                    .font(.uiLabel)
                    .foregroundStyle(Semantic.foreground)
            }
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .textFieldStyle(.plain)
            .font(.uiBody)
            .foregroundStyle(Semantic.foreground)
            .padding(.horizontal, Space.x3)
            .padding(.vertical, Space.x2)
            .background(Semantic.surface)
            .focused($focused)
            .onSubmit { onSubmit?() }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(fieldStroke(look), lineWidth: Stroke.hairline)
            }
            .overlay {
                if look.focusRing > 0 {
                    RoundedRectangle(cornerRadius: Radius.md)
                        .stroke(Semantic.accent, lineWidth: look.focusRing)
                }
            }
            .onHover { hovering = $0 }
            if let error, !error.isEmpty {
                Text(error)
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func fieldStroke(_ look: ControlLook) -> Color {
        switch look.stroke {
        case .destructive: Semantic.destructive
        case .border: Semantic.border
        case .none: Color.clear
        }
    }
}
