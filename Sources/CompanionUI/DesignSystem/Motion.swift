import Cocoa
import SwiftUI

// MARK: - Motion timing from ATOM UIKit scale

/// Named durations. Each step has a specific use, not a preference.
/// Portado del prototipo; mismo orden de magnitudes en ATOM design tokens.
package enum MotionTime {
    /// Hovers, tooltips, immediate feedback.
    package static let fast = 0.15
    /// Default UI transition.
    package static let base = 0.2
    /// Dropdowns, panels, reveals.
    package static let panel = 0.3
    /// Macro entries — ATOM signature (600ms + osmo).
    package static let enter = 0.6
    /// Long layout changes.
    package static let layout = 0.9
    /// A meter following a live level: anything slower lags the voice.
    package static let follow = 0.08
    /// The touched-apps reel swaps its one item at Incredible's pace (local
    /// reference, brief isla-ciclo-y-legibilidad K8).
    package static let reelSwap = 0.65
    /// A slider's knob growing under the pointer: Incredible's island volume.
    package static let knob = 0.12
    /// The permission guide's art swaps with a fade (Incredible's fr-permission-fade).
    package static let permissionFade = panel
    /// A page's first frame lands with an overshoot (Incredible's fr-land).
    package static let land = 0.46
    /// A permission's step circle pops when it is granted (Incredible's fr-perm-granted).
    package static let stepGranted = 0.36
}

/// The one entry curve (spec 16f §9, M3): a strong ease-out that starts
/// fast and settles long. Every fade and move that enters uses it.
package enum MotionCurve {
    /// Incredible's named curves (16l).
    package static let standard: [Double] = [0.4, 0, 0.2, 1]
    package static let settle: [Double] = [0.32, 0.72, 0, 1]
    package static let glide: [Double] = [0.22, 1, 0.36, 1]
    package static let bounce: [Double] = [0.34, 1.56, 0.64, 1]
    /// CSS `linear`: Incredible's reduced-motion fade for a card.
    package static let linear: [Double] = [0, 0, 1, 1]
    /// Incredible's --ease-island: every change of the island's shape. It overshoots ~1.5 %.
    package static let island: [Double] = [0.22, 1.22, 0.36, 1]
    /// CSS `ease`, which SwiftUI's easeInOut is not: Incredible fades the island's content with it.
    package static let ease: [Double] = [0.25, 0.1, 0.25, 1]
    /// CSS `ease-out`: Incredible's composer orb follows the voice with it.
    package static let easeOut: [Double] = [0, 0, 0.58, 1]
    package static let enter: [Double] = glide

    package static func animation(_ curve: [Double], _ duration: Double) -> Animation {
        .timingCurve(curve[0], curve[1], curve[2], curve[3], duration: duration)
    }

    /// Progress of a cubic Bezier at time fraction `x`, as CSS samples it, so the
    /// rules can be checked on a curve the way they are on a spring.
    package static func value(_ curve: [Double], at x: Double) -> Double {
        func point(_ t: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t
        }
        // Bisection leaves a residue at the ends; a word at rest must read exactly unlit.
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        var low = 0.0
        var high = 1.0
        for _ in 0..<50 {
            let mid = (low + high) / 2
            if point(mid, curve[0], curve[2]) < x { low = mid } else { high = mid }
        }
        return point((low + high) / 2, curve[1], curve[3])
    }

    /// Seconds until the curve stays within 2 % of the target, the same measure as `MotionSpring.settle`.
    package static func settledAt(_ curve: [Double], duration: Double) -> Double {
        let samples = 1000
        let last = (0...samples).last { abs(value(curve, at: Double($0) / Double(samples)) - 1) > 0.02 } ?? 0
        return Double(last) / Double(samples) * duration
    }
}

/// A spring as numbers, so the rules can be checked on it (M4): how far it
/// overshoots and when it has settled.
package struct MotionSpring: Sendable, Equatable {
    package let response: Double
    package let damping: Double

    package init(response: Double, damping: Double) {
        self.response = response
        self.damping = damping
    }

    package var animation: Animation { .spring(response: response, dampingFraction: damping) }

    /// Peak past the target, as a fraction of the travel.
    package var overshoot: Double {
        guard damping < 1 else { return 0 }
        return exp(-Double.pi * damping / (1 - damping * damping).squareRoot())
    }

    /// Seconds until it stays within 2 % of the target.
    package var settle: Double {
        let omega = 2 * Double.pi / response
        // The envelope of an underdamped spring starts at 1/sqrt(1 - z^2), not 1.
        return damping < 1
            ? log(50 / (1 - damping * damping).squareRoot()) / (damping * omega)
            : 5.83 * damping / omega
    }

    package static let hover = MotionSpring(response: 0.3, damping: 0.9)
    package static let sheet = MotionSpring(response: 0.32, damping: 0.86)
    package static let select = MotionSpring(response: 0.3, damping: 0.9)
    package static let press = MotionSpring(response: 0.25, damping: 0.9)
    /// The "done" light: the only small bob outside the panel (M4).
    package static let success = MotionSpring(response: 0.35, damping: 0.8)
    /// The notch leaning toward the pointer (spec 16i §11): NotchNook's peek
    /// visibly overshoots and relaxes, which is what makes it feel alive.
    package static let islandPeek = MotionSpring(response: 0.35, damping: 0.65)

    /// The named exceptions to M4: a gesture of tension, never a surface
    /// that carries content, and never past 8 %.
    package static let lively: [(String, MotionSpring)] = [("islandPeek", islandPeek)]

    package static let all: [(String, MotionSpring)] = [
        ("hover", hover), ("sheet", sheet), ("select", select), ("press", press), ("success", success),
    ]
}

/// Stagger step by density: how often each child of a list enters.
package enum Stagger {
    /// Dense cards and items.
    package static let dense = 0.03
    /// Children of a section, words.
    package static let base = 0.05
    /// Lines and large reveals.
    package static let loose = 0.075
}

// MARK: - Easing curves (SwiftUI Animation)

extension Animation {
    /// Expo-out: what enters the view.
    package static func expoOut(_ duration: Double = MotionTime.panel) -> Animation {
        let c = MotionCurve.enter
        return .timingCurve(c[0], c[1], c[2], c[3], duration: duration)
    }

    // Spring curves: barely any bounce, the panel's is the most (M4).
    /// Hover and approach.
    package static var springHover: Animation { MotionSpring.hover.animation }
    /// Sheets, dropdowns and overlays.
    package static var springSheet: Animation { MotionSpring.sheet.animation }
    /// Selection and state changes.
    package static var springSelect: Animation { MotionSpring.select.animation }
    /// Pressure feedback.
    package static var springPress: Animation { MotionSpring.press.animation }
}

// MARK: - Staggered reveal modifier

/// Staged appearance by index — generalized mechanic.
/// Respects reduced-motion.
package struct StaggeredReveal: ViewModifier {
    let index: Int
    var step: Double = Stagger.dense
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    package func body(content: Content) -> some View {
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
    package func staggered(_ index: Int, step: Double = Stagger.dense) -> some View {
        modifier(StaggeredReveal(index: index, step: step))
    }
}
