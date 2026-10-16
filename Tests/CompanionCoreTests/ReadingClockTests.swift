import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// La tarjeta de resultado se cerraba a los 0,2 s de responder: una respuesta de
// 1081 caracteres pasó de docCard a pebble en 289 ms (en vivo, 2026-10-16). Se
// queda el tiempo de leerla, se pausa con la mano encima y se cierra a mano.

private func typedReply(_ machine: inout SessionMachine, load: ReadingLoad?) -> [SessionEffect] {
    _ = machine.handle(.typedSubmitted)
    if let load { _ = machine.handle(.replyMeasured(load)) }
    return machine.handle(.typedReplyFinished)
}

private let short = ReadingLoad(words: 20, rows: 0)

@Test func theReadingTimeGrowsWithTheReplyAndStaysInsideItsBounds() {
    expectEq(ReadingClock.duration(for: ReadingLoad(words: 3, rows: 0)), 4, "lectura: lo corto tiene piso de 4 s")
    let twenty = ReadingClock.duration(for: short) ?? 0
    expect(abs(twenty - (2.5 + 0.28 * 20)) < 1e-9, "lectura: 2,5 s + 0,28 s por palabra")
    let withRows = ReadingClock.duration(for: ReadingLoad(words: 20, rows: 5)) ?? 0
    expect(abs(withRows - twenty - 2) < 1e-9, "lectura: 0,4 s por fila")
    expectEq(ReadingClock.duration(for: ReadingLoad(words: 170, rows: 0)), 20, "lectura: techo de 20 s")
}

@Test func aCardThatNeedsScrollHasNoClock() {
    expectEq(ReadingClock.duration(for: ReadingLoad(words: 400, rows: 0, needsScroll: true)), nil,
             "lectura: lo que pide scroll se cierra a mano")
    let long = String(repeating: "Una frase de relleno para llenar la columna entera. ", count: 60)
    expectEq(ReadingClock.load(of: long)?.needsScroll, true, "lectura: la medida detecta el desbordamiento")
    let thousand = String(repeating: "palabra ", count: 135)
    expectEq(ReadingClock.load(of: thousand)?.needsScroll, false, "lectura: 1081 caracteres caben sin scroll")
    expect(ReadingClock.load(of: "") == nil, "lectura: sin nada que leer no hay medida")
}

@Test func aTypedReplyStaysForItsReadingTimeNotTheShortSettle() {
    var m = SessionMachine()
    let fx = typedReply(&m, load: short)
    expect(fx.contains(.scheduleCompletedExpiry(readTime, floor: SessionMachine.settleFloor)),
           "tarjeta: el reloj es el de lectura")
    expect(!fx.contains(.scheduleCompletedExpiry(SessionMachine.settleDelay, floor: SessionMachine.settleFloor)),
           "tarjeta: el asentamiento de 0,2 s ya no cierra un resultado")
}

@Test func aReplyThatNeedsScrollArmsNoClockAndTheCrossClosesIt() {
    var m = SessionMachine()
    let fx = typedReply(&m, load: ReadingLoad(words: 400, rows: 0, needsScroll: true))
    expect(fx.contains(.cancelCompletedExpiry), "cierre manual: no queda ningún reloj")
    expect(!fx.contains { if case .scheduleCompletedExpiry = $0 { true } else { false } },
           "cierre manual: y no se arma ninguno")
    expectEq(m.projection.kind, .processing(.completed), "cierre manual: la tarjeta espera")
    let closed = m.handle(.resultDismissed)
    expectEq(m.projection.kind, .idle, "cierre manual: la x la cierra")
    expect(closed.contains(.islandEvent(.closed(.result))), "cierre manual: el modelo se entera de que la cerró ella")
}

@Test func dismissingOutsideAResultDoesNothing() {
    var m = SessionMachine()
    _ = m.handle(.typedSubmitted)
    expectEq(m.handle(.resultDismissed), [], "cierre manual: sin tarjeta no hay nada que cerrar")
    expectEq(m.projection.kind, .processing(.thinking), "cierre manual: el turno sigue")
}

