import SwiftUI

/// Incredible 0.2.36's cinematic intro "signal burst" as numbers, so the
/// curve and the colours can be checked without rendering.
/// Reference: styles-CTdsYdwA.css @8523 (.fr-burst), @8771 (fires on the
/// speak beat), @8881-8990 (keyframes), @9046 (reduced motion: 1 ms).
package enum SignalBurst {
    package static let width: CGFloat = 900
    package static let height: CGFloat = 320
    package static let duration = 0.7
    /// styles @8771. CSS applies the timing function to EACH keyframe
    /// segment, so both segments below ease with it.
    package static let curve: [Double] = [0.2, 0.8, 0.2, 1]

    package typealias Keyframe = (at: Double, opacity: Double, scale: Double)
    /// styles @8881-8990.
    package static let keyframes: [Keyframe] = [(0, 0, 0.5), (0.1, 1, 0.8), (1, 0, 1.3)]

    package static func sample(at fraction: Double) -> (opacity: Double, scale: Double) {
        let t = min(max(fraction, 0), 1)
        let upper = keyframes.firstIndex { $0.at >= t } ?? keyframes.count - 1
        let to = keyframes[upper]
        guard upper > 0 else { return (to.opacity, to.scale) }
        let from = keyframes[upper - 1]
        let eased = MotionCurve.value(curve, at: (t - from.at) / (to.at - from.at))
        return (from.opacity + (to.opacity - from.opacity) * eased,
                from.scale + (to.scale - from.scale) * eased)
    }

    /// styles @9046 squeezes every animation to 1 ms under reduced motion:
    /// the burst is effectively never seen, so here it is never drawn. Not
    /// drawing (rather than muting the trigger) keeps a mid-session toggle
    /// from changing the animator's trigger and replaying the burst.
    package static func draws(reduceMotion: Bool) -> Bool { !reduceMotion }

    package typealias Stop = (location: Double, hex: String, alpha: Double)

    /// On dark, exactly Incredible's stops (styles @8523). The welcome is
    /// forced light, where #ebf4ff80 / #c8e1ff33 vanish on near-white paper,
    /// so light takes the stronger stop of Incredible's own .fr-bar gradient
    /// (styles @6507, #afcdffd9) to keep the glow readable.
    package static func stops(dark: Bool) -> [Stop] {
        dark
            ? [(0, "EBF4FF", 0.5), (0.35, "C8E1FF", 0.2), (0.7, "C8E1FF", 0)]
            : [(0, "AFCDFF", 0.55), (0.35, "AFCDFF", 0.2), (0.7, "AFCDFF", 0)]
    }
}

/// A radial glow that flashes from the top edge of its container each time
/// `trigger` changes. Draws nothing at rest and under Reduce Motion.
struct WelcomeSignalBurst: View {
    private let trigger: Int
    private let fixed: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    init(trigger: Int) {
        self.trigger = trigger
        self.fixed = nil
    }

    /// Static snapshot at a fixed point of the animation.
    init(fraction: Double) {
        self.trigger = 0
        self.fixed = fraction
    }

    var body: some View {
        Group {
            if let fixed {
                let value = SignalBurst.sample(at: fixed)
                disc.scaleEffect(value.scale).opacity(value.opacity)
            } else if SignalBurst.draws(reduceMotion: reduceMotion) {
                disc.keyframeAnimator(initialValue: 0.0, trigger: trigger) { content, fraction in
                    let value = SignalBurst.sample(at: fraction)
                    return content.scaleEffect(value.scale).opacity(value.opacity)
                } keyframes: { _ in
                    KeyframeTrack {
                        MoveKeyframe(0)
                        LinearKeyframe(1, duration: SignalBurst.duration)
                    }
                }
            }
        }
        // Centred on the container's top edge, as styles @8523 does with top:0.
        .offset(y: -SignalBurst.height / 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var disc: some View {
        Ellipse()
            .fill(EllipticalGradient(
                stops: SignalBurst.stops(dark: scheme == .dark).map {
                    .init(color: Swatch($0.hex).color.opacity($0.alpha), location: $0.location)
                }))
            .frame(width: SignalBurst.width, height: SignalBurst.height)
    }
}
