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
}

public enum ControlFill: Sendable, Equatable {
    case accent, destructive, surface, clear
}

public enum ControlInk: Sendable, Equatable {
    case onAccent, onDestructive, foreground, accentText
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

    public static func button(
        _ kind: AppButtonKind, _ state: ControlState
    ) -> ControlLook {
        ControlLook(
            fill: fill(kind),
            ink: ink(kind),
            stroke: stroke(kind),
            elevation: state == .hover ? .hover : .rest,
            focusRing: ring(state),
            opacity: state == .disabled ? 0.4 : 1)
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
        case .primary: .accent
        case .secondary: .surface
        case .destructive: .destructive
        case .ghost: .clear
        }
    }

    private static func ink(_ kind: AppButtonKind) -> ControlInk {
        switch kind {
        case .primary: .onAccent
        case .secondary: .foreground
        case .destructive: .onDestructive
        case .ghost: .accentText
        }
    }

    private static func stroke(_ kind: AppButtonKind) -> ControlStroke {
        switch kind {
        case .secondary: .border
        case .ghost: .none
        case .primary, .destructive: .none
        }
    }

    private static func ring(_ state: ControlState) -> CGFloat {
        state == .focused ? Stroke.medium : 0
    }
}