@Test func theHandPausesTheClockFromThePeekAndLeavingKeepsTheFloor() {
    var m = SessionMachine()
    _ = typedReply(&m, load: short)
    expectEq(m.handle(.peeked), [.pauseCompletedExpiry], "mano: el peek pausa sin esperar el dwell")
    expectEq(m.handle(.peeked), [], "mano: un segundo peek no cambia nada")
    expect(m.handle(.peekLeft).contains(.resumeCompletedExpiry), "mano: al salir sigue desde el piso")
    _ = m.handle(.completedTimerExpired)
    expectEq(m.projection.kind, .idle, "mano: cumplido el reloj, se va")
}

@Test func aPointerAlreadyThereStartsTheNextCardPaused() {
    var m = SessionMachine()
    _ = m.handle(.peeked)
    let fx = typedReply(&m, load: short)
    expect(fx.contains(.pauseCompletedExpiry), "mano: la tarjeta que llega bajo el puntero nace pausada")
}

@Test func aNewTurnReplacesTheCardAndANoticeKeepsBlocking() {
    var m = SessionMachine()
    _ = typedReply(&m, load: short)
    _ = m.handle(.typedSubmitted)
    expectEq(m.projection.kind, .processing(.thinking), "turno nuevo: reemplaza la tarjeta")
    let late = m.handle(.completedTimerExpired)
    expectEq(m.projection.kind, .processing(.thinking), "turno nuevo: el reloj viejo no lo arrastra a reposo (\(late.count))")

    var blocked = SessionMachine()
    _ = blocked.handle(.typedSubmitted)
    _ = blocked.handle(.replyMeasured(short))
    _ = blocked.handle(.connectAppSuggested(slug: "notion", name: "Notion"))
    let fx = blocked.handle(.typedReplyFinished)
    expect(!fx.contains { if case .scheduleCompletedExpiry = $0 { true } else { false } },
           "aviso: con un aviso en pantalla la tarjeta no se arma sola")
}

@Test func aSpokenReplyWithoutADocumentLandsOnTheCardWithTheSameClock() {
    var m = SessionMachine()
    _ = m.handle(.voice(TurnSnapshot(state: .speaking, pipeline: .classic, streamingStarted: true)))
    _ = m.handle(.replyMeasured(short))
    let fx = m.handle(.voice(TurnSnapshot(state: .idle)))
    expectEq(m.projection.kind, .processing(.completed), "voz: la respuesta sin documento también aterriza")
    expect(fx.contains(.scheduleCompletedExpiry(readTime, floor: SessionMachine.settleFloor)),
           "voz: con el reloj de lectura")
    _ = m.handle(.completedTimerExpired)
    expectEq(m.projection.kind, .idle, "voz: el reloj la despide")
}

@Test func aVoiceReplyNobodyMeasuredStillGoesStraightToRest() {
    var m = SessionMachine()
    _ = m.handle(.voice(TurnSnapshot(state: .speaking, pipeline: .classic, streamingStarted: true)))
    _ = m.handle(.voice(TurnSnapshot(state: .idle)))
    expectEq(m.projection.kind, .idle, "voz: sin medida no hay nada que leer")
}

@Test func aJobAnswerMeasuredAfterItsEndReArmsTheCardWithItsRealLength() {
    var m = SessionMachine()
    let first = typedReply(&m, load: nil)
    expect(first.contains(.scheduleCompletedExpiry(SessionMachine.settleDelay, floor: SessionMachine.settleFloor)),
           "tarea: sin medida corre el asentamiento corto")
    let fx = m.handle(.replyMeasured(short))
    expect(fx.contains(.scheduleCompletedExpiry(readTime, floor: SessionMachine.settleFloor)),
           "tarea: la medida tardía rearma con la longitud real")
}

// The same arithmetic the reducer does, so floating point never decides a test.
private let readTime = ReadingClock.duration(for: ReadingLoad(words: 20, rows: 0)) ?? 0
