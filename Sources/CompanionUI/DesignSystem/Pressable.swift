import SwiftUI

/// Numbers the views apply. Extracted so press/hover stay testable without a window.
package enum PressMotion {
    package static let pressedScale: CGFloat = 0.98
    package static let pressedOpacity: CGFloat = 0.85
    package static let chipScale: CGFloat = 1.04
    package static let iconScale: CGFloat = 1.05
    package static let restFillOpacity: Double = 0.55
    package static let restStrokeOpacity: Double = 0.5

    package static func scale(pressed: Bool, reduceMotion: Bool) -> CGFloat {
        pressed && !reduceMotion ? pressedScale : 1
    }

    package static func opacity(pressed: Bool) -> CGFloat {
        pressed ? pressedOpacity : 1
    }

    package static func hoverScale(
        _ hovering: Bool, reduceMotion: Bool, icon: Bool
    ) -> CGFloat {
        guard hovering, !reduceMotion else { return 1 }
        return icon ? iconScale : chipScale
    }

    package static func fillOpacity(hovering: Bool) -> Double {
        hovering ? 1 : restFillOpacity
    }

    package static func strokeOpacity(hovering: Bool) -> Double {
        hovering ? 1 : restStrokeOpacity
    }
}

package struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    package init() {}

    package func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                PressMotion.scale(
                    pressed: configuration.isPressed,
                    reduceMotion: reduceMotion))
            .opacity(PressMotion.opacity(pressed: configuration.isPressed))
            .animation(
                reduceMotion ? nil : .springPress,
                value: configuration.isPressed)
    }
}

package struct HoverChip: ViewModifier {
    var hovering: Binding<Bool>?
    var icon = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var localHover = false

    package func body(content: Content) -> some View {
        let over = hovering?.wrappedValue ?? localHover
        content
            .background {
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(Semantic.surface.opacity(
                        PressMotion.fillOpacity(hovering: over)))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.md)
                            .fill(over ? Semantic.hover : Color.clear)
                    }
                    .allowsHitTesting(false)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(Semantic.border, lineWidth: Stroke.hairline)
                    .opacity(PressMotion.strokeOpacity(hovering: over))
                    .allowsHitTesting(false)
            }
            .scaleEffect(
                PressMotion.hoverScale(over, reduceMotion: reduceMotion, icon: icon))
            .animation(reduceMotion ? nil : .springHover, value: over)
            .onHover { value in
                localHover = value
                hovering?.wrappedValue = value
            }
    }
}

extension View {
    package func hoverChip(
        hovering: Binding<Bool>? = nil, icon: Bool = false
    ) -> some View {
        modifier(HoverChip(hovering: hovering, icon: icon))
    }
}
