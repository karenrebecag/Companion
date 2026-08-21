import CompanionCore
import Foundation

// Pure functions that map voice state and audio levels to orb visual properties.
// All logic here is testable without instantiating views.

public enum OrbAppearance {
    /// Which semantic color to use based on turn state.
    nonisolated public static func baseColor(for state: TurnState) -> String {
        switch state {
        case .idle, .connecting, .listening, .thinking, .speaking:
            return "accent"
        case .error:
            return "destructive"
        }
    }

    /// Core glow intensity: how bright the pulsing center gets.
    /// Increases during active listening and thinking; dims on error.
    nonisolated public static func coreGlowIntensity(for state: TurnState) -> Double {
        switch state {
        case .idle:
            return 0.7
        case .connecting:
            return 0.5
        case .listening:
            return 1.15
        case .thinking:
            return 0.95
        case .speaking:
            return 1.25
        case .error:
            return 0.6
        }
    }

    /// Animation speed of the blob shapes. Base unit is 60 RPM-equivalent.
    /// Higher speed conveys urgency or activity; lower speed suggests rest.
    nonisolated public static func animationSpeed(for state: TurnState) -> Double {
        switch state {
        case .idle:
            return 26
        case .connecting:
            return 55
        case .listening:
            return 78
        case .thinking:
            return 145
        case .speaking:
            return 95
        case .error:
            return 14
        }
    }

    /// Scale multiplier driven by live audio level (mic or agent).
    /// Level is 0...1; maps to 1.0 (no scale) to ~1.11 (11% growth).
    /// Values outside 0...1 are clamped. Reacts quickly for tactile feedback.
    nonisolated public static func scaleFromLevel(_ level: Double) -> Double {
        let clamped = max(0, min(1, level))
        return 1 + clamped * 0.11
    }

    /// Opacity of the orb. Idle state dims it subtly; all other states are full.
    nonisolated public static func opacity(for state: TurnState) -> Double {
        state == .idle ? 0.82 : 1
    }

    /// Animation speed adjusted for accessibility: disabled if reduce-motion is on.
    nonisolated public static func effectiveAnimationSpeed(
        for state: TurnState,
        reduceMotion: Bool
    ) -> Double {
        reduceMotion ? 0 : animationSpeed(for: state)
    }

    /// Whether the outer shimmer shell should animate.
    /// Only animates during listening and thinking; always off if reduce-motion.
    nonisolated public static func shouldAnimateShell(
        for state: TurnState,
        reduceMotion: Bool
    ) -> Bool {
        if reduceMotion { return false }
        switch state {
        case .listening, .thinking:
            return true
        case .idle, .connecting, .speaking, .error:
            return false
        }
    }
}
