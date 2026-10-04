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
    /// Arc button `loading`: the spinner takes the glyph's place while the
    /// action runs. The caller also disables the button.
    var busy = false
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
        busy: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.kind = kind
        self.shape = shape
        self.size = size
        self.fullWidth = fullWidth
        self.enabled = enabled
        self.systemImage = systemImage
        self.busy = busy
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
            if busy {
                LoaderArc()
            } else if let systemImage {
                Image(systemName: systemImage)
            }
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
    /// Arc input's helper row: what the value should be, before anything is wrong.
    var description: String? = nil
    var error: String? = nil
    var secure = false
    /// Arc input's readOnly: the value cannot change under a save in flight.
    var readOnly = false
    /// How the helper and error rows enter; only seen when the caller animates them.
    var messageTransition: AnyTransition = .opacity
    /// Neutral chrome: the focus ring in ink instead of the app accent, for
    /// surfaces that stay black-and-white (the welcome sheet).
    var neutral = false
    /// Opt-in Arc input reading: the title names the field and the helper or
    /// error is its hint. Off, the field reads as it always has, so callers
    /// that did not ask (Settings, Welcome, search) are not changed by it.
    var messagesInHint = false
    var onSubmit: (() -> Void)? = nil

    @FocusState private var focused: Bool
    @State private var hovering = false

    package init(
        title: String? = nil,
        placeholder: String,
        text: Binding<String>,
        description: String? = nil,
        error: String? = nil,
        secure: Bool = false,
        readOnly: Bool = false,
        messageTransition: AnyTransition = .opacity,
        neutral: Bool = false,
        messagesInHint: Bool = false,
        onSubmit: (() -> Void)? = nil
    ) {
        self.title = title
        self.placeholder = placeholder
        self._text = text
        self.description = description
        self.error = error
        self.secure = secure
        self.readOnly = readOnly
        self.messageTransition = messageTransition
        self.neutral = neutral
        self.messagesInHint = messagesInHint
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
            .foregroundStyle(readOnly ? Semantic.mutedForeground : Semantic.foreground)
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
            // Not .disabled: that greys the value out and drops it from
            // VoiceOver's reading. The value stays readable; only input stops.
            .allowsHitTesting(!readOnly)
            .onChange(of: readOnly) { _, locked in
                if locked { focused = false }
            }
            .modifier(FieldAccessibilityModifier(spec: accessibilitySpec))
            if let error, !error.isEmpty {
                Text(error)
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(messagesInHint)
                    .transition(messageTransition)
            } else if let description, !description.isEmpty {
                Text(description)
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(messagesInHint)
                    .transition(messageTransition)
            }
        }
    }

    /// SwiftUI has no aria-invalid; the hint opens with the word instead.
    package static func hint(description: String?, error: String?) -> String {
        if let error, !error.isEmpty { return String(format: Localized.string("field.invalid"), error) }
        return description ?? ""
    }

    /// The visible title, then the placeholder, then a generic name: never empty.
    package static func label(title: String?, placeholder: String) -> String {
        if let title, !title.isEmpty { return title }
        return placeholder.isEmpty ? Localized.string("field.unnamed") : placeholder
    }

    /// nil leaves SwiftUI's own reading untouched.
    package static func accessibility(
        messagesInHint: Bool, title: String?, placeholder: String, description: String?, error: String?
    ) -> FieldAccessibility? {
        guard messagesInHint else { return nil }
        return FieldAccessibility(label: label(title: title, placeholder: placeholder),
                                  hint: hint(description: description, error: error))
    }

    package var accessibilitySpec: FieldAccessibility? {
        Self.accessibility(messagesInHint: messagesInHint, title: title, placeholder: placeholder,
                           description: description, error: error)
    }

    private func fieldStroke(_ look: ControlLook) -> Color {
        switch look.stroke {
        case .destructive: Semantic.destructive
        case .border: Semantic.border
        case .none: Color.clear
        }
    }
}

package struct FieldAccessibility: Equatable, Sendable {
    package let label: String
    package let hint: String
}

private struct FieldAccessibilityModifier: ViewModifier {
    let spec: FieldAccessibility?

    func body(content: Content) -> some View {
        if let spec {
            content
                .accessibilityLabel(spec.label)
                .accessibilityHint(spec.hint)
        } else {
            content
        }
    }
}
