import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

// Incredible 0.2.36's header swap: the new line rises from below its own height while
// the old one leaves above, each property on its own clock.

@Test @MainActor func theNewHeaderLineRisesFromBelowWithTheIslandCurve() {
    let swap = IslandMotionBudget.headerSwap
    let entering = swap.state(.entering)
    expectEq(entering.travel, 1.2, "entra: desde 120 % de su altura, abajo")
    expectEq(entering.opacity, 0, "entra: desde invisible")
    expectEq(entering.blur, 2, "entra: desde 2 pt de desenfoque")
    expectEq(swap.move(leaving: false), .timing(MotionCurve.island, 0.36), "entra: 360 ms con la curva de la isla")
    expectEq(swap.fade, .timing(MotionCurve.standard, 0.15), "opacidad: 150 ms standard")
    expectEq(swap.focus, .timing(MotionCurve.standard, 0.22), "desenfoque: 220 ms standard")
}

@Test @MainActor func theOldHeaderLineLeavesAboveFaster() {
    let swap = IslandMotionBudget.headerSwap
    let leaving = swap.state(.leaving)
    expectEq(leaving.travel, -1.2, "sale: hasta -120 % de su altura, arriba")
    expectEq(leaving.opacity, 0, "sale: hasta invisible")
    expectEq(leaving.blur, 2, "sale: con 2 pt de desenfoque")
    expectEq(swap.move(leaving: true), .timing(MotionCurve.standard, 0.22), "sale: 220 ms standard")
}

@Test @MainActor func aShownHeaderLineSitsStill() {
    let shown = IslandMotionBudget.headerSwap.state(.shown)
    expectEq(shown.travel, 0, "quieta: en su lugar")
    expectEq(shown.opacity, 1, "quieta: visible")
    expectEq(shown.blur, 0, "quieta: nítida")
}

@Test @MainActor func theSwapLastsAsLongAsItsSlowestProperty() {
    let swap = IslandMotionBudget.headerSwap
    expectEq(swap.longest, 0.36, "el cambio dura lo que su propiedad más lenta, la subida")
}

@Test @MainActor func longestIsTheSlowestOfAnyProperty() {
    let quick = IslandMotion.Curve.timing(MotionCurve.standard, 0.1)
    let slow = IslandMotion.Curve.timing(MotionCurve.standard, 0.5)
    for (name, swap) in [
        ("rise", IslandMotionBudget.HeaderSwap(travel: 1, blur: 0, rise: slow, leave: quick, fade: quick, focus: quick)),
        ("leave", IslandMotionBudget.HeaderSwap(travel: 1, blur: 0, rise: quick, leave: slow, fade: quick, focus: quick)),
        ("fade", IslandMotionBudget.HeaderSwap(travel: 1, blur: 0, rise: quick, leave: quick, fade: slow, focus: quick)),
        ("focus", IslandMotionBudget.HeaderSwap(travel: 1, blur: 0, rise: quick, leave: quick, fade: quick, focus: slow)),
    ] {
        expectEq(swap.longest, 0.5, "longest: cuenta \(name)")
    }
}

@Test @MainActor func aTransitionPhaseMapsToWhereTheLineIs() {
    expectEq(IslandMotionBudget.HeaderSwap.Phase(TransitionPhase.willAppear), .entering, "aparece: entra desde abajo")
    expectEq(IslandMotionBudget.HeaderSwap.Phase(TransitionPhase.identity), .shown, "quieta")
    expectEq(IslandMotionBudget.HeaderSwap.Phase(TransitionPhase.didDisappear), .leaving, "desaparece: sale por arriba")
}

/// Reduce motion keeps the status line a short fade: the travel and blur are motion.
@Test @MainActor func theStatusLineUnderReduceMotionIsAShortFade() {
    let swap = IslandMotionBudget.headerSwap
    expectEq(swap.lifetime(reduceMotion: false), .timing(MotionCurve.standard, 0.36), "el cambio vive lo que su propiedad más lenta")
    expect(swap.lifetime(reduceMotion: true).duration <= MotionTime.fast, "reducir movimiento: fundido corto")
    expect(!swap.travels(reduceMotion: true), "reducir movimiento: sin subida ni desenfoque")
    expect(swap.travels(reduceMotion: false), "sin reducir: sube y enfoca")
}

@Test @MainActor func aRelativeOffsetAnimatesThroughItsFraction() {
    var effect = IslandRelativeOffset(fraction: 0)
    effect.animatableData = 0.6
    expect(abs(effect.effectValue(size: CGSize(width: 200, height: 20)).m32 - 12) < 1e-9, "a mitad de camino, 12 pt")
}

@Test @MainActor func aRelativeOffsetMovesByItsOwnHeight() {
    let effect = IslandRelativeOffset(fraction: 1.2)
    let transform = effect.effectValue(size: CGSize(width: 200, height: 20))
    expect(abs(transform.m32 - 24) < 1e-9, "120 % de 20 pt son 24 pt hacia abajo: \(transform.m32)")
    expectEq(IslandRelativeOffset(fraction: 0).effectValue(size: CGSize(width: 200, height: 20)).m32, 0, "sin fracción, quieta")
}
