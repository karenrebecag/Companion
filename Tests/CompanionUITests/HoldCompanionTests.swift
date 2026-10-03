import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import AppKit
import Foundation
import SwiftUI
import Testing

// Incredible 0.2.36's hold companion (referencia local): the pill that rides the cursor
// while the key is held, flashing what the user touches and stacking what they hand over.

private func item(_ id: String, _ kind: HoldItem.Kind, tMs: Int = 0) -> HoldItem {
    HoldItem(id: id, kind: kind, label: id, tMs: tMs)
}

@Test @MainActor func startingAHoldShowsTheCompanionClean() {
    var state = HoldCompanionState()
    state = state.receiving([item("a", .copied)], generation: 1, nowMs: 0, words: 0, listening: true)
    state = state.started()
    expect(state.visible, "sostener: el acompanante aparece")
    expect(state.stack.isEmpty && state.flash == nil && state.marks.isEmpty, "y empieza limpio")
}

@Test @MainActor func nothingIsCollectedWhenNotListening() {
    let state = HoldCompanionState().receiving([item("a", .copied)], generation: 1, nowMs: 0, words: 0,
                                               listening: false)
    expect(state.stack.isEmpty && state.flash == nil, "sin escuchar no se recoge nada")
}

@Test @MainActor func everyNewItemFlashesAndOnlyHandedOverOnesStack() {
    var state = HoldCompanionState().started()
    state = state.receiving([item("w", .window, tMs: 10)], generation: 1, nowMs: 100, words: 0, listening: true)
    expectEq(state.flash?.id, "w", "una ventana destella")
    expect(state.stack.isEmpty, "pero no se apila")
    state = state.receiving([item("w", .window, tMs: 10), item("c", .copied, tMs: 20)],
                            generation: 1, nowMs: 200, words: 3, listening: true)
    expectEq(state.flash?.id, "c", "la copia destella")
    expectEq(state.flashSeq, 2, "cada destello cuenta")
    expectEq(state.stack.map(\.item.id), ["c"], "y se apila")
    expectEq(state.stack.first?.atMs, 200, "a la hora en que llego")
    expectEq(state.marks[3], ["\u{201C}c\u{201D}"], "y se teje en la palabra donde llego")
}

@Test @MainActor func anItemSeenBeforeIsNotCollectedAgain() {
    var state = HoldCompanionState().started()
    state = state.receiving([item("c", .copied)], generation: 1, nowMs: 100, words: 0, listening: true)
    state = state.receiving([item("c", .copied)], generation: 1, nowMs: 900, words: 2, listening: true)
    expectEq(state.flashSeq, 1, "visto una vez, destella una vez")
    expectEq(state.stack.first?.atMs, 100, "y conserva su hora")
}

@Test @MainActor func anOlderObservationDoesNotTakeTheFlash() {
    var state = HoldCompanionState().started()
    state = state.receiving([item("new", .window, tMs: 50)], generation: 1, nowMs: 0, words: 0, listening: true)
    state = state.receiving([item("old", .copied, tMs: 40)], generation: 1, nowMs: 10, words: 0, listening: true)
    expectEq(state.flash?.id, "new", "lo mas reciente sigue en el orb")
    expectEq(state.stack.map(\.item.id), ["old"], "aunque lo viejo igual se apila")
}

@Test @MainActor func aNewGenerationStartsOver() {
    var state = HoldCompanionState().started()
    state = state.receiving([item("a", .copied)], generation: 1, nowMs: 0, words: 0, listening: true)
    state = state.receiving([item("b", .file)], generation: 2, nowMs: 10, words: 0, listening: true)
    expectEq(state.stack.map(\.item.id), ["b"], "otra generacion de observaciones borra la anterior")
    expectEq(state.flashSeq, 1, "y su cuenta de destellos")
}

@Test @MainActor func dictationClearsWhatWasCollected() {
    var state = HoldCompanionState().started()
    state = state.receiving([item("a", .copied)], generation: 1, nowMs: 0, words: 0, listening: true)
    state = state.dictating()
    expect(state.stack.isEmpty && state.marks.isEmpty, "dictar no arrastra lo recogido")
    expect(state.visible, "pero el acompanante sigue")
}

@Test @MainActor func theFlashClearsOnlyIfNothingNewerCame() {
    var state = HoldCompanionState().started()
    state = state.receiving([item("a", .window, tMs: 1)], generation: 1, nowMs: 0, words: 0, listening: true)
    let first = state.flashSeq
    state = state.receiving([item("b", .window, tMs: 2)], generation: 1, nowMs: 10, words: 0, listening: true)
    expectEq(state.flashCleared(seq: first).flash?.id, "b", "un vencimiento viejo no apaga el destello nuevo")
    expectEq(state.flashCleared(seq: state.flashSeq).flash, nil, "el propio si")
}

