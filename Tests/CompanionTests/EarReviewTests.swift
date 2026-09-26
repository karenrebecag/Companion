import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Revisión 2026-09-24 de la wave 15e, del lado de la sesión: quién detiene
// el oído y quién le entrega el audio que llegó antes de que arrancara.

@Test @MainActor func earReviewTests() async {
    await testADictationStopNeverKillsTheNextHold()
    await testEarlyAudioReachesTheEarExactlyOnce()
    await testAFailedListenKeepsNoEarlyAudio()
    await testADeniedListenKeepsNoEarlyAudio()
    await testADictationHoldKeepsNoEarlyAudio()
}

/// M1: the dictation branch stopped the ear outside `stopEar()`, so the
/// listen of a press after Esc never waited for it: that press's ear
/// started, then the dictation's late stop halted it and its late
/// completion hung the new hold up.
@MainActor func testADictationStopNeverKillsTheNextHold() async {
    let injector = ScriptedInjector()
    let h = makeVoiceHarness(
        fieldProbe: ScriptedFieldProbe(FocusedField(app: "Slack", pid: 42)), injector: injector)
    h.transcriber.stoppedText = "hola"
    h.transcriber.stopDelays = [0.4]
    await h.session.hold(dictate: true)
    await pumpUntil("dictado A: listening") { h.watch.latest.state == .listening }
    let release = Task { await h.session.release() }
    await pumpUntil("dictado A: el stop espera") { h.transcriber.stops >= 1 }
    let esc = Task { await h.session.discard() }
    await pumpUntil("Esc: reposo") { h.watch.latest.state == .idle }
    await h.session.hold()
    await release.value
    await esc.value
    await pumpUntil("hold B: listening") { h.watch.latest.state == .listening }
    await settle(0.5)
    expectEq(h.watch.latest.state, .listening, "hold B: sigue escuchando")
    expect(h.transcriber.running, "hold B: el stop del dictado no mata su oído")
    expect(injector.texts.isEmpty, "dictado A: la sesión ya es de B, no pega")
}

/// M3: `submit` ran `finalTranscript` off the session actor while the frame
/// pump kept writing the same buffers on it; the early audio could reach
/// the ear twice ("abre abre Safari"). Every 640-byte chunk carries its own
/// id byte, and no id may reach the ear twice.
@MainActor func testEarlyAudioReachesTheEarExactlyOnce() async {
    for round in 0 ..< 10 {
        let h = makeVoiceHarness()
        h.transcriber.stoppedText = "abre Safari"
        h.chat.rounds = [[.text("Listo.")]]
        h.transcriber.startDelay = 0.05
        let press = Task { await h.session.hold() }
        await pumpUntil("M3: micro") { h.mic.started }
        for id in UInt8(1) ... 5 { h.mic.yield(idFrame(id)) }
        await press.value
        await pumpUntil("M3: listening") { h.watch.latest.state == .listening }
        let release = Task { await h.session.release() }
        for id in UInt8(6) ... 60 { h.mic.yield(idFrame(id)) }
        await release.value
        await pumpUntil("M3: el turno viaja") { !h.chat.histories.isEmpty }
        await h.session.awaitClassicTurn()
        let ids = chunkIDs(h.transcriber.appended)
        expectEq(ids.count, Set(ids).count, "M3 ronda \(round): ningún trozo llega dos veces")
        expect(ids.contains(1), "M3 ronda \(round): el audio temprano llega")
    }
}

/// L3: frames heard while the listen came up, then the mic failed: the
/// listen returns early and no flush ever takes them.
@MainActor func testAFailedListenKeepsNoEarlyAudio() async {
    let h = makeVoiceHarness()
    h.mic.startDelay = 0.2
    h.mic.startError = .unreachable
    let press = Task { await h.session.hold() }
    await settle(0.05)
    for id in UInt8(1) ... 5 { h.mic.yield(idFrame(id)) }
    await pumpUntilAsync("L3: el audio temprano se guardó") { await kept(h) > 0 }
    await press.value
    await settle(0.3)
    expectEq(await kept(h), 0, "L3: micro caído, sin PCM en memoria")
}

@MainActor func testADeniedListenKeepsNoEarlyAudio() async {
    let h = makeVoiceHarness()
    h.transcriber.grantsAuthorization = false
    h.transcriber.authorizationDelay = 0.2
    let press = Task { await h.session.hold() }
    await settle(0.05)
    for id in UInt8(1) ... 5 { h.mic.yield(idFrame(id)) }
    await pumpUntilAsync("L3: el audio temprano se guardó") { await kept(h) > 0 }
    await press.value
    await settle(0.1)
    expectEq(await kept(h), 0, "L3: voz denegada, sin PCM en memoria")
}

/// L3: a dictation hold released before any live frame never flushed its
/// early audio; it now reaches the ear and leaves nothing behind.
@MainActor func testADictationHoldKeepsNoEarlyAudio() async {
    let injector = ScriptedInjector()
    let h = makeVoiceHarness(
        fieldProbe: ScriptedFieldProbe(FocusedField(app: "Slack", pid: 42)), injector: injector)
    h.transcriber.stoppedText = "hola"
    h.transcriber.startDelay = 0.2
    let press = Task { await h.session.hold(dictate: true) }
    await pumpUntil("L3 dictado: micro") { h.mic.started }
    for id in UInt8(1) ... 5 { h.mic.yield(idFrame(id)) }
    await pumpUntilAsync("L3 dictado: guardado") { await kept(h) == 5 * 640 }
    await press.value
    await pumpUntil("L3 dictado: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("L3 dictado: pegó") { injector.texts == ["hola"] }
    expectEq(await kept(h), 0, "L3 dictado: sin PCM en memoria")
    expect(chunkIDs(h.transcriber.appended).contains(1), "L3 dictado: el oído oyó el principio")
}

private func kept(_ h: VoiceHarness) async -> Int {
    await h.session.classic.holdAudio.keptBytes
}

private func idFrame(_ id: UInt8) -> MicFrame {
    MicFrame(pcm16le24k: Data(repeating: id, count: 640), rms: 0.3)
}

private func chunkIDs(_ frames: [MicFrame]) -> [UInt8] {
    let all = frames.reduce(Data()) { $0 + $1.pcm16le24k }
    return stride(from: 0, to: all.count, by: 640).map { all[all.startIndex + $0] }
}
