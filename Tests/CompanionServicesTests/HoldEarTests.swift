import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Wave 15d. El oído completo: el micro abre al bajar la tecla, un tap no
// envía nada, la cola de 300 ms al soltar, un hold sin voz vuelve a reposo
// con el micro apagado, y la línea de tiempos separa oído, cerebro y boca.

@Test @MainActor func holdEarTests() async {
    await testTheEarFinalIsMarkedOnTheTimeline()
    await testATapOpensTheMicAndDropsItSilently()
    await testFramesBeforeTheEarIsUpStillReachTheEar()
    await testATapWhileTheMicComesUpLeavesItOff()
    await testAReleaseWhileTheMicComesUpLeavesItOff()
    await testTheTailKeepsFeedingTheEarsThenCommits()
    await testAPressDuringTheTailCommitsOnce()
}

/// 15d-0: the ear's final is marked when it lands, apart from
/// the commit — `release→earFinal` is the ear's own share of the wait.
@MainActor func testTheEarFinalIsMarkedOnTheTimeline() async {
    let h = makeVoiceHarness()
    h.transcriber.stoppedText = "abre Safari"
    h.chat.rounds = [[.text("Listo.")]]
    h.clock.now = 50
    await h.session.hold()
    await pumpUntil("earFinal: listening") { h.watch.latest.state == .listening }
    speak(h, frames: 3)
    await pumpUntil("earFinal: frames") { h.transcriber.appended.count >= 3 }
    h.clock.now = 51
    await h.session.release()
    await pumpUntil("earFinal: el turno viaja") { !h.chat.histories.isEmpty }
    await h.session.awaitClassicTurn()
    expectEq(await h.session.timeline.earFinal, 51, "earFinal: marcado cuando llega el texto final")
}

/// 15d-1 (TDD row 1): FN down 100 ms and up. The mic opened at the press;
/// the cancel closes it, sends nothing, and never says "no te oí".
@MainActor func testATapOpensTheMicAndDropsItSilently() async {
    let h = makeVoiceHarness()
    h.transcriber.stoppedText = "ruido"
    let seen = SessionEventBox(h.session.events)
    await h.session.hold()
    expect(h.mic.started, "tap: el micro arrancó al bajar")
    speak(h, frames: 3)
    await pumpUntil("tap: frames") { h.transcriber.appended.count >= 3 }
    await h.session.discard()
    await pumpUntil("tap: a reposo") { h.watch.latest.state == .idle }
    await settle(0.05)
    expect(h.mic.stopped, "tap: el micro se apaga")
    expect(h.chat.histories.isEmpty, "tap: nada viaja al cerebro")
    expect(!seen.events.contains { $0 == .heardNothing }, "tap: sin «no te oí»")
}

/// 15d-1 (TDD row 2), 15e-1 (spec §4 row 1): the mic is up before the
/// on-device ear is; what it hears in that gap is the first word, and with
/// the cloud ear gone the ear itself must get it — first, and in order.
@MainActor func testFramesBeforeTheEarIsUpStillReachTheEar() async {
    let h = makeVoiceHarness()
    h.transcriber.stoppedText = "abre Safari"
    h.chat.rounds = [[.text("Listo.")]]
    h.transcriber.startDelay = 0.3
    let press = Task { await h.session.hold() }
    await pumpUntil("primeras: el micro arrancó") { h.mic.started }
    speak(h, frames: 3, byte: 0x7A)
    await press.value
    await pumpUntil("primeras: listening") { h.watch.latest.state == .listening }
    speak(h, frames: 3, byte: 0x11)
    // No release tail here: the live frames must reach the ear before the
    // release stops it, or the fake (like the real ear) drops them.
    await pumpUntil("primeras: todo llegó al oído") {
        h.transcriber.appended.reduce(0) { $0 + $1.pcm16le24k.count } >= 6 * 640
    }
    await h.session.release()
    await pumpUntil("primeras: el turno viaja") { !h.chat.histories.isEmpty }
    let heard = h.transcriber.appended.reduce(Data()) { $0 + $1.pcm16le24k }
    expectEq(heard.first, 0x7A, "primeras: el audio de +0 ms abre lo que oye el oído")
    expectEq(heard.count, 6 * 640, "primeras: nada se perdió")
    expectEq(heard.last, 0x11, "primeras: el orden se conserva")
}

