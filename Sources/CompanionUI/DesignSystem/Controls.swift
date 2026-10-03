import SwiftUI

/// 16l: every Incredible button is a pill. `standard` is its md button
/// (40 high); `pill` is the welcome button (46 high, 15 pt).
package enum AppButtonShape: Sendable {
    case standard, pill
}

package struct AppButton: View {
    let title: String
    var kind: AppButtonKind = .primary
    var shape: AppButtonShape = .standard
    var size: ButtonSize = .default
    var fullWidth = false
    var enabled: Bool = true
    /// 19-1b: an optional glyph before the label ("checkmark" on Allow).
    var systemImage: String?
    let action: () -> Void

    @State private var hovering = false
    @FocusState private var focused: Bool

    package init(
        _ title: String,
        kind: AppButtonKind = .primary,
        shape: AppButtonShape = .standard,
        size: ButtonSize = .default,
        fullWidth: Bool = false,
        enabled: Bool = true,
        systemImage: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.kind = kind
        self.shape = shape
        self.size = size
        self.fullWidth = fullWidth
        self.enabled = enabled
        self.systemImage = systemImage
        self.action = action
    }

    package var body: some View {
        Button(action: action) {
            if shape == .pill { pillLabel } else { shadcnLabel }
        }
        .buttonStyle(shape: shape, kind: kind, size: size, enabled: enabled,
                     hovering: hovering, focused: focused)
        .disabled(!enabled)
        .onHover { hovering = $0 }
        // 19-1c: a CTA under the pointer says so (Karen, feedback en vivo).
        // pointerStyle, not NSCursor push/pop: the manual stack leaks when
        // the sheet dismisses under the pointer (review 19-1c H1).
        .pointerStyle(enabled ? .link : .default)
        .focusable()
        .focused($focused)
        .accessibilityAddTraits(.isButton)
    }

    /// The window's buttons are shadcn's; the style supplies font and box.
    private var shadcnLabel: some View {
        HStack(spacing: size.gap) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .frame(maxWidth: fullWidth ? .infinity : nil)
    }

    /// The welcome sheet keeps its own Geist pill.
    private var pillLabel: some View {
        HStack(spacing: Space.x1) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(Fonts.sans(fontSize, face: .system).weight(.semibold))
            }
            Text(title)
                .font(Fonts.sans(fontSize, face: .geist).weight(.semibold))
                .tracking(Tracking.snug, at: fontSize)
                .lineLimit(1)
        }
        .frame(maxWidth: fullWidth ? .infinity : nil)
        .padding(.horizontal, ButtonMetrics.welcomePadding)
        .frame(height: ButtonMetrics.welcomeHeight)
    }

    private var fontSize: CGFloat { TypeSize.heroBody }
}

private extension View {
    @ViewBuilder
    func buttonStyle(
        shape: AppButtonShape, kind: AppButtonKind, size: ButtonSize,
        enabled: Bool, hovering: Bool, focused: Bool
    ) -> some View {
        if shape == .pill {
            buttonStyle(AppButtonStyle(
                kind: kind, enabled: enabled, hovering: hovering, focused: focused))
        } else {
            buttonStyle(.shadcn(ButtonVariant(kind: kind), size: size))
        }
    }
}

extension ButtonVariant {
    /// The app's four kinds are shadcn's variants; `neutral` is the same
    /// solid ink as primary on surfaces that must stay black and white.
    package init(kind: AppButtonKind) {
        switch kind {
        case .primary, .neutral: self = .default
        case .secondary: self = .secondary
        case .destructive: self = .destructive
        case .ghost: self = .ghost
        }
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

package struct AppField: View {
    var title: String?
    var placeholder: String
    @Binding var text: String
    var error: String? = nil
    var secure = false
    /// Neutral chrome: the focus ring in ink instead of the app accent, for
    /// surfaces that stay black-and-white (the welcome sheet).
    var neutral = false
    var onSubmit: (() -> Void)? = nil

    @FocusState private var focused: Bool
    @State private var hovering = false

    package init(
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

    package var body: some View {
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
