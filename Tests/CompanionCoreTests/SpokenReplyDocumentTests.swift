import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Una respuesta hablada con tabla, lista o texto largo termina en la tarjeta
// del documento, y la voz y el subtitulo no leen el markdown.

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

@Test func richnessFollowsTableListParagraphsAndLength() {
    expect(ReplyRichness.isRich("| a | b |\n|---|---|\n| 1 | 2 |"), "rica: tabla")
    expect(ReplyRichness.isRich("1. uno\n2. dos\n3. tres"), "rica: lista de tres")
    expect(ReplyRichness.isRich("Primero esto.\n\nLuego aquello."), "rica: dos parrafos")
    expect(ReplyRichness.isRich(String(repeating: "palabra ", count: 60)), "rica: larga")
    expect(!ReplyRichness.isRich("Son las 3 en Tokio."), "corta: no es rica")
    expect(!ReplyRichness.isRich("- uno\n- dos"), "corta: dos items no son lista")
}

@Test func theTurnKeepsRichUntilTheVoiceStopsAndDropsItOnTheNextUtterance() {
    var turn = TurnMachine(snapshot: TurnSnapshot(state: .speaking, pipeline: .classic, streamingStarted: true))
    _ = turn.handle(.replyIsRich, at: 0)
    _ = turn.handle(.replyCompleted, at: 0)
    _ = turn.handle(.speechFinished, at: 0)
    expectEq(turn.snapshot.state, .listening, "manos libres: vuelve a escuchar")
    expect(turn.snapshot.richReply, "manos libres: la respuesta rica llega hasta el snapshot")
    _ = turn.handle(.advance(hasSpeech: true), at: 1)
    expect(!turn.snapshot.richReply, "manos libres: la siguiente frase la suelta")
}

private func speaking() -> SessionEvent {
    .voice(TurnSnapshot(state: .speaking, pipeline: .classic, streamingStarted: true))
}

@Test func aRichSpokenReplyEndsOnTheCompletedDocumentCard() {
    var m = SessionMachine()
    _ = m.handle(speaking())
    let fx = m.handle(.voice(TurnSnapshot(state: .idle, richReply: true)))
    expectEq(m.projection.kind, .processing(.completed), "voz rica: termina en completed")
    expect(fx.contains(.scheduleCompletedExpiry(SessionMachine.settleDelay, floor: SessionMachine.settleFloor)),
           "voz rica: se cierra como la tecleada")
    let island = IslandState.from(m.projection, pebbleHidden: false)
    expectEq(island.size, .docCard, "voz rica: la tarjeta del documento")
    expectEq(island.line, .completed, "voz rica: la linea de terminado")
    _ = m.handle(.completedTimerExpired)
    expectEq(m.projection.kind, .idle, "voz rica: el timer la despide")
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
    _ = m.handle(.voice(TurnSnapshot(state: .listening, pipeline: .classic, richReply: true)))
    expectEq(m.projection.kind, .processing(.completed), "manos libres: la tarjeta queda")
    expectEq(m.projection.voice, .live, "manos libres: el microfono sigue vivo")
    _ = m.handle(.voice(TurnSnapshot(state: .listening, pipeline: .classic)))
    expectEq(m.projection.kind, .processing(.completed), "manos libres: otro snapshot no la pisa")
    _ = m.handle(.partialTranscript("y ahora"))
    expectEq(m.projection.kind, .listening, "manos libres: la frase nueva la reemplaza")
    expectEq(m.projection.partial, "y ahora", "manos libres: con sus palabras")
}

@Test func handsFreeCardExpiryReturnsToListeningNotRest() {
    var m = SessionMachine()
    _ = m.handle(speaking())
    _ = m.handle(.voice(TurnSnapshot(state: .listening, pipeline: .classic, richReply: true)))
    _ = m.handle(.completedTimerExpired)
    expectEq(m.projection.kind, .listening, "manos libres: al expirar sigue escuchando")
}
