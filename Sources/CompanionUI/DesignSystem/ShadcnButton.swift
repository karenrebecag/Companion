import SwiftUI

/// shadcn's Button as a native ButtonStyle: behaviour, focus and
/// accessibility stay SwiftUI's; only the look is ported.
package struct ShadcnButtonStyle: ButtonStyle {
    let variant: ButtonVariant
    let size: ButtonSize

    package init(_ variant: ButtonVariant = .default, size: ButtonSize = .default) {
        self.variant = variant
        self.size = size
    }

    package func makeBody(configuration: Configuration) -> some View {
        ShadcnButtonBody(configuration: configuration, variant: variant, size: size)
    }
}

extension ButtonStyle where Self == ShadcnButtonStyle {
    package static func shadcn(
        _ variant: ButtonVariant = .default, size: ButtonSize = .default
    ) -> ShadcnButtonStyle {
        ShadcnButtonStyle(variant, size: size)
    }
}

/// The state (hover, focus) lives here because a ButtonStyle has no stored
/// state of its own.
private struct ShadcnButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let variant: ButtonVariant
    let size: ButtonSize

    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        let look = ButtonLook.resolve(
            enabled: enabled, hovering: hovering, pressed: configuration.isPressed,
            focused: focused, reduceMotion: reduceMotion)
        let shape = RoundedRectangle(cornerRadius: size.radius)
        configuration.label
            .font(Fonts.sans(size.fontSize).weight(.medium))
            .underline(variant.underlinesOnHover && look.hovering)
            .lineLimit(1)
            .padding(.horizontal, size.paddingX)
            .frame(height: size.height)
            .foregroundStyle(variant.foreground)
            .background(shape.fill(variant.background(hovering: look.hovering)))
            .overlay {
                if let border = variant.border {
                    shape.stroke(border, lineWidth: Stroke.hairline)
                }
            }
            .overlay {
                if look.ring > 0 {
                    shape.stroke(Semantic.focusRing, lineWidth: look.ring)
                        .padding(-look.ring / 2)
                }
            }
            .contentShape(shape)
            .opacity(look.opacity)
            .scaleEffect(look.scale)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil
                       : MotionCurve.animation(MotionCurve.settle, ButtonMetrics.duration),
                       value: look)
    }
}
