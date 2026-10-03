import SwiftUI

// shadcn's Button, read from its new-york-v4 source and expressed in
// Companion's own scales: every number below is a Space/TypeSize/Radius step
// and every colour a Semantic role, so a theme change moves this button too.

package enum ButtonSize: Sendable, CaseIterable {
    case xs, sm, `default`, lg

    package var height: CGFloat {
        switch self {
        case .xs: Space.x6
        case .sm: Space.x8
        case .default: Space.x9
        case .lg: Space.x10
        }
    }

    package var paddingX: CGFloat {
        switch self {
        case .xs: Space.x2
        case .sm: Space.x3
        case .default: Space.x4
        case .lg: Space.x6
        }
    }

    /// Space between a glyph and the label.
    package var gap: CGFloat {
        switch self {
        case .xs: Space.x1
        case .sm: Space.x1_5
        case .default, .lg: Space.x2
        }
    }

    package var fontSize: CGFloat {
        self == .xs ? TypeSize.caption : TypeSize.rowTitle
    }

    package var radius: CGFloat { Radius.md }
}

package enum ButtonVariant: Sendable, CaseIterable {
    case `default`, secondary, outline, ghost, destructive, link

    package func background(hovering: Bool) -> Color {
        switch self {
        case .default: hovering ? Semantic.primaryHover : Semantic.primary
        case .secondary: hovering ? Semantic.secondaryHover : Semantic.muted
        case .destructive: hovering ? Semantic.dangerHover : Semantic.destructive
        case .outline: hovering ? Semantic.hover : Semantic.surface
        case .ghost: hovering ? Semantic.hover : Color.clear
        case .link: Color.clear
        }
    }

    package var foreground: Color {
        switch self {
        case .default: Semantic.primaryForeground
        case .destructive: Semantic.destructiveForeground
        case .secondary, .outline, .ghost: Semantic.foreground
        case .link: Semantic.primary
        }
    }

    /// Only outline draws one.
    package var border: Color? {
        self == .outline ? Semantic.borderStrong : nil
    }

    package var underlinesOnHover: Bool { self == .link }
}

/// What a button looks like in one state, as numbers. Disabled wins over
/// every other state, as the `disabled:` classes do in the source.
package struct ButtonLook: Equatable, Sendable {
    package let hovering: Bool
    package let opacity: Double
    package let scale: CGFloat
    package let ring: CGFloat

    package static func resolve(
        enabled: Bool, hovering: Bool, pressed: Bool, focused: Bool, reduceMotion: Bool
    ) -> ButtonLook {
        guard enabled else {
            return ButtonLook(hovering: false, opacity: StateAlpha.disabled, scale: 1, ring: 0)
        }
        return ButtonLook(
            hovering: hovering || pressed,
            opacity: 1,
            scale: PressMotion.scale(pressed: pressed, reduceMotion: reduceMotion),
            ring: focused ? Stroke.ring : 0)
    }
}
