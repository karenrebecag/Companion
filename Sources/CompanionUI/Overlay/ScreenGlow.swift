import CompanionCore
import Foundation
import SwiftUI

// Incredible 0.2.36's screen glow as it ships: the "gl-waves" shader (the reference
// local), ported to Metal in ScreenGlowShader. These are its numbers and its clock.

package enum ScreenGlow {
    /// The palette the shader sweeps around the frame; the pointer trail borrows it.
    package static let colors = [Swatch("1C69F0"), Swatch("0AB4AF"), Swatch("8C46E6"), Swatch("1496DC")]

    package enum Mode: Equatable, Sendable {
        case off, listening, waiting
    }

    /// The glow belongs to the voice alone, as in Incredible: an agent acting through
    /// the bridge does not light it (Karen's UX decision, 2026-10-03).
    package static func mode(_ projection: SessionProjection, enabled: Bool, previous: Mode) -> Mode {
        mode(projection.kind, enabled: enabled, previous: previous)
    }

    /// Speaking is the answer arriving: the edges have done their job. Waiting only
    /// dims a glow already lit, as in Incredible: a turn that starts by processing
    /// never lights it.
    package static func mode(_ kind: SessionKind, enabled: Bool, previous: Mode) -> Mode {
        guard enabled else { return .off }
        switch kind {
        case .listening: return .listening
        case .processing(.pending), .processing(.thinking),
             .processing(.toolExecuting), .processing(.subAgentRunning):
            return previous != .off ? .waiting : .off
        case .idle, .hover, .processing(.speaking), .processing(.completed): return .off
        }
    }

    /// Alpha at full fill and no dimming.
    package static let ceiling = 0.5
    /// Milliseconds for the fill to rise from empty and to fall from full: quick in, soft out.
    package static let fillIn = 260.0
    package static let fillOut = 900.0
    /// Waiting halves the light, approached at one `dimRate` per millisecond step.
    package static let waitingDim = 0.5
    package static let dimRate = 250.0
    /// A long frame (a stall, a sleep) counts as this many milliseconds, so nothing jumps.
    package static let frameCap = 100.0

    /// Fill and dim of one frame. Incredible steps them per frame, not as tweens, so a
    /// change of mode mid-fade continues from where the light is.
    package struct Envelope: Equatable, Sendable {
        package let fill: Double
        package let dim: Double

        package init(fill: Double, dim: Double) {
            self.fill = fill
            self.dim = dim
        }

        package static func start(_ mode: Mode) -> Envelope {
            Envelope(fill: mode == .off ? 0 : 1, dim: 1)
        }

        package func step(_ mode: Mode, ms: Double) -> Envelope {
            let dt = min(ScreenGlow.frameCap, max(ms, 0))
            let goal = mode == .off ? 0.0 : 1.0
            let rate = dt / (mode == .off ? ScreenGlow.fillOut : ScreenGlow.fillIn)
            let nextFill = fill < goal ? min(goal, fill + rate) : max(goal, fill - rate)
            let dimGoal = mode == .waiting ? ScreenGlow.waitingDim : 1
            return Envelope(fill: nextFill, dim: dim + (dimGoal - dim) * min(1, dt / ScreenGlow.dimRate))
        }

        package var alpha: Double { fill * dim * ScreenGlow.ceiling }

        /// Frames keep coming while the light moves in, stays or drains out.
        package func drawing(_ mode: Mode) -> Bool { fill > 0 || mode != .off }
    }

    /// Canvas pixels inward from each edge before the waves ruffle it.
    package static let reach: CGFloat = 120
    /// Incredible draws its canvas at no more than 1.25 pixels per point: the waves'
    /// frequencies are in those pixels, so the density is part of the look.
    package static let densityCap: CGFloat = 1.25
    /// Incredible's noise seed is fixed; only the palette phase changes per activation.
    package static let seed: Float = 9

    package static func density(backing: CGFloat) -> CGFloat { min(backing, densityCap) }

    /// A whole degree, as a fraction of a turn: where the palette starts this time.
    package static func phase(random: Double) -> Double { (random * 360).rounded() / 360 }

    /// The whole glow shrinks a hair while waiting, over the container's settle.
    package static let waitingScale: CGFloat = 0.996
    package static let settle = 0.7
    /// Turning off, the container holds its opacity this long, then fades over `settle`.
    package static let leaveDelay = 0.8

    /// How long the renderer keeps running once off: until the container is gone and the
    /// fill has drained. Reduce motion hides the container at once, but the fill still
    /// drains, so a quick relight starts from where Incredible's would.
    package static func linger(reduceMotion: Bool) -> Double {
        reduceMotion ? fillOut / 1000 : max(fillOut / 1000, leaveDelay + settle)
    }

    /// Turning on is instant: the shader's fill carries the arrival.
    package static func opacityAnimation(off: Bool, reduceMotion: Bool) -> Animation? {
        guard off, !reduceMotion else { return nil }
        return MotionCurve.animation(MotionCurve.settle, settle).delay(leaveDelay)
    }

    /// The shrink while waiting animates only while lit; going off it snaps back.
    package static func scaleAnimation(off: Bool, reduceMotion: Bool) -> Animation? {
        off || reduceMotion ? nil : MotionCurve.animation(MotionCurve.settle, settle)
    }

    /// The ring that leaves the notch when the glow lights.
    package enum Ripple {
        package static let duration = 0.85
        package static let curve: [Double] = [0.25, 0.55, 0.35, 1]
        package static let fromScale: CGFloat = 0.05
        package static let toScale: CGFloat = 2.3
        package static let peak = 0.55
        /// Fraction of the run at which the ring is brightest.
        package static let peakAt = 0.3
        /// Points of blur over the rings.
        package static let blur: CGFloat = 10

        package struct Stop {
            package let swatch: Swatch
            package let alpha: Double
            /// Fraction of the distance from the notch to the farthest screen corner.
            package let at: Double
        }

        /// Two soft rings, outer and inner; each fades in and out of its own hue, since
        /// CSS blends `transparent` premultiplied and never through grey.
        package static let outer = [
            Stop(swatch: Swatch("784CD6"), alpha: 0, at: 0.26), Stop(swatch: Swatch("784CD6"), alpha: 0.2, at: 0.33),
            Stop(swatch: Swatch("246EEB"), alpha: 0.3, at: 0.39), Stop(swatch: Swatch("12A0C4"), alpha: 0.28, at: 0.45),
            Stop(swatch: Swatch("12A0C4"), alpha: 0, at: 0.54),
        ]
        package static let inner = [
            Stop(swatch: Swatch("12A0C4"), alpha: 0, at: 0.12), Stop(swatch: Swatch("12A0C4"), alpha: 0.14, at: 0.2),
            Stop(swatch: Swatch("12A0C4"), alpha: 0, at: 0.28),
        ]

        /// CSS's `circle at 50% 100%` reaches the farthest corner; turned 180 degrees,
        /// the centre is the top middle.
        package static func radius(in size: CGSize) -> CGFloat {
            (pow(size.width / 2, 2) + pow(size.height, 2)).squareRoot()
        }

        /// CSS applies the timing function per keyframe interval: the scale runs one
        /// interval, the opacity two (up to the peak, then down).
        package static func state(at seconds: Double) -> (scale: CGFloat, opacity: Double) {
            let x = min(max(seconds / duration, 0), 1)
            let scale = fromScale + (toScale - fromScale) * CGFloat(MotionCurve.value(curve, at: x))
            let opacity = x < peakAt
                ? peak * MotionCurve.value(curve, at: x / peakAt)
                : peak * (1 - MotionCurve.value(curve, at: (x - peakAt) / (1 - peakAt)))
            return (scale, opacity)
        }
    }

}

/// Incredible's `screen_glow_enabled`: on unless the user turned it off.
package enum ScreenGlowPreference {
    static let key = "companion.screenGlow.enabled"

    package static func enabled(in store: UserDefaults = .standard) -> Bool {
        store.object(forKey: key) == nil ? true : store.bool(forKey: key)
    }

    package static func set(_ enabled: Bool, in store: UserDefaults = .standard) {
        store.set(enabled, forKey: key)
    }
}
