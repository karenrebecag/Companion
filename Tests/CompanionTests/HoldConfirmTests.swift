import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Code review 2026-09-24 of Wave 15d. FN opens the mic on the way down, so
// a tap now reaches the session. The rule: on key-down only LOCAL,
// REVERSIBLE things start (mic, HoldAudioBuffer, Apple's ear); anything
// that leaves the machine or cuts a turn in flight waits for the tap
// threshold (`confirmHold`), and a tap before it is dropped quietly.

@Test @MainActor func holdConfirmTests() async {
    await testATapNeverUploadsTheScreen()
    await testAConfirmedHoldUploadsTheScreenOnce()
    await testAReleaseBeforeTheConfirmStillCountsAsConfirmed()
    await testATapDuringAReplyLetsItFinish()
    await testAConfirmedHoldDuringAReplyStillSteers()
    await testAStaleTeardownNeverKillsTheNextHold()
    await testACancelledSilentTurnNeverTearsDownTheNextHold()
    await testATapInsideTheTailCommitsThePendingRelease()
    await testADiscardInsideTheTailCancelsTheCommit()
    await testAPressInsideTheTailKeepsTheWordsHeardSoFar()
    await testPointingStartsOnEveryPipeline()
}

/// Code review 16o (HIGH): pointing is local Accessibility, not vision, so
/// the no-key pipeline samples it too; vision still waits for a key.
@MainActor func testPointingStartsOnEveryPipeline() async {
    for key in [String?.none, "sk-test"] {
        let screen = FakeScreenSeeing()
        let h = makeVoiceHarness(key: key, screen: screen)
        await h.session.hold(provisional: true)
        await pumpUntil("señalar: listening") { h.watch.latest.state == .listening }
        expectEq(screen.pointings, 0, "señalar: un toque no muestrea")
        await h.session.confirmHold()
        expectEq(screen.pointings, 1, "señalar: muestrea al confirmar (clave: \(key != nil))")
        expectEq(screen.begins, key == nil ? 0 : 1, "señalar: la visión sigue exigiendo clave")
        await h.session.discard()
    }
}

// MARK: - 1. Nothing leaves the machine on a tap

@MainActor func testATapNeverUploadsTheScreen() async {
    let screen = FakeScreenSeeing()
    let h = makeVoiceHarness(screen: screen)
    await h.session.hold(provisional: true)
    await pumpUntil("tap: listening") { h.watch.latest.state == .listening }
    expect(h.mic.started, "tap: el micro sí abre al bajar (local)")
    expectEq(screen.begins, 0, "tap: la captura espera al umbral")
    await h.session.discard()
    await settle(0.05)
    expectEq(screen.begins, 0, "tap: ninguna captura viaja a la visión")
}

@MainActor func testAConfirmedHoldUploadsTheScreenOnce() async {
    let screen = FakeScreenSeeing()
    let h = makeVoiceHarness(screen: screen)
    await h.session.hold(provisional: true)
    await pumpUntil("confirmado: listening") { h.watch.latest.state == .listening }
    await h.session.confirmHold()
    expectEq(screen.begins, 1, "confirmado: la captura arranca al umbral")
    await h.session.confirmHold()
    expectEq(screen.begins, 1, "confirmado: un segundo confirm no repite")
}

