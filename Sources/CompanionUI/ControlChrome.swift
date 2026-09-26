import SwiftUI

public enum ControlState: Sendable, CaseIterable {
    case normal, hover, pressed, disabled, focused

    public static func resolve(
        enabled: Bool, hovering: Bool, pressed: Bool, focused: Bool
    ) -> ControlState {
        if !enabled { return .disabled }
        if pressed { return .pressed }
        if hovering { return .hover }
        if focused { return .focused }
        return .normal
    }
}

public enum AppButtonKind: Sendable, CaseIterable {
    case primary, secondary, destructive, ghost
    /// Solid ink button: black on light, white on dark. For surfaces that
    /// must stay clean of the app accent (the onboarding hero sheet).
    case neutral
}

public enum ControlFill: Sendable, Equatable {
    /// `wash` is Incredible's ghost fill: black 5 % over the surface.
    case destructive, surface, clear, ink, wash
}

public enum ControlInk: Sendable, Equatable {
    case onDestructive, foreground, onInk, muted
}

public enum ControlStroke: Sendable, Equatable {
    case none, border, destructive
}

public struct ControlLook: Equatable, Sendable {
    public let fill: ControlFill
    public let ink: ControlInk
    public let stroke: ControlStroke
    public let elevation: Elevation
    public let focusRing: CGFloat
    public let opacity: Double
    /// Incredible's buttons grow on hover instead of lifting a shadow.
    public var scale: CGFloat = 1

    public static func button(
        _ kind: AppButtonKind, _ state: ControlState
    ) -> ControlLook {
        // 16l: Incredible fades the same look to 50 % and never shadows a
        // button; the solid and wash kinds grow 3 % under the pointer.
        let grows = state == .hover && kind != .ghost && kind != .destructive
        return ControlLook(
            fill: fill(kind),
            ink: ink(kind),
            stroke: stroke(kind),
            elevation: .rest,
            focusRing: state == .disabled ? 0 : ring(state),
            opacity: state == .disabled ? StateAlpha.disabled : 1,
            scale: grows ? ButtonMetrics.hoverScale : 1)
    }

    public static func field(
        _ state: ControlState, error: Bool
    ) -> ControlLook {
        ControlLook(
            fill: .surface,
            ink: .foreground,
            stroke: error ? .destructive : .border,
            elevation: .rest,
            focusRing: ring(state),
            opacity: state == .disabled ? 0.4 : 1)
    }

    private static func fill(_ kind: AppButtonKind) -> ControlFill {
        switch kind {
        case .primary, .neutral: .ink
        case .secondary: .wash
        case .destructive: .destructive
        case .ghost: .clear
        }
    }

    private static func ink(_ kind: AppButtonKind) -> ControlInk {
        switch kind {
        case .primary, .neutral: .onInk
        case .secondary: .foreground
        case .destructive: .onDestructive
        case .ghost: .muted
        }
    }

    private static func stroke(_ kind: AppButtonKind) -> ControlStroke {
        switch kind {
        case .primary, .secondary, .destructive, .ghost, .neutral: .none
        }
    }

    private static func ring(_ state: ControlState) -> CGFloat {
        state == .focused ? Stroke.medium : 0
    }
}
