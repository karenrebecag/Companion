import CompanionCore
import Foundation

// Arc's voice-orb (uiarc.dev, Pro) as pure numbers: nine shape values per
// state, each on its own lightly damped spring, and a level meter with a fast
// attack and a slow release. The view only draws what this computes.

package enum VoiceOrbState: Hashable, Sendable {
    case idle, listening, thinking, speaking

    package init(_ turn: TurnState) {
        switch turn {
        case .listening: self = .listening
        case .speaking: self = .speaking
        case .thinking, .connecting: self = .thinking
        case .idle, .error: self = .idle
        }
    }
}

extension VoiceOrbState {
    /// Below this the voice speaking back is silence, not speech.
    package static let speechFloor = 0.02

    /// The composer's mark speaks with the voice coming back and never with
    /// the mic: the user's own voice must not look like the assistant's.
    package static func composer(levels: VoiceLevels) -> VoiceOrbState {
        let agent = levels.agent.isFinite ? levels.agent : 0
        return agent > speechFloor ? .speaking : .idle
    }
}

package struct VoiceOrbParams: Equatable, Sendable {
    package var breath: Double
    package var wobble: Double
    package var speed: Double
    package var swirl: Double
    package var gain: Double
    package var tint: Double
    package var ring: Double
    package var grow: Double
    package var orbit: Double

    package static func target(_ state: VoiceOrbState) -> VoiceOrbParams {
        switch state {
        case .idle:
            VoiceOrbParams(breath: 0.022, wobble: 0.02, speed: 0.5, swirl: 0.16, gain: 0, tint: 0.42,
                           ring: 0, grow: 0, orbit: 0.2)
        case .listening:
            VoiceOrbParams(breath: 0.012, wobble: 0.03, speed: 1.1, swirl: 0.3, gain: 0.16, tint: 0.72,
                           ring: 1, grow: 0.03, orbit: 0.24)
        case .thinking:
            VoiceOrbParams(breath: 0.008, wobble: 0.075, speed: 0.8, swirl: 1.7, gain: 0, tint: 0.6,
                           ring: 0, grow: -0.08, orbit: 0.36)
        case .speaking:
            VoiceOrbParams(breath: 0.008, wobble: 0.035, speed: 1.35, swirl: 0.4, gain: 0.14, tint: 0.92,
                           ring: 0, grow: 0.02, orbit: 0.2)
        }
    }

    fileprivate static let keys: [WritableKeyPath<VoiceOrbParams, Double>] = [
        \.breath, \.wobble, \.speed, \.swirl, \.gain, \.tint, \.ring, \.grow, \.orbit,
    ]

    fileprivate static let zero = VoiceOrbParams(breath: 0, wobble: 0, speed: 0, swirl: 0, gain: 0, tint: 0,
                                                 ring: 0, grow: 0, orbit: 0)
}

/// The orb's running state: where each value is, how fast it moves, the
/// two clocks the shape turns on and the level it shows.
package struct VoiceOrbSimulation: Sendable {
    package private(set) var current: VoiceOrbParams
    private var velocity = VoiceOrbParams.zero
    package private(set) var phase: Double = 0
    package private(set) var swirlPhase: Double = 0
    package var level: Double = 0

    /// Arc's per-value spring: stiffness 70, damping 15.
    private static let stiffness = 70.0
    private static let damping = 15.0
    /// A frame longer than this (a stall, a background tab) is treated as this.
    package static let maxFrame = 0.05

    package init(state: VoiceOrbState) { current = .target(state) }

    package mutating func step(dt raw: Double, state: VoiceOrbState, input: Double, output: Double) {
        let dt = min(Self.maxFrame, max(0, raw.isFinite ? raw : 0))
        let target = VoiceOrbParams.target(state)
        for key in VoiceOrbParams.keys {
            let force = Self.stiffness * (target[keyPath: key] - current[keyPath: key])
                - Self.damping * velocity[keyPath: key]
            velocity[keyPath: key] += force * dt
            current[keyPath: key] += velocity[keyPath: key] * dt
        }
        phase += dt * current.speed
        swirlPhase += dt * current.swirl
        let goal: Double = switch state {
        case .listening: Self.clamp(input)
        case .speaking: Self.clamp(output)
        case .idle, .thinking: 0
        }
        // Fast attack, slow release, the way a level meter reads.
        let rate = goal > level ? 22.0 : 6.0
        level += (goal - level) * (1 - exp(-dt * rate))
    }

    private static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}

package enum VoiceOrbGeometry {
    package static let points = 96
    /// The body's radius as a share of the canvas side; the ripples spread past it.
    package static let bodyShare = 0.3

    /// The blob's edge at one angle: a slow wobble plus a voice-driven ripple.
    package static func radius(at a: Double, base: Double, params p: VoiceOrbParams,
                               phase ph: Double, swirl sw: Double, level: Double) -> Double {
        let wobble = p.wobble * (0.62 * sin(2 * a + sw * 1.4 + ph * 0.6) + 0.3 * sin(3 * a - ph * 1.3)
            + 0.16 * sin(5 * a + ph * 2.1))
        let voice = level * p.gain * (0.34 * sin(4 * a + ph * 3.1) + 0.2 * sin(7 * a - ph * 2.4))
        return base * (1 + wobble + voice)
    }

    /// The body's base radius this frame: it breathes, grows with its state and swells with the level.
    package static func bodyRadius(side: Double, params p: VoiceOrbParams, phase ph: Double, level: Double) -> Double {
        side * bodyShare * (1 + p.grow + p.breath * sin(ph * 1.6) + level * p.gain)
    }

    /// Dark surfaces need the tint lifted into a glow (Arc's `glow`), keeping its hue.
    package static func glow(r: Double, g: Double, b: Double) -> (r: Double, g: Double, b: Double) {
        let gray = (r + g + b) / 3
        func lift(_ v: Double) -> Double { min(1, max(0, (190 + (v - gray) * 255 * 3) / 255)) }
        return (lift(r), lift(g), lift(b))
    }
}
