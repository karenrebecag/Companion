import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

// Incredible 0.2.36's cards (`.ov-card`): they settle up into place and leave the way they came.

@Test @MainActor func aCardSettlesUpIntoPlace() {
    let card = IslandMotionBudget.card
    expectEq(card.enter, .timing(MotionCurve.settle, 0.26), "tarjeta: entra en 260 ms settle")
    let entering = card.state(.entering)
    expectEq(entering.opacity, 0, "tarjeta: entra desde invisible")
    expectEq(entering.offset, 6, "tarjeta: desde 6 pt abajo")
    expectEq(entering.scale, 0.98, "tarjeta: desde 0.98")
    let shown = card.state(.shown)
    expectEq([shown.opacity, Double(shown.offset), Double(shown.scale)], [1, 0, 1], "tarjeta: quieta en su lugar")
}

@Test @MainActor func aCardLeavesFasterTheWayItCame() {
    let card = IslandMotionBudget.card
    expectEq(card.exit, .timing(MotionCurve.settle, 0.2), "tarjeta: sale en 200 ms settle")
    let leaving = card.state(.leaving)
    expectEq(leaving.opacity, 0, "tarjeta: sale a invisible")
    expectEq(leaving.offset, 4, "tarjeta: baja 4 pt")
    expectEq(leaving.scale, 0.98, "tarjeta: a 0.98")
}

@Test @MainActor func aConfirmationCardGrowsFromItsBottom() {
    expectEq(IslandMotionBudget.card.anchor, .bottom, "confirmacion: crece desde abajo al centro")
}

// QA review: the plan is what the transition builder maps, so a swap shows here.
@Test @MainActor func aCardsPlanEntersAndLeavesOnItsOwnClocks() {
    let card = IslandMotionBudget.card
    let plan = card.plan(reduceMotion: false)
    expectEq(plan.from, card.state(.entering), "plan: entra desde abajo y pequena")
    expectEq(plan.insertion, .timing(MotionCurve.settle, 0.26), "plan: entra con su reloj")
    expectEq(plan.to, card.state(.leaving), "plan: sale hacia abajo")
    expectEq(plan.removal, .timing(MotionCurve.settle, 0.2), "plan: sale con el suyo")
}

@Test @MainActor func underReduceMotionACardOnlyFades() {
    let plan = IslandMotionBudget.card.plan(reduceMotion: true)
    expectEq(plan.from, .init(opacity: 0, offset: 0, scale: 1), "reducido: ni desplazamiento ni escala")
    expectEq(plan.insertion, .timing(MotionCurve.linear, 0.12), "reducido: un fundido lineal de 120 ms")
    expect(plan.to == nil && plan.removal == nil, "reducido: sale al instante")
}

@Test @MainActor func cssLinearIsTheIdentityCurve() {
    expectEq(MotionCurve.linear, [0, 0, 1, 1], "lineal de CSS")
}

// QA review: the card left the `moves` loops, so the budget rules are checked here.
@Test @MainActor func aCardStaysInsideTheMotionBudget() {
    let card = IslandMotionBudget.card
    expect(abs(card.enterOffset) <= 12 && abs(card.exitOffset) <= 12, "M5: amplitudes pequenas")
    for curve in [card.enter, card.exit] {
        expect(curve.duration >= MotionTime.fast * 0.8, "M1: \(curve.duration) no es un parpadeo")
    }
    expect(card.exit.duration < card.enter.duration, "sale mas rapido que entra")
    expect(card.reducedFade.duration <= MotionTime.fast, "M8: reducido es un fundido corto")
    expect(max(card.enter.duration, card.reducedFade.duration) < ApprovalClickGuard.dwell,
           "aprobacion: la tarjeta termina de entrar antes de que Permitir acepte un clic")
}
