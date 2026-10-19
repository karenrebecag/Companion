import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Una respuesta hablada con documento (show_document) termina en la tarjeta
// del documento, en hold y en manos libres, y se queda lo bastante para
// leerla. La voz y el subtitulo nunca leen markdown.

@Test func speechMarkdownReadsATableRowAsItsCells() {
    let table = "| Modelo | Batería |\n|---|:---:|\n| iPhone 17 | 4 500 mAh |\n| Pixel 10 | 5 200 mAh |"
    expectEq(SpeechMarkdown.plain(table),
             "Modelo, Batería iPhone 17, 4 500 mAh Pixel 10, 5 200 mAh",
             "voz: sin pipes ni fila separadora, cada fila son sus celdas")
}

@Test func speechMarkdownKeepsTheNumberAndAddsTheSpace() {
    let list = "1. Hierve el agua\n3.Vierte el agua\n- **Canela** fresca\n## Paso final"
    expectEq(SpeechMarkdown.plain(list),
             "1. Hierve el agua 3. Vierte el agua Canela fresca Paso final",
             "voz: la numeracion queda con espacio, sin vinetas ni asteriscos")
    expectEq(SpeechMarkdown.plain("3.14 es pi"), "3.14 es pi", "voz: un decimal no es una lista")
}

@Test func speechMarkdownTurnsEveryLineBreakIntoASpace() {
    expectEq(SpeechMarkdown.plain("mAh\nCámara\n\nTriple 48 MP"), "mAh Cámara Triple 48 MP",
             "voz: ninguna palabra se pega al salto de linea")
}

@Test func theTurnKeepsTheDocumentUntilTheVoiceStopsAndDropsItOnTheNextUtterance() {
    var turn = TurnMachine(snapshot: TurnSnapshot(state: .speaking, pipeline: .classic, streamingStarted: true))
    _ = turn.handle(.replyHasDocument, at: 0)
    _ = turn.handle(.replyCompleted, at: 0)
    _ = turn.handle(.speechFinished, at: 0)
    expectEq(turn.snapshot.state, .listening, "manos libres: vuelve a escuchar")
    expect(turn.snapshot.hasDocument, "manos libres: el documento llega hasta el snapshot")
    _ = turn.handle(.advance(hasSpeech: true), at: 1)
    expect(!turn.snapshot.hasDocument, "manos libres: la siguiente frase lo suelta")
}

// En vivo 2026-10-12 (caso 4): la voz leyo las filas de una tabla durante
// 11 s y Karen pulso FN para cortarla; el corte se llevo el documento. El
// contrato hace la frase corta, y este test fija que el corte es un corte.
@Test func aPressWhileTheSentenceStillSoundsCutsTheReplyAndItsDocument() {
    var turn = TurnMachine(snapshot: TurnSnapshot(
        state: .speaking, pipeline: .classic, streamingStarted: true, holdArmed: true))
    _ = turn.handle(.replyHasDocument, at: 0)
    _ = turn.handle(.replyCompleted, at: 0)
    let effects = turn.handle(.holdPressed, at: 1)
    expectEq(turn.snapshot.state, .listening, "corte: la pulsacion reabre el oido")
    expect(effects.contains(.cancelAgentOutput(steer: true)), "corte: la voz se calla")
    expect(!turn.snapshot.hasDocument, "corte: el documento se va con la respuesta cortada")
    var m = SessionMachine()
    _ = m.handle(.voice(TurnSnapshot(state: .speaking, pipeline: .classic, streamingStarted: true)))
    _ = m.handle(.pressed)
    _ = m.handle(.voice(turn.snapshot))
    expectEq(m.projection.kind, .listening, "corte: la isla escucha, no muestra el documento")
}

private func speaking() -> SessionEvent {
    .voice(TurnSnapshot(state: .speaking, pipeline: .classic, streamingStarted: true))
}

@Test func aSpokenDocumentEndsOnTheCompletedDocumentCardInAHold() {
    var m = SessionMachine()
    _ = m.handle(speaking())
    let fx = m.handle(.voice(TurnSnapshot(state: .idle, hasDocument: true)))
    expectEq(m.projection.kind, .processing(.completed), "hold: termina en completed")
    expect(fx.contains(.cancelCompletedExpiry), "hold: un documento no tiene reloj, se queda hasta la x")
    let island = IslandState.from(m.projection, pebbleHidden: false)
    expectEq(island.size, .docCard, "hold: la tarjeta del documento")
    expectEq(island.line, .completed, "hold: la linea de terminado")
    _ = m.handle(.resultDismissed)
    expectEq(m.projection.kind, .idle, "hold: la x lo despide")
}

