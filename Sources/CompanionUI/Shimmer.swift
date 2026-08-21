import CompanionCore
import SwiftUI

public enum ShimmerMotion {
    public static func phase(
        elapsed: TimeInterval, period: TimeInterval, delay: TimeInterval
    ) -> Double {
        guard elapsed >= delay, period > 0 else { return 0 }
        let t = elapsed - delay
        return t.truncatingRemainder(dividingBy: period) / period
    }

    public static func isActive(for state: TurnState) -> Bool {
        state == .thinking || state == .connecting
    }
}

public enum ShimmerRingMotion {
    public static let listeningDuration: TimeInterval = 1.15
    public static let thinkingDuration: TimeInterval = 2.0
    public static let listeningBand: CGFloat = 0.38
    public static let thinkingBand: CGFloat = 0.5

    public static func duration(thinking: Bool) -> TimeInterval {
        thinking ? thinkingDuration : listeningDuration
    }

    public static func bandSize(thinking: Bool) -> CGFloat {
        thinking ? thinkingBand : listeningBand
    }
}

struct Shimmer: ViewModifier {
    var active: Bool
    var period: TimeInterval = 1.5
    var delay: TimeInterval = 0.25
    var bandSize: CGFloat = 0.35
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var started = Date()

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
                let p = ShimmerMotion.phase(
                    elapsed: timeline.date.timeIntervalSince(started),
                    period: period,
                    delay: delay)
                content.mask(band(p))
            }
        } else {
            content
        }
    }

    private func band(_ phase: Double) -> some View {
        let start = UnitPoint(x: phase - bandSize, y: phase - bandSize)
        let end = UnitPoint(x: phase + 1 - bandSize, y: phase + 1 - bandSize)
        return LinearGradient(
            colors: [
                Color.white.opacity(0.15),
                Color.white,
                Color.white.opacity(0.15),
            ],
            startPoint: start,
            endPoint: end)
    }
}

extension View {
    func shimmering(
        active: Bool,
        period: TimeInterval = 1.5,
        delay: TimeInterval = 0.25,
        bandSize: CGFloat = 0.35
    ) -> some View {
        modifier(Shimmer(
            active: active, period: period, delay: delay, bandSize: bandSize))
    }
}

/// Hairline around the orb. The sweep is the only status chrome while
/// listening or thinking.
struct ShimmerRing: View {
    let active: Bool
    let thinking: Bool
    let reduceMotion: Bool

    var body: some View {
        Circle()
            .strokeBorder(Color.white.opacity(active ? 0.55 : 0), lineWidth: 1.6)
            .padding(Space.x1 / 4)
            .shimmering(
                active: active && !reduceMotion,
                period: ShimmerRingMotion.duration(thinking: thinking),
                delay: 0,
                bandSize: ShimmerRingMotion.bandSize(thinking: thinking))
            .opacity(active ? 1 : 0)
            .animation(
                .easeOut(duration: reduceMotion ? 0 : MotionTime.fast),
                value: active)
    }
}
