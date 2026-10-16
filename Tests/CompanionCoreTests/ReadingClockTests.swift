import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Un resultado con contenido no se cierra con reloj: se queda hasta la x, Esc o
// la siguiente interacción. Solo un recibo (una línea corta) se cierra solo.

private func typedReply(_ machine: inout SessionMachine, reply: String?) -> [SessionEffect] {
    _ = machine.handle(.typedSubmitted)
    if let reply, let kind = ReadingClock.kind(of: reply) { _ = machine.handle(.replyMeasured(kind)) }
    return machine.handle(.typedReplyFinished)
}

private func armsAClock(_ effects: [SessionEffect]) -> Bool {
    effects.contains { if case .scheduleCompletedExpiry = $0 { true } else { false } }
}

@Test func aOneLineStatusIsAReceiptAndAnythingElseIsContent() {
    expectEq(ReadingClock.kind(of: "Listo"), .receipt, "recibo: una palabra")
    expectEq(ReadingClock.kind(of: "Abrí Notas"), .receipt, "recibo: una línea corta")
    expectEq(ReadingClock.kind(of: "Dos\n\nPárrafos"), .content, "contenido: dos bloques")
    expectEq(ReadingClock.kind(of: "- uno\n- dos"), .content, "contenido: una lista")
    expectEq(ReadingClock.kind(of: String(repeating: "palabra ", count: 16)), .content,
             "contenido: más de quince palabras")
    expect(ReadingClock.kind(of: " \n ") == nil, "sin nada que leer no hay clasificación")
}

@Test func theReceiptClockWaitsForTheVoiceOrTheSilentWaitThenHoldsUnderTheCap() {
    expectEq(ReadingClock.receiptDelay(voiced: true), 1.5, "recibo con voz: 1,5 s tras la voz")
    expectEq(ReadingClock.receiptDelay(voiced: false), 7.5, "recibo mudo: 6 s de espera y 1,5 s")
    expect(ReadingClock.receiptDelay(voiced: false) <= ReadingClock.cap, "recibo: nunca pasa del tope")
}

@Test func aContentReplyStaysUntilClosedByHand() {
    var m = SessionMachine()
    let fx = typedReply(&m, reply: "## Plan\n\nPaso uno.\n\nPaso dos.")
    expect(fx.contains(.cancelCompletedExpiry), "contenido: ningún reloj")
    expect(!armsAClock(fx), "contenido: no se arma ninguno")
    expectEq(m.projection.kind, .processing(.completed), "contenido: la tarjeta espera")
    let closed = m.handle(.resultDismissed)
    expectEq(m.projection.kind, .idle, "contenido: la x la cierra")
    expect(closed.contains(.islandEvent(.closed(.result))), "contenido: el modelo se entera de que la cerró ella")
}

@Test func aReceiptArmsItsClockAndThePointerHoldsIt() {
    var m = SessionMachine()
    let fx = typedReply(&m, reply: "Listo")
    expect(fx.contains(.scheduleCompletedExpiry(ReadingClock.receiptDelay(voiced: false), floor: ReadingClock.hold)),
           "recibo: su reloj de siete segundos y medio")
    expectEq(m.handle(.peeked), [.pauseCompletedExpiry], "recibo: la mano lo pausa")
    expect(m.handle(.peekLeft).contains(.resumeCompletedExpiry), "recibo: al salir sigue desde el piso")
    _ = m.handle(.completedTimerExpired)
    expectEq(m.projection.kind, .idle, "recibo: cumplido el reloj, se va")
}

@Test func dismissingOutsideAResultDoesNothing() {
    var m = SessionMachine()
    _ = m.handle(.typedSubmitted)
    expectEq(m.handle(.resultDismissed), [], "cierre manual: sin tarjeta no hay nada que cerrar")
    expectEq(m.projection.kind, .processing(.thinking), "cierre manual: el turno sigue")
}

@Test func aPointerAlreadyThereStartsTheNextReceiptPaused() {
    var m = SessionMachine()
    _ = m.handle(.peeked)
    let fx = typedReply(&m, reply: "Listo")
    expect(fx.contains(.pauseCompletedExpiry), "recibo: el que llega bajo el puntero nace pausado")
}

@Test func aNewTurnReplacesTheCardAndANoticeKeepsBlocking() {
    var m = SessionMachine()
    _ = typedReply(&m, reply: "Listo")
    _ = m.handle(.typedSubmitted)
    expectEq(m.projection.kind, .processing(.thinking), "turno nuevo: reemplaza la tarjeta")
    _ = m.handle(.completedTimerExpired)
    expectEq(m.projection.kind, .processing(.thinking), "turno nuevo: el reloj viejo no lo arrastra a reposo")

    var blocked = SessionMachine()
    _ = blocked.handle(.typedSubmitted)
    _ = blocked.handle(.replyMeasured(.receipt))
    _ = blocked.handle(.connectAppSuggested(slug: "notion", name: "Notion"))
    expect(!armsAClock(blocked.handle(.typedReplyFinished)), "aviso: con un aviso en pantalla no se arma solo")
}

@Test func aSpokenReceiptLandsWithTheClockThatStartsWhenTheVoiceStops() {
    var m = SessionMachine()
    _ = m.handle(.voice(TurnSnapshot(state: .speaking, pipeline: .classic, streamingStarted: true)))
    _ = m.handle(.replyMeasured(.receipt))
    let fx = m.handle(.voice(TurnSnapshot(state: .idle)))
    expectEq(m.projection.kind, .processing(.completed), "voz: la respuesta de una línea también aterriza")
    expect(fx.contains(.scheduleCompletedExpiry(ReadingClock.receiptDelay(voiced: true), floor: ReadingClock.hold)),
           "voz: el reloj arranca cuando la voz para")
}

@Test func aVoiceReplyNobodyMeasuredStillGoesStraightToRest() {
    var m = SessionMachine()
    _ = m.handle(.voice(TurnSnapshot(state: .speaking, pipeline: .classic, streamingStarted: true)))
    _ = m.handle(.voice(TurnSnapshot(state: .idle)))
    expectEq(m.projection.kind, .idle, "voz: sin medida no hay nada que leer")
}

@Test func aJobAnswerMeasuredAfterItsEndReArmsTheCardAsAReceipt() {
    var m = SessionMachine()
    let first = typedReply(&m, reply: nil)
    expect(first.contains(.scheduleCompletedExpiry(SessionMachine.settleDelay, floor: SessionMachine.settleFloor)),
           "tarea: sin medida corre el asentamiento corto")
    let fx = m.handle(.replyMeasured(.receipt))
    expect(fx.contains(.scheduleCompletedExpiry(ReadingClock.receiptDelay(voiced: false), floor: ReadingClock.hold)),
           "tarea: la medida tardía rearma como recibo")
}
