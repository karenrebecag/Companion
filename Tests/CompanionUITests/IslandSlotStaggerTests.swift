import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// Incredible 0.2.36 reveals the open island in three slots, 30 ms apart: the field, then
// the conversation, then the cards (referencia local, --isl-content-reveal-delay-2 y -3).

@Test @MainActor func theSlotsRevealThirtyMillisecondsApart() {
    let start = { (slot: IslandMotion.Slot) in
        IslandMotion.contentStart(from: .pebble, to: .nudge, reduceMotion: false, slot: slot)
    }
    expectEq(IslandMotion.slotStep, 0.03, "ranuras: 30 ms entre una y otra")
    expect(abs(start(.field) - 0.06) < 1e-9, "campo: a los 60 ms, con el resto del contenido")
    expect(abs(start(.conversation) - 0.09) < 1e-9, "conversacion: a los 90 ms")
    expect(abs(start(.card) - 0.12) < 1e-9, "tarjeta: a los 120 ms")
    expectEq(IslandMotion.Slot.allCases, [.field, .conversation, .card], "ranuras: en el orden de Incredible")
}

@Test @MainActor func theFieldSlotIsTheContentBeat() {
    expectEq(IslandMotion.slotDelay(.field, reduceMotion: false), 0,
             "campo: entra con el latido de contenido, sin espera propia")
    expectEq(IslandMotion.contentStart(from: .pebble, to: .nudge, reduceMotion: false),
             IslandMotion.contentStart(from: .pebble, to: .nudge, reduceMotion: false, slot: .field),
             "sin ranura es la del campo")
}

@Test @MainActor func underReduceMotionNoSlotWaits() {
    for slot in IslandMotion.Slot.allCases {
        expectEq(IslandMotion.slotDelay(slot, reduceMotion: true), 0, "reducido: \(slot) no espera")
        expectEq(IslandMotion.contentStart(from: .pebble, to: .nudge, reduceMotion: true, slot: slot), 0,
                 "reducido: \(slot) entra ya")
    }
}

@Test @MainActor func closingTakesEverySlotOutTogether() {
    for slot in IslandMotion.Slot.allCases {
        let leaving = IslandMotion.slotFade(slot, showing: false, reduceMotion: false)
        expectEq(leaving?.delay, 0, "cerrar: \(slot) sale sin espera, a la vez que la forma")
        expectEq(leaving?.duration, IslandMotionBudget.contentOut.duration, "cerrar: \(slot) sale en 130 ms")
        expect(IslandMotion.slotFade(slot, showing: false, reduceMotion: true) == nil,
               "reducido: \(slot) desaparece al instante")
    }
}

@Test @MainActor func openingFadesEachSlotOnItsOwnBeat() {
    for slot in IslandMotion.Slot.allCases {
        let entering = IslandMotion.slotFade(slot, showing: true, reduceMotion: false)
        expectEq(entering?.delay, IslandMotion.slotDelay(slot, reduceMotion: false), "abrir: \(slot) con su espera")
        expectEq(entering?.duration, IslandMotionBudget.contentIn.duration, "abrir: \(slot) en 130 ms")
        expectEq(entering?.curve, MotionCurve.ease, "abrir: \(slot) con ease de CSS")
        let reduced = IslandMotion.slotFade(slot, showing: true, reduceMotion: true)
        expectEq(reduced?.delay, 0, "reducido: \(slot) entra sin espera")
    }
}

@Test @MainActor func theLastSlotIsInWithinTheOpeningBudget() {
    let last = IslandMotion.contentStart(from: .pebble, to: .nudge, reduceMotion: false, slot: .card)
        + IslandMotionBudget.contentIn.duration
    expect(last <= 0.4, "M2: la ultima ranura termina de entrar en \(last) s")
}

// The approval sheet lives in the card slot: opening straight onto it, the sheet must be
// fully visible before "Permitir" accepts a click.
@Test @MainActor func theCardSlotIsVisibleBeforeAnApprovalAcceptsAClick() {
    let visible = IslandMotion.contentStart(from: .pebble, to: .card, reduceMotion: false, slot: .card)
        + max(IslandMotionBudget.contentIn.duration, IslandMotionBudget.card.enter.duration)
    expect(visible < ApprovalClickGuard.dwell, "aprobacion: visible a los \(visible) s, antes del dwell")
}
