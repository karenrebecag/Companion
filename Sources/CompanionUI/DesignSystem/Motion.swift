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
    /// A meter following a live level: anything slower lags the voice.
    public static let follow = 0.08
}

/// The one entry curve (spec 16f §9, M3): a strong ease-out that starts
/// fast and settles long. Every fade and move that enters uses it.
public enum MotionCurve {
    /// Incredible's named curves (16l).
    public static let standard: [Double] = [0.4, 0, 0.2, 1]
    public static let settle: [Double] = [0.32, 0.72, 0, 1]
    public static let glide: [Double] = [0.22, 1, 0.36, 1]
    public static let bounce: [Double] = [0.34, 1.56, 0.64, 1]
    public static let enter: [Double] = glide

    public static func animation(_ curve: [Double], _ duration: Double) -> Animation {
        .timingCurve(curve[0], curve[1], curve[2], curve[3], duration: duration)
    }
}

/// A spring as numbers, so the rules can be checked on it (M4): how far it
/// overshoots and when it has settled.
public struct MotionSpring: Sendable, Equatable {
    public let response: Double
    public let damping: Double

    public init(response: Double, damping: Double) {
        self.response = response
        self.damping = damping
    }

    public var animation: Animation { .spring(response: response, dampingFraction: damping) }

    /// Peak past the target, as a fraction of the travel.
    public var overshoot: Double {
        guard damping < 1 else { return 0 }
        return exp(-Double.pi * damping / (1 - damping * damping).squareRoot())
    }

    /// Seconds until it stays within 2 % of the target.
    public var settle: Double {
        let omega = 2 * Double.pi / response
        // The envelope of an underdamped spring starts at 1/sqrt(1 - z^2), not 1.
        return damping < 1
            ? log(50 / (1 - damping * damping).squareRoot()) / (damping * omega)
            : 5.83 * damping / omega
    }

    public static let hover = MotionSpring(response: 0.3, damping: 0.9)
    public static let sheet = MotionSpring(response: 0.32, damping: 0.86)
    public static let select = MotionSpring(response: 0.3, damping: 0.9)
    public static let press = MotionSpring(response: 0.25, damping: 0.9)
    /// The island (spec 16f §4): pill, panel, close.
    public static let islandPill = MotionSpring(response: 0.14, damping: 1)
    public static let islandPanel = MotionSpring(response: 0.18, damping: 0.82)
    public static let islandClose = MotionSpring(response: 0.18, damping: 1)
    /// The "done" light: the only small bob outside the panel (M4).
    public static let success = MotionSpring(response: 0.35, damping: 0.8)
    /// The notch leaning toward the pointer (spec 16i §11): NotchNook's peek
    /// visibly overshoots and relaxes, which is what makes it feel alive.
    public static let islandPeek = MotionSpring(response: 0.35, damping: 0.65)

    /// The named exceptions to M4: a gesture of tension, never a surface
    /// that carries content, and never past 8 %.
    public static let lively: [(String, MotionSpring)] = [("islandPeek", islandPeek)]

    public static let all: [(String, MotionSpring)] = [
        ("hover", hover), ("sheet", sheet), ("select", select), ("press", press),
        ("islandPill", islandPill), ("islandPanel", islandPanel), ("islandClose", islandClose),
        ("success", success),
    ]
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
    /// Expo-out: what enters the view.
    public static func expoOut(_ duration: Double = MotionTime.panel) -> Animation {
        let c = MotionCurve.enter
        return .timingCurve(c[0], c[1], c[2], c[3], duration: duration)
    }

    // Spring curves: barely any bounce, the panel's is the most (M4).
    /// Hover and approach.
    public static var springHover: Animation { MotionSpring.hover.animation }
    /// Sheets, dropdowns and overlays.
    public static var springSheet: Animation { MotionSpring.sheet.animation }
    /// Selection and state changes.
    public static var springSelect: Animation { MotionSpring.select.animation }
    /// Pressure feedback.
    public static var springPress: Animation { MotionSpring.press.animation }
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
                withAnimation(.expoOut(MotionTime.panel)
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
