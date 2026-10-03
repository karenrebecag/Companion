import SwiftUI

/// Incredible's inline spinner is lucide's LoaderCircle at 14 px turning on
/// Tailwind's animate-spin (local reference 0.2.36), not the system's petal
/// ProgressView. Measured on lucide's 24-unit viewBox.
package enum LoaderArcMetrics {
    package static let size: CGFloat = 14
    private static let viewBox: CGFloat = 24
    package static let lineWidth: CGFloat = size * 2 / viewBox
    package static let diameter: CGFloat = size * 18 / viewBox
    /// The path runs 288 of the circle's 360 degrees.
    package static let sweep: CGFloat = 0.8
}

package enum LoaderArcMotion {
    package static let period: TimeInterval = 1

    package static func degrees(elapsed: TimeInterval) -> Double {
        guard elapsed > 0 else { return 0 }
        return elapsed.truncatingRemainder(dividingBy: period) / period * 360
    }
}

/// Decorative: the label beside it names the wait. It keeps turning under
/// Reduce Motion, as Incredible's does and the system spinner it replaces
/// did, because a frozen arc reads as a stall.
struct LoaderArc: View {
    @State private var started = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            Circle()
                .trim(from: 0, to: LoaderArcMetrics.sweep)
                .stroke(style: StrokeStyle(lineWidth: LoaderArcMetrics.lineWidth, lineCap: .round))
                .frame(width: LoaderArcMetrics.diameter, height: LoaderArcMetrics.diameter)
                .rotationEffect(.degrees(LoaderArcMotion.degrees(elapsed: timeline.date.timeIntervalSince(started))))
        }
        .frame(width: LoaderArcMetrics.size, height: LoaderArcMetrics.size)
        .accessibilityHidden(true)
    }
}