/// 15d-1: the tap now lands while the mic may still be coming up
/// (press→mic ~200 ms live). The listen that arrives after the cancel
/// belongs to no hold: the mic must end off, not listening for nobody.
@MainActor func testATapWhileTheMicComesUpLeavesItOff() async {
    let h = makeVoiceHarness()
    h.mic.startDelay = 0.2
    let press = Task { await h.session.hold() }
    await settle(0.05)
    await h.session.discard()
    await press.value
    await settle(0.05)
    expectEq(h.watch.latest.state, .idle, "tap en arranque: reposo")
    expect(h.mic.stopped, "tap en arranque: el micro queda apagado")
    expect(!h.watch.latest.holdArmed, "tap en arranque: sin hold armado")
}

/// Same race, from the release side: a hold shorter than the mic's own
/// start-up must not leave it listening with no key to close it.
@MainActor func testAReleaseWhileTheMicComesUpLeavesItOff() async {
    let h = makeVoiceHarness()
    h.mic.startDelay = 0.2
    let press = Task { await h.session.hold() }
    await settle(0.05)
    await h.session.release()
    await press.value
    await settle(0.05)
    expectEq(h.watch.latest.state, .idle, "soltar en arranque: reposo")
    expect(h.mic.stopped, "soltar en arranque: el micro queda apagado")
    expect(h.chat.histories.isEmpty, "soltar en arranque: nada viaja")
}

/// 15d-2 (TDD row 3): after the key comes up the mic keeps feeding the
/// ear for the tail, and only then commits — the last
/// syllable used to be cut at `release→commit 0`.
@MainActor func testTheTailKeepsFeedingTheEarsThenCommits() async {
    let h = makeVoiceHarness(releaseTail: 1.0)
    h.transcriber.stoppedText = "abre Safari"
    h.chat.rounds = [[.text("Listo.")]]
    await h.session.hold()
    await pumpUntil("cola: listening") { h.watch.latest.state == .listening }
    speak(h, frames: 3, byte: 0x11)
    await pumpUntil("cola: frames") { h.transcriber.appended.count >= 3 }
    h.clock.now = 10
    let release = Task { await h.session.release() }
    await pumpUntilAsync("cola: soltó") { await h.session.timeline.released != nil }
    h.clock.now = 10.3
    speak(h, frames: 3, byte: 0x22)
    await pumpUntil("cola: la cola llega a Apple") { h.transcriber.appended.count >= 6 }
    expect(h.chat.histories.isEmpty, "cola: aún no se envía")
    await release.value
    await pumpUntil("cola: el turno viaja") { !h.chat.histories.isEmpty }
    let heard = h.transcriber.appended.reduce(Data()) { $0 + $1.pcm16le24k }
    expectEq(heard.count, 6 * 640, "cola: el oído recibe la cola")
    expectEq(heard.last, 0x22, "cola: lo último es lo dicho tras soltar")
    expectEq(await h.session.timeline.released, 10, "cola: soltar al subir la tecla")
    expectEq(await h.session.timeline.committed, 10.3, "cola: el commit tras la cola")
}

/// 15d-2: a press inside the tail takes the hold back (15b-10's steer
/// spirit: the newest press wins) — the tail never commits on its own,
/// and the next release commits exactly once.
@MainActor func testAPressDuringTheTailCommitsOnce() async {
    let h = makeVoiceHarness(releaseTail: 0.5)
    h.transcriber.stoppedText = "abre Safari"
    h.chat.rounds = [[.text("Listo.")]]
    await h.session.hold()
    await pumpUntil("cola+press: listening") { h.watch.latest.state == .listening }
    speak(h, frames: 3)
    await pumpUntil("cola+press: frames") { h.transcriber.appended.count >= 3 }
    let first = Task { await h.session.release() }
    await pumpUntilAsync("cola+press: soltó") { await h.session.timeline.released != nil }
    await h.session.hold()
    await first.value
    expect(h.chat.histories.isEmpty, "cola+press: nada llega al cerebro")
    expectEq(h.watch.latest.state, .listening, "cola+press: sigue escuchando")
    speak(h, frames: 3)
    await h.session.release()
    await pumpUntil("cola+press: el turno viaja") { !h.chat.histories.isEmpty }
    await h.session.awaitClassicTurn()
    await settle(0.1)
    expectEq(h.chat.histories.count, 1, "cola+press: un solo turno")
}