@Test func aShortSpokenReplyGoesStraightToRest() {
    var m = SessionMachine()
    _ = m.handle(speaking())
    _ = m.handle(.voice(TurnSnapshot(state: .idle)))
    expectEq(m.projection.kind, .idle, "voz corta: directo a reposo")
}

@Test func handsFreeKeepsListeningUnderTheCardAndANewUtteranceReplacesIt() {
    var m = SessionMachine()
    _ = m.handle(speaking())
    _ = m.handle(.voice(TurnSnapshot(state: .listening, pipeline: .classic, hasDocument: true)))
    expectEq(m.projection.kind, .processing(.completed), "manos libres: la tarjeta queda")
    expectEq(m.projection.voice, .live, "manos libres: el microfono sigue vivo")
    expectEq(IslandState.from(m.projection, pebbleHidden: false).size, .docCard,
             "manos libres: la tarjeta del documento")
    _ = m.handle(.voice(TurnSnapshot(state: .listening, pipeline: .classic)))
    expectEq(m.projection.kind, .processing(.completed), "manos libres: otro snapshot no la pisa")
    _ = m.handle(.partialTranscript("y ahora"))
    expectEq(m.projection.kind, .listening, "manos libres: la frase nueva la reemplaza")
    expectEq(m.projection.partial, "y ahora", "manos libres: con sus palabras")
}

@Test func handsFreeCardExpiryReturnsToListeningNotRest() {
    var m = SessionMachine()
    _ = m.handle(speaking())
    _ = m.handle(.voice(TurnSnapshot(state: .listening, pipeline: .classic, hasDocument: true)))
    _ = m.handle(.completedTimerExpired)
    expectEq(m.projection.kind, .listening, "manos libres: al expirar sigue escuchando")
}

// En vivo 2026-10-12: la frase de entrada termino de sonar antes de que la
// respuesta acabara de llegar; la marca llego con la voz en reposo.
@Test func theDocumentMarkArrivingAfterTheVoiceIsDoneStillLandsTheCard() {
    var turn = TurnMachine(snapshot: TurnSnapshot(state: .idle, pipeline: .classic))
    _ = turn.handle(.replyHasDocument, at: 0)
    expect(turn.snapshot.hasDocument, "turno: la marca vale aunque la voz ya callo")
    var m = SessionMachine()
    _ = m.handle(speaking())
    _ = m.handle(.voice(TurnSnapshot(state: .idle)))
    expectEq(m.projection.kind, .idle, "voz: primero en reposo")
    _ = m.handle(.voice(turn.snapshot))
    expectEq(m.projection.kind, .processing(.completed), "documento tardio: termina en la tarjeta")
}

// En vivo 2026-10-13: el documento llegaba al terminar la frase y, mientras
// tanto, el subtitulo leia la cola del documento. Sube en cuanto existe.
@Test func theDocumentGoesUpWhileTheVoiceSaysItsSentenceAndStaysAfter() {
    var m = SessionMachine()
    _ = m.handle(.voice(TurnSnapshot(state: .speaking, pipeline: .classic, streamingStarted: true)))
    let fx = m.handle(.voice(TurnSnapshot(state: .speaking, pipeline: .classic, streamingStarted: true, hasDocument: true)))
    expectEq(m.projection.kind, .processing(.completed), "documento: sube mientras la voz habla")
    expect(fx.contains(.cancelCompletedExpiry), "documento: sin reloj, se queda hasta la x")
    _ = m.handle(.voice(TurnSnapshot(state: .speaking, pipeline: .classic, streamingStarted: true, hasDocument: true)))
    expectEq(m.projection.kind, .processing(.completed), "documento: otro tick de la voz no lo baja")
    _ = m.handle(.voice(TurnSnapshot(state: .idle, hasDocument: true)))
    expectEq(m.projection.kind, .processing(.completed), "documento: sigue cuando la voz calla")
}