@Test @MainActor func hidingDropsTheFlashButKeepsTheStackForTheFade() {
    var state = HoldCompanionState().started()
    state = state.receiving([item("a", .copied)], generation: 1, nowMs: 0, words: 0, listening: true)
    state = state.hidden()
    expect(!state.visible, "se oculta")
    expectEq(state.flash, nil, "sin destello")
    expectEq(state.stack.count, 1, "la pila se va con el fundido, no de golpe")
}

@Test @MainActor func theStackWakesAtTheNextLeaveOrDrop() {
    var state = HoldCompanionState().started()
    state = state.receiving([item("a", .copied)], generation: 1, nowMs: 1000, words: 0, listening: true)
    expectEq(state.nextWakeMs(nowMs: 1000), 2400, "despierta a los 1400 ms para sacarlo")
    expectEq(state.nextWakeMs(nowMs: 2400), 2700, "y a los 1700 para borrarlo")
    expectEq(state.pruned(nowMs: 2700).stack.count, 0, "borrado")
    expectEq(state.pruned(nowMs: 2700).nextWakeMs(nowMs: 2700), nil, "sin pila no despierta")
}

@Test @MainActor func theTranscriptCarriesWhatWasHandedOver() {
    var state = HoldCompanionState().started()
    state = state.receiving([item("plan.pdf", .file)], generation: 1, nowMs: 0, words: 1, listening: true)
    expectEq(state.woven("manda esto"), "manda [plan.pdf] esto", "la transcripcion lleva la marca")
}

@Test @MainActor func theCompanionKeepsIncrediblesClocks() {
    expectEq(HoldCompanionMotion.lingerMs, 1200, "queda 1200 ms tras soltar")
    expectEq(HoldCompanionMotion.flashMs, 1100, "el destello dura 1100 ms")
    expectEq(HoldCompanionMotion.appear, .timing(MotionCurve.standard, 0.18), "aparece en 180 ms standard")
    expectEq(HoldCompanionMotion.appearScale, 0.85, "desde 0,85")
    expectEq(HoldCompanionMotion.chipIn, .timing(MotionCurve.bounce, 0.46), "chip entra 460 ms con rebote")
    expectEq(HoldCompanionMotion.chipOut, .timing(MotionCurve.chipExit, 0.26), "y sale en 260 ms")
    expectEq(MotionCurve.chipExit, [0.55, 0, 1, 0.45], "con su curva de salida")
    expectEq(HoldCompanionMotion.chipDrop, 18, "desde 18 pt abajo")
    expectEq(HoldCompanionMotion.chipScale, 0.15, "y a 0,15")
    expectEq(HoldCompanionMotion.slotStep, 31, "31 pt por chip")
    expectEq(HoldCompanionMotion.flashOn, .timing(MotionCurve.standard, 0.16), "la cara del destello entra en 160 ms")
    expectEq(HoldCompanionMotion.flashOff, .timing(MotionCurve.standard, 0.22), "y sale en 220 ms")
    expectEq(HoldCompanionMotion.glyphIn, .timing(MotionCurve.bounce, 0.42), "el glifo entra en 420 ms")
    expectEq(HoldCompanionMotion.glyphOut, .timing(MotionCurve.standard, 0.26), "y sale en 260 ms")
    expectEq(HoldCompanionMotion.gulp, .timing(MotionCurve.bounce, 0.42), "el trago dura 420 ms")
    expectEq(HoldCompanionMotion.gulpDelay, 0.16, "tras 160 ms")
}

// Incredible's companion box sits at the cursor plus (14, 17); its orb is centred 23 pt
// inside, so the orb's centre trails the tip by (37, 40), never under it.
@Test @MainActor func theOrbSitsBelowAndRightOfTheCursorTip() {
    expectEq(PointerOrb.offset, CGSize(width: 14, height: 17), "la caja: cursor mas (14, 17)")
    expectEq(HoldCompanionMetrics.orbCenter, CGPoint(x: 23, y: 23), "el orb, 23 pt dentro de la caja")
    expectEq(HoldCompanionMetrics.pillHeight, 46, "pildora de 46 pt")
    expectEq(HoldCompanionMetrics.orb, 32, "orb de 32 pt")
}

@Test @MainActor func underReduceMotionTheCompanionStaysButNothingBounces() {
    expect(HoldCompanionMotion.animates(reduceMotion: false), "con movimiento: rebotes y destellos")
    expect(!HoldCompanionMotion.animates(reduceMotion: true), "reducido: sin rebotes ni tragos")
    let screen = CGRect(x: 0, y: 0, width: 100, height: 100)
    expect(!PointerOrb.shows(kind: .listening, reduceMotion: true, screen: screen, cursor: CGPoint(x: 5, y: 5)),
           "reducido: el rastro no se dibuja aunque el acompanante si")
}

