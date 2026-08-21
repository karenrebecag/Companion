import CompanionCore
import Foundation
import SwiftUI

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

    /// Opacity of the rotating glow overlay. Active turns read brighter.
    nonisolated public static func glowOpacity(for state: TurnState) -> Double {
        switch state {
        case .idle: 0.35
        case .connecting: 0.45
        case .listening: 0.75
        case .thinking: 0.65
        case .speaking: 0.85
        case .error: 0.25
        }
    }

    /// SpriteKit birth count. Idle/connecting/error have none, matching VoiceState.orb.
    nonisolated public static func particleCount(
        for state: TurnState, reduceMotion: Bool
    ) -> Int {
        if reduceMotion { return 0 }
        switch state {
        case .idle, .connecting, .error: return 0
        case .listening: return 14
        case .thinking: return 16
        case .speaking: return 12
        }
    }

    public static func configuration(
        for state: TurnState,
        accent: Color,
        reduceMotion: Bool
    ) -> OrbConfiguration {
        let speed = effectiveAnimationSpeed(for: state, reduceMotion: reduceMotion)
        let particles = particleCount(for: state, reduceMotion: reduceMotion) > 0
        let ink: [Color]
        if state == .error {
            ink = [
                Color(nsColor: NSColor.fromHex("E8A317")),
                Color(nsColor: NSColor.fromHex("8A5A2B")),
                Color(nsColor: NSColor.fromHex("E8A317")),
            ]
        } else {
            ink = [accent, accent.opacity(0.82), Color.white.opacity(0.92)]
        }
        return OrbConfiguration(
            backgroundColors: ink,
            coreGlowIntensity: coreGlowIntensity(for: state),
            showParticles: particles,
            speed: speed)
    }

    /// Press shrinks the orb; spring lives on the button style, not here.
    nonisolated public static func pressScale(_ pressed: Bool) -> Double {
        pressed ? 0.92 : 1
    }
}
