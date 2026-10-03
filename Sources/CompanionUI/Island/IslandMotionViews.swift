import CompanionCore
import SwiftUI

// The island's moving parts (Wave 16f). The numbers live in IslandMotion.swift,
// the token file; this one only applies them, under every conformance rule.

/// Enters from below with a blur that clears; leaves the way `exit` says.
struct IslandMoveModifier: ViewModifier {
    let opacity: Double
    let blur: CGFloat
    let offset: CGFloat

    func body(content: Content) -> some View {
        content.opacity(opacity).blur(radius: blur).offset(y: offset)
    }
}

/// Moves a view by a fraction of its own height: Incredible's header swap travels 120 %
/// of the line, whatever its font, and a fixed offset in points would not.
struct IslandRelativeOffset: GeometryEffect {
    var fraction: CGFloat

    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 0, y: fraction * size.height))
    }
}

/// The header swap with each property on its own clock, as Incredible's CSS transitions
/// transform, opacity and filter separately.
struct IslandHeaderSwapTransition: Transition {
    let swap: IslandMotionBudget.HeaderSwap

    func body(content: Content, phase: TransitionPhase) -> some View {
        let place = IslandMotionBudget.HeaderSwap.Phase(phase)
        let state = swap.state(place)
        return content
            .animation(swap.move(leaving: place == .leaving).animation) {
                $0.modifier(IslandRelativeOffset(fraction: state.travel))
            }
            .animation(swap.fade.animation) { $0.opacity(state.opacity) }
            .animation(swap.focus.animation) { $0.blur(radius: state.blur) }
    }
}

extension AnyTransition {
    /// Panel reveal: rises in with a blur; leaves as a quiet fade (M2).
    static func islandReveal(_ move: IslandMotionBudget.Move) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: IslandMoveModifier(opacity: 0, blur: move.blur, offset: move.offset),
                identity: IslandMoveModifier(opacity: 1, blur: 0, offset: 0)),
            removal: .opacity)
    }
}

/// Texts reveal for a list: each row rises in on its own beat.
struct IslandLineReveal: ViewModifier {
    let index: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        let move = IslandMotionBudget.line.resolved(reduceMotion: reduceMotion)
        content
            .modifier(IslandMoveModifier(
                opacity: shown ? 1 : 0, blur: shown ? 0 : move.blur, offset: shown ? 0 : move.offset))
            .onAppear {
                withAnimation(IslandMotionBudget.line.animation(reduceMotion: reduceMotion)
                    .delay(reduceMotion ? 0 : IslandMotionBudget.delay(line: index))) {
                    shown = true
                }
            }
    }
}

/// One black silhouette that continues the notch: flush with the top edge,
/// concave shoulders where it meets the screen, round at the bottom.
struct NotchShape: Shape {
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat

    /// The flare where the silhouette meets the top edge of the screen.
    static let shoulder: CGFloat = 8
    /// The hardware notch's own corner, and the open panel's.
    static let restRadius: CGFloat = 10
    static let openRadius: CGFloat = 22

    static func clampedRadius(_ radius: CGFloat, height: CGFloat) -> CGFloat {
        min(radius, height / 2)
    }

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(width, AnimatablePair(height, radius)) }
        set {
            width = newValue.first
            height = newValue.second.first
            radius = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let s = Self.shoulder
        let r = Self.clampedRadius(radius, height: height)
        let left = rect.midX - width / 2
        let right = rect.midX + width / 2
        var path = Path()
        path.move(to: CGPoint(x: left - s, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: left, y: rect.minY + s), control: CGPoint(x: left, y: rect.minY))
        path.addLine(to: CGPoint(x: left, y: rect.minY + height - r))
        path.addQuadCurve(to: CGPoint(x: left + r, y: rect.minY + height),
                          control: CGPoint(x: left, y: rect.minY + height))
        path.addLine(to: CGPoint(x: right - r, y: rect.minY + height))
        path.addQuadCurve(to: CGPoint(x: right, y: rect.minY + height - r),
                          control: CGPoint(x: right, y: rect.minY + height))
        path.addLine(to: CGPoint(x: right, y: rect.minY + s))
        path.addQuadCurve(to: CGPoint(x: right + s, y: rect.minY), control: CGPoint(x: right, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
