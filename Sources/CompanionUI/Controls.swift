import SwiftUI

/// 16l: every Incredible button is a pill. `standard` is its md button
/// (40 high); `pill` is the welcome button (46 high, 15 pt).
public enum AppButtonShape: Sendable {
    case standard, pill
}

public struct AppButton: View {
    let title: String
    var kind: AppButtonKind = .primary
    var shape: AppButtonShape = .standard
    var fullWidth = false
    var enabled: Bool = true
    /// 19-1b: an optional glyph before the label ("checkmark" on Allow).
    var systemImage: String?
    let action: () -> Void

    @State private var hovering = false
    @FocusState private var focused: Bool

    public init(
        _ title: String,
        kind: AppButtonKind = .primary,
        shape: AppButtonShape = .standard,
        fullWidth: Bool = false,
        enabled: Bool = true,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.kind = kind
        self.shape = shape
        self.fullWidth = fullWidth
        self.enabled = enabled
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            // The welcome button speaks Geist like the rest of that sheet.
            HStack(spacing: Space.x1) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(Fonts.sans(fontSize, face: .system).weight(.semibold))
                }
                Text(title)
                    .font(Fonts.sans(fontSize, face: shape == .pill ? .geist : .system).weight(.semibold))
                    .tracking(shape == .pill ? Tracking.snug : 0, at: fontSize)
                    .lineLimit(1)
            }
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, paddingX)
            .frame(height: height)
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

    private var isWash: Bool { kind == .secondary || kind == .ghost }

    private var fontSize: CGFloat {
        if shape == .pill { return TypeSize.heroBody }
        return isWash ? TypeSize.body : TypeSize.rowTitle
    }

    private var paddingX: CGFloat {
        if shape == .pill { return ButtonMetrics.welcomePadding }
        return isWash ? ButtonMetrics.ghostPadding : ButtonMetrics.padding
    }

    private var height: CGFloat {
        shape == .pill ? ButtonMetrics.welcomeHeight : ButtonMetrics.height
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
            .foregroundStyle(ink(look, state))
            .background(Capsule().fill(fill(look, state)))
            .contentShape(Capsule())
            .overlay {
                if look.focusRing > 0 {
                    // Incredible outlines focus in the button's own ink,
                    // 2 pt out from the edge.
                    Capsule()
                        .stroke(Semantic.foreground, lineWidth: look.focusRing)
                        .padding(-Stroke.medium)
                }
            }
            .opacity(look.opacity)
            .scaleEffect(look.scale)
            .animation(MotionCurve.animation(MotionCurve.settle, ButtonMetrics.duration),
                       value: look.scale)
    }

    private func fill(_ look: ControlLook, _ state: ControlState) -> Color {
        let hot = state == .hover || state == .pressed
        switch look.fill {
        case .destructive: return hot ? Semantic.dangerHover : Semantic.destructive
        case .surface: return Semantic.surface
        case .clear: return hot ? Semantic.hoverSubtle : Color.clear
        case .ink: return Semantic.primary
        case .wash: return Semantic.wash
        }
    }

    private func ink(_ look: ControlLook, _ state: ControlState) -> Color {
        switch look.ink {
        case .onDestructive: return Semantic.destructiveForeground
        case .foreground: return Semantic.foreground
        case .onInk: return Semantic.primaryForeground
        case .muted:
            // Ghost: secondary grey that turns primary under the pointer.
            return state == .hover ? Semantic.foreground : Semantic.mutedForeground
        }
    }
}

public struct AppField: View {
    var title: String?
    var placeholder: String
    @Binding var text: String
    var error: String? = nil
    var secure = false
    /// Neutral chrome: the focus ring in ink instead of the app accent, for
    /// surfaces that stay black-and-white (the onboarding sheet).
    var neutral = false
    var onSubmit: (() -> Void)? = nil

    @FocusState private var focused: Bool
    @State private var hovering = false

    public init(
        title: String? = nil,
        placeholder: String,
        text: Binding<String>,
        error: String? = nil,
        secure: Bool = false,
        neutral: Bool = false,
        onSubmit: (() -> Void)? = nil
    ) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
        self.error = error
        self.secure = secure
        self.neutral = neutral
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
                        .stroke(neutral ? Semantic.foreground : Semantic.accent,
                                lineWidth: look.focusRing)
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