@Test @MainActor func theLayerStaysMountedWhileHeldOrFading() {
    for listening in [false, true] {
        for mounted in [false, true] {
            expectEq(HoldCompanion.mounts(listening: listening, mounted: mounted), listening || mounted,
                     "montado: escuchando \(listening), montado \(mounted)")
        }
    }
}

// MARK: - Edges of the state

@Test @MainActor func theStateClockFollowsEveryReadAndFlipsAChipAtItsBoundary() {
    var state = HoldCompanionState().started()
    state = state.receiving([item("a", .copied)], generation: 1, nowMs: 1000, words: 0, listening: true)
    expectEq(state.clockMs, 1000, "recibir marca el reloj")
    expect(!HoldStack.leaving(state.stack[0], nowMs: state.pruned(nowMs: 2399).clockMs), "a 1399 ms aun entra")
    expect(HoldStack.leaving(state.stack[0], nowMs: state.pruned(nowMs: 2400).clockMs), "a 1400 ms sale")
    expectEq(state.pruned(nowMs: 2699).stack.count, 1, "a 1699 ms sigue")
    expectEq(state.pruned(nowMs: 2700).stack.count, 0, "a 1700 ms se fue")
}

@Test @MainActor func twoEntriesWakeAtTheEarliestBoundaryAndPruneOnlyTheExpired() {
    var state = HoldCompanionState().started()
    state = state.receiving([item("a", .copied)], generation: 1, nowMs: 0, words: 0, listening: true)
    state = state.receiving([item("a", .copied), item("b", .file)], generation: 1, nowMs: 500, words: 0,
                            listening: true)
    expectEq(state.nextWakeMs(nowMs: 500), 1400, "la primera frontera futura")
    expectEq(state.pruned(nowMs: 1800).stack.map(\.item.id), ["b"], "solo se va el vencido")
}

@Test @MainActor func aResetLetsTheSameItemsCountAgain() {
    var state = HoldCompanionState().started()
    state = state.receiving([item("a", .copied)], generation: 1, nowMs: 0, words: 0, listening: true)
    let afterDictation = state.dictating()
        .receiving([item("a", .copied)], generation: 1, nowMs: 10, words: 0, listening: true)
    expectEq(afterDictation.stack.map(\.item.id), ["a"], "tras dictar, lo mismo vuelve a contar")
    let afterNewHold = state.hidden().started()
        .receiving([item("a", .copied)], generation: 1, nowMs: 10, words: 0, listening: true)
    expectEq(afterNewHold.flashSeq, 1, "en un hold nuevo, lo mismo vuelve a destellar")
}

@Test @MainActor func anOlderItemIsStillSeenSoItNeverFlashesLater() {
    var state = HoldCompanionState().started()
    state = state.receiving([item("new", .window, tMs: 50)], generation: 1, nowMs: 0, words: 0, listening: true)
    state = state.receiving([item("old", .window, tMs: 40)], generation: 1, nowMs: 10, words: 0, listening: true)
    state = state.flashCleared(seq: state.flashSeq)
        .receiving([item("old", .window, tMs: 40)], generation: 1, nowMs: 20, words: 0, listening: true)
    expectEq(state.flash, nil, "lo viejo ya visto no destella despues")
}

// Security review: the view never needs what the user typed or the full address.
@Test @MainActor func theViewStateCarriesNoDetailOrAddress() {
    let typed = HoldItem(id: "t", kind: .typed, label: "pa", detail: "password", tMs: 1)
    let copied = HoldItem(id: "c", kind: .copied, label: "x", detail: "secreto", siteURL: "https://a.com/?t=1", tMs: 2)
    var state = HoldCompanionState().started()
    state = state.receiving([typed], generation: 1, nowMs: 0, words: 0, listening: true)
    expectEq(state.flash?.detail, nil, "el destello no guarda lo tecleado")
    state = state.receiving([typed, copied], generation: 1, nowMs: 0, words: 0, listening: true)
    expect(state.stack.allSatisfy { $0.item.detail == nil && $0.item.siteURL == nil }, "la pila tampoco")
}

@Test @MainActor func anEmptyListOrAFarWordChangesNothingButTheClock() {
    let state = HoldCompanionState().started()
        .receiving([item("a", .file)], generation: 1, nowMs: 0, words: 9, listening: true)
    expectEq(state.woven("uno dos"), "uno dos [a]", "una palabra mas alla va al final")
    let same = state.receiving([], generation: 1, nowMs: 5, words: 0, listening: true)
    expectEq(same.stack, state.stack, "una lista vacia no cambia la pila")
}

