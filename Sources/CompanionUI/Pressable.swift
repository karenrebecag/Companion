import SwiftUI

/// Numbers the views apply. Extracted so press/hover stay testable without a window.
public enum PressMotion {
    public static let pressedScale: CGFloat = 0.98
    public static let pressedOpacity: CGFloat = 0.85
    public static let chipScale: CGFloat = 1.04
    public static let iconScale: CGFloat = 1.05
    public static let restFillOpacity: Double = 0.55
    public static let restStrokeOpacity: Double = 0.5

    public static func scale(pressed: Bool, reduceMotion: Bool) -> CGFloat {
        pressed && !reduceMotion ? pressedScale : 1
    }

    public static func opacity(pressed: Bool) -> CGFloat {
        pressed ? pressedOpacity : 1
    }

    public static func hoverScale(
        _ hovering: Bool, reduceMotion: Bool, icon: Bool
    ) -> CGFloat {
        guard hovering, !reduceMotion else { return 1 }
        return icon ? iconScale : chipScale
    }

    public static func fillOpacity(hovering: Bool) -> Double {
        hovering ? 1 : restFillOpacity
    }

    public static func strokeOpacity(hovering: Bool) -> Double {
        hovering ? 1 : restStrokeOpacity
    }
}

public struct PressableStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
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

public struct HoverChip: ViewModifier {
    var hovering: Binding<Bool>?
    var icon = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var localHover = false

    public func body(content: Content) -> some View {
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
    public func hoverChip(
        hovering: Binding<Bool>? = nil, icon: Bool = false
    ) -> some View {
        modifier(HoverChip(hovering: hovering, icon: icon))
    }
}

/// Header chrome icon. SF until 05/08 ask for a house glyph.
public struct HoverIconButton: View {
    var symbol: String = ""
    var icon: CompanionIcon? = nil
    let help: String
    let action: () -> Void
    @State private var hovering = false

    public init(symbol: String, help: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.action = action
    }

    public init(icon: CompanionIcon, help: String, action: @escaping () -> Void) {
        self.icon = icon
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Group {
                if let icon {
                    IconGlyph(icon: icon, size: 14)
                } else {
                    Image(systemName: symbol)
                        .font(.uiCaption)
                }
            }
            .foregroundStyle(
                hovering ? Semantic.foreground : Semantic.mutedForeground)
            .frame(width: IconSize.hero, height: IconSize.hero)
            .contentShape(Rectangle())
            .hoverChip(hovering: $hovering, icon: true)
            .accessibilityHidden(true)
        }
        .buttonStyle(PressableStyle())
        .help(help)
        .accessibilityLabel(help)
    }
}