/// The threshold timer and the key-up race: a release past the threshold
/// is a hold by definition, even if its `confirmed` never arrived.
@MainActor func testAReleaseBeforeTheConfirmStillCountsAsConfirmed() async {
    let screen = FakeScreenSeeing()
    let h = makeVoiceHarness(screen: screen)
    h.transcriber.stoppedText = "qué hay en pantalla"
    h.chat.rounds = [[.text("Nada.")]]
    await h.session.hold(provisional: true)
    await pumpUntil("carrera: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("carrera: el turno viaja") { !h.chat.histories.isEmpty }
    expectEq(screen.begins, 1, "carrera: soltar confirma antes de enviar")
}

// MARK: - 2. A tap during a reply never cuts it

/// Hold, release, and let the reply start speaking.
@MainActor private func speakingHarness() async -> VoiceHarness {
    let h = makeVoiceHarness()
    h.transcriber.stoppedText = "cuéntame algo"
    h.chat.rounds = [[.text("Te cuento algo largo, con calma.")]]
    await h.session.hold()
    await pumpUntil("respuesta: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("respuesta: speaking") { h.watch.latest.state == .speaking }
    await h.session.awaitClassicTurn()
    return h
}

@MainActor func testATapDuringAReplyLetsItFinish() async {
    let h = await speakingHarness()
    let starts = h.mic.startCount
    await h.session.hold(provisional: true)
    await h.session.discard()
    await settle(0.05)
    expectEq(h.watch.latest.state, .speaking, "tap en respuesta: sigue hablando")
    expect(!h.synth.stopped, "tap en respuesta: la voz no se corta")
    expect(!h.watch.latest.interruptionPending, "tap en respuesta: sin nota de steer")
    expectEq(h.mic.startCount, starts, "tap en respuesta: el micro no vuelve a arrancar")
}

@MainActor func testAConfirmedHoldDuringAReplyStillSteers() async {
    let h = await speakingHarness()
    await h.session.hold(provisional: true)
    await settle(0.03)
    expectEq(h.watch.latest.state, .speaking, "steer: bajo el umbral todavía habla")
    await h.session.confirmHold()
    await pumpUntil("steer: al umbral corta y escucha") { h.watch.latest.state == .listening }
    expect(h.synth.stopped, "steer: la voz se corta")
    expect(h.watch.latest.interruptionPending, "steer: queda la nota para el siguiente turno")
}

// MARK: - 3. A stale teardown belongs to its own listen

/// Tap A's listen arrives after its cancel and is torn down; the ear's
/// stop waits up to 300 ms for a final. Hold B starts inside that wait.
@MainActor func testAStaleTeardownNeverKillsTheNextHold() async {
    let h = makeVoiceHarness()
    h.mic.startDelay = 0.1
    h.transcriber.stopDelay = 0.3
    let tapA = Task { await h.session.hold(provisional: true) }
    await settle(0.03)
    await h.session.discard()
    await pumpUntil("tap A: su escucha tardía se desmonta") { h.transcriber.stops >= 1 }
    await h.session.hold()
    await pumpUntil("hold B: listening") { h.watch.latest.state == .listening }
    await tapA.value
    await settle(0.35)
    expectEq(h.watch.latest.state, .listening, "hold B: sigue escuchando")
    expect(!h.mic.stopped, "hold B: el desmontaje de A no apaga su micro")
    expect(h.transcriber.running, "hold B: ni su reconocedor")
}

// MARK: - 5. A cancelled turn that heard nothing stays quiet

@MainActor func testACancelledSilentTurnNeverTearsDownTheNextHold() async {
    let h = makeVoiceHarness()
    let seen = SessionEventBox(h.session.events)
    h.transcriber.stoppedText = ""
    h.transcriber.stopDelay = 0.3
    await h.session.hold()
    await pumpUntil("silencio A: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("silencio A: el oído final corre") { h.transcriber.stops >= 1 }
    await h.session.hold()
    await pumpUntil("B: listening") { h.watch.latest.state == .listening }
    await settle(0.45)
    expectEq(h.watch.latest.state, .listening, "B: sigue escuchando")
    expect(!h.mic.stopped, "B: su micro sigue abierto")
    expect(!seen.events.contains { $0 == .heardNothing }, "A: cortado, sin «no te oí»")
}

// MARK: - 6, 10, 12. The release tail

@MainActor func testATapInsideTheTailCommitsThePendingRelease() async {
    let h = makeVoiceHarness(releaseTail: 0.5)
    let seen = SessionEventBox(h.session.events)
    h.transcriber.stoppedText = "abre Safari"
    h.chat.rounds = [[.text("Listo.")]]
    await h.session.hold()
    await pumpUntil("cola+tap: listening") { h.watch.latest.state == .listening }
    h.clock.now = 5
    let release = Task { await h.session.release() }
    await pumpUntilAsync("cola+tap: soltó") { await h.session.timeline.released != nil }
    h.clock.now = 5.2
    await h.session.hold(provisional: true)
    await h.session.discard()
    await release.value
    await pumpUntil("cola+tap: la frase de A viaja") { !h.chat.histories.isEmpty }
    expectEq(h.chat.histories.count, 1, "cola+tap: una sola vez")
    expect(!seen.events.contains { $0 == .heardNothing }, "cola+tap: sin «no te oí»")
}

@MainActor func testADiscardInsideTheTailCancelsTheCommit() async {
    let h = makeVoiceHarness(releaseTail: 0.5)
    h.transcriber.stoppedText = "borra todo"
    h.chat.rounds = [[.text("Listo.")]]
    await h.session.hold()
    await pumpUntil("cola+stop: listening") { h.watch.latest.state == .listening }
    let release = Task { await h.session.release() }
    await pumpUntilAsync("cola+stop: soltó") { await h.session.timeline.released != nil }
    await h.session.discard()
    await release.value
    await settle(0.1)
    expect(h.chat.histories.isEmpty, "cola+stop: Esc en la cola no envía")
    expectEq(h.watch.latest.state, .idle, "cola+stop: a reposo")
    expect(h.mic.stopped, "cola+stop: micro apagado")
}

@MainActor func testAPressInsideTheTailKeepsTheWordsHeardSoFar() async {
    let h = makeVoiceHarness(releaseTail: 0.5)
    await h.session.hold()
    await pumpUntil("cola+press: listening") { h.watch.latest.state == .listening }
    h.transcriber.yieldPartial("abre Safari")
    let release = Task { await h.session.release() }
    await pumpUntilAsync("cola+press: soltó") { await h.session.timeline.released != nil }
    await h.session.hold()
    await release.value
    let text = await h.session.audit.turnText()
    expectEq(text, "abre Safari", "cola+press: lo oído antes de la cola sigue siendo de este hold")
}
