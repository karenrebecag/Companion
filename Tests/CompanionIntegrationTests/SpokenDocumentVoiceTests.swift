import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing
import CompanionUITestSupport
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// El documento hablado llega a la isla por las dos puertas de la voz: el
// hold (FN) termina en reposo con la tarjeta, manos libres sigue escuchando
// debajo de ella. En vivo 2026-10-12 ninguna de las dos la mostraba.
// Los snapshots de la voz llegan al modelo de sesion como los lleva
// VoiceViewModel en la app: uno por uno, en orden.

@Test @MainActor func spokenDocumentVoiceTests() async {
    await testAHoldEndsOnTheDocumentCard()
    await testHandsFreeKeepsListeningUnderTheDocumentCard()
}

private let showDocument = ToolCallRef(
    id: "c1", name: SpokenDocument.toolName,
    arguments: #"{"say":"Aquí tienes los pasos.","title":"Pizza","markdown":"1. Masa.\n2. Salsa.\n3. Queso.\n4. Horno.\n5. Servir."}"#)

@MainActor func testAHoldEndsOnTheDocumentCard() async {
    let model = SessionModel(jobs: nil, approvals: nil)
    let h = makeVoiceHarness(session: model)
    h.transcriber.stoppedText = "dame cinco pasos para preparar pizza"
    h.chat.rounds = [[.toolCalls([showDocument])]]
    model.send(.pressed)
    await h.session.hold()
    await pumpUntil("hold doc: listening") { h.watch.latest.state == .listening }
    model.send(.voice(h.watch.latest))
    model.send(.released)
    await h.session.release()
    await pumpUntil("hold doc: la frase suena") { h.synth.queue == ["Aquí tienes los pasos."] }
    expect(h.chat.toolsSeen.map(\.name).contains(SpokenDocument.toolName), "hold doc: la tool viaja")
    await pumpUntil("hold doc: la voz habla") { h.watch.latest.state == .speaking }
    model.send(.voice(h.watch.latest))
    expectEq(model.projection.kind, .processing(.speaking), "hold doc: la isla habla")
    h.synth.yield(.finished)
    await pumpUntil("hold doc: la voz descansa") { h.watch.latest.state == .idle }
    expect(h.watch.latest.hasDocument, "hold doc: el snapshot lleva el documento")
    model.send(.voice(h.watch.latest))
    expectEq(model.projection.kind, .processing(.completed), "hold doc: la isla muestra el documento")
    expectEq(IslandState.from(model.projection, pebbleHidden: false).size, .docCard, "hold doc: la tarjeta")
    expect(h.thread.turns.last { $0.role == .assistant }?.content.contains("5. Servir.") == true,
           "hold doc: el hilo tiene el documento que la tarjeta pinta")
}

@MainActor func testHandsFreeKeepsListeningUnderTheDocumentCard() async {
    let model = SessionModel(jobs: nil, approvals: nil)
    let h = makeVoiceHarness(key: nil, session: model)
    h.transcriber.stoppedText = "dame cinco pasos para preparar pizza"
    h.chat.rounds = [[.toolCalls([showDocument])]]
    await h.session.start()
    await pumpUntil("manos libres doc: listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .classic
    }
    model.send(.voice(h.watch.latest))
    h.mic.yield(MicFrame(pcm16le24k: Data([1, 2, 3, 4]), rms: 0.5))
    await pumpUntil("manos libres doc: el frame llega") { !h.transcriber.appended.isEmpty }
    await h.session.advance()
    await pumpUntil("manos libres doc: la frase suena") { h.synth.queue == ["Aquí tienes los pasos."] }
    await pumpUntil("manos libres doc: la voz habla") { h.watch.latest.state == .speaking }
    model.send(.voice(h.watch.latest))
    h.synth.yield(.finished)
    await pumpUntil("manos libres doc: vuelve a escuchar") {
        h.watch.latest.state == .listening && h.watch.latest.hasDocument
    }
    model.send(.voice(h.watch.latest))
    expectEq(model.projection.kind, .processing(.completed), "manos libres doc: la isla muestra el documento")
    expectEq(IslandState.from(model.projection, pebbleHidden: false).size, .docCard, "manos libres doc: la tarjeta")
    expectEq(model.projection.voice, .live, "manos libres doc: el microfono sigue vivo debajo")
}