// Security review: a long name must stay inside the chip, not run past it.
@Test @MainActor func aChipNeverGrowsPastItsMaximum() {
    let long = HoldItem(id: "f", kind: .file, label: String(repeating: "nombre", count: 60), tMs: 0)
    let wide = NSHostingView(rootView: HoldChip(item: long, leaving: false, animates: false)).fittingSize.width
    expect(wide <= HoldCompanionMetrics.chipMaxWidth + 0.5,
           "un nombre largo mide \(wide), como maximo \(HoldCompanionMetrics.chipMaxWidth)")
    let short = HoldItem(id: "s", kind: .file, label: "a.pdf", tMs: 0)
    let snug = NSHostingView(rootView: HoldChip(item: short, leaving: false, animates: false)).fittingSize.width
    expect(snug < HoldCompanionMetrics.chipMaxWidth / 2, "uno corto se ajusta a su texto (\(snug))")
}

// MARK: - The model's clocks

@MainActor private final class ManualClock {
    private(set) var now = 0
    private var sleepers: [(id: Int, until: Int, resume: CheckedContinuation<Void, Error>)] = []
    private var nextID = 0

    func sleep(_ ms: Int) async throws {
        let id = nextID
        nextID += 1
        let until = now + ms
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (resume: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { resume.resume(throwing: CancellationError()) } else {
                    sleepers.append((id, until, resume))
                }
            }
        } onCancel: {
            Task { @MainActor in self.cancel(id) }
        }
    }

    func advance(by ms: Int) async {
        // Tasks the model just started must register their sleep before time moves.
        for _ in 0..<20 { await Task.yield() }
        now += ms
        let due = sleepers.filter { $0.until <= now }
        sleepers.removeAll { $0.until <= now }
        due.forEach { $0.resume.resume() }
        for _ in 0..<20 { await Task.yield() }
    }

    private func cancel(_ id: Int) {
        guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return }
        sleepers.remove(at: index).resume.resume(throwing: CancellationError())
    }
}

@MainActor private func model() -> (HoldCompanionModel, ManualClock) {
    let clock = ManualClock()
    return (HoldCompanionModel(now: { clock.now }, sleep: { try await clock.sleep($0) }), clock)
}

@Test @MainActor func releasingLingersThenFadesThenUnmounts() async {
    let (companion, clock) = model()
    companion.listening(true)
    companion.listening(false)
    await clock.advance(by: 1199)
    expect(companion.state.visible, "sigue visible hasta los 1200 ms")
    await clock.advance(by: 1)
    expect(!companion.state.visible, "a los 1200 ms empieza a irse")
    expect(companion.state.mounted, "pero sigue montado para el fundido")
    await clock.advance(by: 180)
    expect(!companion.state.mounted, "a los 180 ms del fundido se desmonta")
}

@Test @MainActor func holdingAgainInsideTheLingerKeepsItShown() async {
    let (companion, clock) = model()
    companion.listening(true)
    companion.listening(false)
    await clock.advance(by: 600)
    companion.listening(true)
    await clock.advance(by: 2000)
    expect(companion.state.visible && companion.state.mounted, "un hold nuevo cancela el ocultar")
}

@Test @MainActor func aNewerFlashOutlivesTheOlderOnesClock() async {
    let (companion, clock) = model()
    companion.listening(true)
    companion.receive([item("a", .window, tMs: 1)], generation: 1, words: 0)
    await clock.advance(by: 600)
    companion.receive([item("a", .window, tMs: 1), item("b", .window, tMs: 2)], generation: 1, words: 0)
    await clock.advance(by: 500)
    expectEq(companion.state.flash?.id, "b", "a los 1100 ms del primero, el segundo sigue")
    await clock.advance(by: 600)
    expectEq(companion.state.flash, nil, "a los 1100 ms del segundo se apaga")
}

@Test @MainActor func nothingArrivesOnceTheKeyIsUp() async {
    let (companion, _) = model()
    companion.receive([item("a", .copied)], generation: 1, words: 0)
    expect(companion.state.stack.isEmpty && companion.state.flash == nil,
           "sin tecla no se recoge nada, tampoco en el remanente, como en Incredible")
}

@Test @MainActor func aStackedItemLeavesThenGoesOnTheModelsClock() async {
    let (companion, clock) = model()
    companion.listening(true)
    companion.receive([item("a", .copied)], generation: 1, words: 0)
    await clock.advance(by: 1400)
    expect(HoldStack.leaving(companion.state.stack[0], nowMs: companion.state.clockMs), "a los 1400 ms sale")
    await clock.advance(by: 300)
    expect(companion.state.stack.isEmpty, "a los 1700 ms ya no esta")
}

@Test @MainActor func dictationClearsTheModel() async {
    let (companion, _) = model()
    companion.listening(true)
    companion.receive([item("a", .copied)], generation: 1, words: 0)
    companion.dictating()
    expect(companion.state.stack.isEmpty, "dictar limpia la pila")
}
