import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Live 2026-10-12: a hold of only "Para." went to the model, which answered
// by describing the screen. A stop ends the turn without calling it.

@Test @MainActor func spokenStopTurnTests() async {
    await testAHoldOfOnlyParaNeverCallsTheModel()
    await testAHoldThatMerelyContainsParaStillGoesToTheModel()
}

@MainActor func testAHoldOfOnlyParaNeverCallsTheModel() async {
    let h = makeVoiceHarness(key: nil)
    h.transcriber.stoppedText = "Para."
    h.chat.rounds = [[.text("¿Qué quieres hacer ahora?")]]
    await h.session.hold()
    await pumpUntil("stop: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await h.session.awaitClassicTurn()
    await pumpUntil("stop: idle") { h.watch.latest.state == .idle }
    expect(h.chat.histories.isEmpty, "stop: el modelo no se llama")
    expect(h.thread.turns.isEmpty, "stop: nada entra al hilo")
}

@MainActor func testAHoldThatMerelyContainsParaStillGoesToTheModel() async {
    let h = makeVoiceHarness(key: nil)
    h.transcriber.stoppedText = "para qué sirve esto"
    h.chat.rounds = [[.text("Para esto.")]]
    await h.session.hold()
    await pumpUntil("para: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("para: chat") { !h.chat.histories.isEmpty }
    await h.session.awaitClassicTurn()
    expect(!h.chat.histories.isEmpty, "para: una pregunta sigue al modelo")
}
