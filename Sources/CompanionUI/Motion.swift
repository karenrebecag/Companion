import Cocoa
import SwiftUI

// MARK: - Motion timing from ATOM UIKit scale

/// Named durations. Each step has a specific use, not a preference.
/// Portado del prototipo; mismo orden de magnitudes en ATOM design tokens.
public enum MotionTime {
    /// Hovers, tooltips, immediate feedback.
    public static let fast = 0.15
    /// Default UI transition.
    public static let base = 0.2
    /// Dropdowns, panels, reveals.
    public static let panel = 0.3
    /// Macro entries — ATOM signature (600ms + osmo).
    public static let enter = 0.6
    /// Long layout changes.
    public static let layout = 0.9
}

/// Stagger step by density: how often each child of a list enters.
public enum Stagger {
    /// Dense cards and items.
    public static let dense = 0.03
    /// Children of a section, words.
    public static let base = 0.05
    /// Lines and large reveals.
    public static let loose = 0.075
}

// MARK: - Easing curves (SwiftUI Animation)

extension Animation {
    /// ATOM signature curve: aggressive start, long settle.
    public static func osmo(_ duration: Double = MotionTime.enter) -> Animation {
        .timingCurve(0.625, 0.05, 0, 1, duration: duration)
    }

    /// Expo-out: what enters the view.
    public static func expoOut(_ duration: Double = MotionTime.panel) -> Animation {
        .timingCurve(0.22, 1, 0.36, 1, duration: duration)
    }

    // Spring curves
    /// Hover and approach.
    public static var springHover: Animation { .spring(response: 0.3, dampingFraction: 0.8) }
    /// Sheets, dropdowns and overlays.
    public static var springSheet: Animation { .spring(response: 0.32, dampingFraction: 0.82) }
    /// Selection and state changes.
    public static var springSelect: Animation { .spring(response: 0.3, dampingFraction: 0.85) }
    /// Pressure feedback.
    public static var springPress: Animation { .spring(response: 0.25, dampingFraction: 0.8) }
}

// MARK: - Staggered reveal modifier

/// Staged appearance by index — generalized mechanic.
/// Respects reduced-motion.
public struct StaggeredReveal: ViewModifier {
    let index: Int
    var step: Double = Stagger.dense
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    public func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : -4)
            .onAppear {
                guard !reduceMotion else {
                    revealed = true
                    return
                }
                withAnimation(.osmo(MotionTime.panel)
                    .delay(Double(index) * step)) {
                    revealed = true
                }
            }
    }
}

extension View {
    /// Staggered appearance by index with customizable step.
    public func staggered(_ index: Int, step: Double = Stagger.dense) -> some View {
        modifier(StaggeredReveal(index: index, step: step))
    }
}
