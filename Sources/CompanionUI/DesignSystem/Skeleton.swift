import SwiftUI

/// Incredible's skeleton defaults to Tailwind's animate-pulse (local
/// reference 0.2.36): opacity dips to half and back on a 2 s ease-in-out,
/// and `motion-reduce:animate-none` leaves the plain fill. The shimmer sweep
/// it also ships is opt-in there and unused by the Apps surface.
package enum SkeletonMotion {
    package static let period: TimeInterval = 2
    package static let curve: [Double] = [0.4, 0, 0.6, 1]
    package static let dimmed = 0.5

    package static func animates(reduceMotion: Bool) -> Bool { !reduceMotion }

    package static func opacity(elapsed: TimeInterval, reduceMotion: Bool = false) -> Double {
        guard animates(reduceMotion: reduceMotion), elapsed > 0 else { return 1 }
        let phase = elapsed.truncatingRemainder(dividingBy: period) / period
        // CSS eases each keyframe segment on its own, so both halves start
        // and land slowly instead of one curve stretched over the cycle.
        if phase < 0.5 {
            return 1 - (1 - dimmed) * MotionCurve.value(curve, at: phase * 2)
        }
        return dimmed + (1 - dimmed) * MotionCurve.value(curve, at: (phase - 0.5) * 2)
    }
}

/// One placeholder shape. Decorative: the container it sits in carries the
/// single "loading" label.
struct SkeletonBlock: View {
    let width: CGFloat?
    let height: CGFloat
    let radius: CGFloat
    let opacity: Double

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(Semantic.surfaceSecondary)
            .frame(maxWidth: width, minHeight: height, maxHeight: height)
            .opacity(opacity)
            .accessibilityHidden(true)
    }
}

/// Drives every block below it from one clock, so they pulse together the
/// way Incredible's siblings do (each starts its animation on the same frame).
struct SkeletonPulse<Content: View>: View {
    @ViewBuilder let content: (Double) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()

    var body: some View {
        if SkeletonMotion.animates(reduceMotion: reduceMotion) {
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                content(SkeletonMotion.opacity(elapsed: timeline.date.timeIntervalSince(started), reduceMotion: reduceMotion))
            }
        } else {
            content(SkeletonMotion.opacity(elapsed: Date().timeIntervalSince(started), reduceMotion: reduceMotion))
        }
    }
}
