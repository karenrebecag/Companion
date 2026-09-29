import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import CoreGraphics
import Foundation
import Testing

// Wave 12b. La sesión de voz bajo el hold: pulsar abre, soltar envía lo que
// el oído nativo oyó (ForceEndpoint), un tap no envía, pulsar mientras habla
// corta, y sin clave el clásico escucha y envía al soltar.

@Test @MainActor func holdVoiceTests() async {
    await testHoldThenReleaseSendsTheNativeText()
    await testReleaseWithNothingHeardSaysSo()
    await testTapDiscardsWithoutSending()
    await testAPressDuringAReleaseWins()
    await testHoldWhileSpeakingCutsTheAgent()
    await testHoldOnClassic()
    await testTheEarIsOnBeforeTheSessionIsReady()
    await testAHoldIsOneTurnUnderServerVAD()
    await testPartialsReachTheStreamWhileHolding()
    await testClassicPartialsComeFromTheEarThatHears()
    await testPrewarmTouchesNothingLoud()
    await testAHoldWritesItsTimeline()
    await testAHoldMarksFirstToken()
    await testALateSegmentAfterReleaseSendsNothing()
    await testALateSegmentAfterDiscardSendsNothing()
    await testLateWordsDoNotJoinTheNextHold()
    await testABouncedPressKeepsTheTimeline()
    await testATapBeforeAHoldDoesNotPoisonItsTimeline()
    await testALateToolMarkDoesNotJoinTheNextHold()
    await testHoldDoesNotOpenRealtime()
    await testHoldDelegateReachesTheSubmitter()
    await testHoldWithoutJobsDoesNotAdvertiseDelegate()
    await testHoldParentToolIsNotAJob()
    await testHoldJobDoneIsSpoken()
    await testReleaseWhileThinkingAfterServerCommitSendsNothingExtra()
    await testHoldEndsIdleWithMicOffAfterReply()
    await testClassicHoldMarksFirstAudioOnce()
    await testChunkStartedWithoutAHoldDoesNotMark()
    await testTheModelPathMarksCommitted()
    await testFNNeverDictatesEvenInAutomaticModeWithAField()
    testConsumesPureDecision()
    await testAVoicedHoldCarriesTheAnalyzerFinal()
    await testAVoicedHoldWithAnEmptyFinalSaysSo()
    await testEarLogNamesTheEarNeverTheWords()
    await testASilentHoldNeverReachesTheBrain()
    await testAQuietHoldTheEarHeardStillTravels()
}

/// Code in `finalTranscript` writes one `ear=` line per hold; these read
/// it back without depending on anything else the log holds.
@MainActor private func earLines(_ url: URL) -> [String] {
    let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    return text.split(separator: "\n").map(String.init).filter { $0.contains("ear=") }
}

@MainActor private func earLogURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-ear-\(UUID().uuidString).log")
}

/// 15e-1 (spec §4 row 3): a voiced hold carries the analyzer's final and
/// names the ear — Groq is gone from the hold.
@MainActor func testAVoicedHoldCarriesTheAnalyzerFinal() async {
    let url = earLogURL()
    await Log.capturing(to: url) {
        let h = makeVoiceHarness()
        h.transcriber.stoppedText = "abre Safari y busca el clima"
        h.chat.rounds = [[.text("Hecho.")]]
        await h.session.hold()
        await pumpUntil("apple: listening") { h.watch.latest.state == .listening }
        speak(h, frames: 3)
        await pumpUntil("apple: frames") { h.transcriber.appended.count >= 3 }
        await h.session.release()
        await pumpUntil("apple: el turno viaja") { !h.chat.histories.isEmpty }
        let sent = h.chat.histories.last?.last?.content ?? ""
        expect(sent.contains("abre Safari y busca el clima"), "apple: su final es el que viaja")
        expect(earLines(url).contains { $0.hasSuffix("ear=apple-analyzer") }, "apple: el log nombra el oído")
        expect(!earLines(url).contains { $0.contains("groq") || $0.contains("noKey") },
               "apple: ningún rastro de Groq")
    }
}

/// 15e-1: speech energy but an empty final — "no te oí", never the brain,
/// and the log says the ear came back empty.
@MainActor func testAVoicedHoldWithAnEmptyFinalSaysSo() async {
    let url = earLogURL()
    await Log.capturing(to: url) {
        let h = makeVoiceHarness()
        let seen = SessionEventBox(h.session.events)
        h.transcriber.stoppedText = ""
        h.chat.rounds = [[.text("¿Qué?")]]
        await h.session.hold()
        await pumpUntil("vacío: listening") { h.watch.latest.state == .listening }
        speak(h, frames: 3)
        await pumpUntil("vacío: frames") { h.transcriber.appended.count >= 3 }
        await h.session.release()
        await h.session.awaitClassicTurn()
        expect(seen.events.contains { $0 == .heardNothing }, "vacío: «no te oí»")
        expect(h.chat.histories.isEmpty, "vacío: el cerebro nunca se llama")
        expect(earLines(url).contains { $0.hasSuffix("ear=apple-analyzer reason=empty") },
               "vacío: el log dice que el oído volvió vacío")
    }
}

/// 15c-7 (spec §4 row 4): no speech energy and an empty final is silence —
/// nothing travels, the hold rests with the mic off.
@MainActor func testASilentHoldNeverReachesTheBrain() async {
    let url = earLogURL()
    await Log.capturing(to: url) {
        let h = makeVoiceHarness()
        let seen = SessionEventBox(h.session.events)
        h.transcriber.stoppedText = ""
        h.chat.rounds = [[.text("De nada.")]]
        await h.session.hold()
        await pumpUntil("silencio: listening") { h.watch.latest.state == .listening }
        for _ in 0 ..< 6 {
            h.mic.yield(MicFrame(pcm16le24k: Data(repeating: 0x01, count: 640), rms: 0.02))
        }
        await pumpUntil("silencio: frames") { h.transcriber.appended.count >= 6 }
        await h.session.release()
        await h.session.awaitClassicTurn()
        expect(seen.events.contains { $0 == .heardNothing }, "silencio: lo trata como no oído")
        expect(h.chat.histories.isEmpty, "silencio: el cerebro nunca se llama")
        expect(earLines(url).contains { $0.hasSuffix("ear=none reason=silence") },
               "silencio: el log lo dice")
        await pumpUntil("silencio: a reposo (15d-4)") { h.watch.latest.state == .idle }
        expect(h.mic.stopped, "silencio: el micro se apaga (15d-4)")
    }
}

/// The energy gate must not eat a soft speaker: low energy, but the ear
/// heard words, and those words are the turn.
@MainActor func testAQuietHoldTheEarHeardStillTravels() async {
    let h = makeVoiceHarness()
    h.transcriber.stoppedText = "abre Notas"
    h.chat.rounds = [[.text("Listo.")]]
    await h.session.hold()
    await pumpUntil("bajito: listening") { h.watch.latest.state == .listening }
    h.mic.yield(MicFrame(pcm16le24k: Data(repeating: 0x02, count: 640), rms: 0.1))
    await pumpUntil("bajito: frame") { !h.transcriber.appended.isEmpty }
    await h.session.release()
    await pumpUntil("bajito: el turno viaja") { !h.chat.histories.isEmpty }
    let sent = h.chat.histories.last?.last?.content ?? ""
    expect(sent.contains("abre Notas"), "bajito: viaja lo que oyó el oído")
}

/// TDD row 16 (15c), kept for the one ear left: `ear=…` names the ear,
/// never the utterance.
@MainActor func testEarLogNamesTheEarNeverTheWords() async {
    let url = earLogURL()
    await Log.capturing(to: url) {
        let h = makeVoiceHarness()
        h.transcriber.stoppedText = "contraseña del banco es 1234"
        h.chat.rounds = [[.text("Hecho.")]]
        await h.session.hold()
        await pumpUntil("ear log: listening") { h.watch.latest.state == .listening }
        speak(h, frames: 3)
        await pumpUntil("ear log: el frame llegó") { h.transcriber.appended.count >= 3 }
        await h.session.release()
        await pumpUntil("ear log: el turno llega") { !h.chat.histories.isEmpty }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        expect(earLines(url).contains { $0.hasSuffix("ear=apple-analyzer") }, "ear log: nombra el oído")
        expect(!text.contains("contraseña del banco es 1234"), "ear log: nunca el texto")
    }
}

/// 22. Pulsar abre el clásico; soltar manda el texto al ChatProvider, no a realtime.
@MainActor func testHoldThenReleaseSendsTheNativeText() async {
    let h = makeVoiceHarness()
    h.transcriber.stoppedText = "abre Safari"
    h.chat.rounds = [[.text("Listo.")]]
    await h.session.hold()
    await pumpUntil("hold: listening") { h.watch.latest.state == .listening }
    expect(!h.watch.latest.muted, "hold: el micro está abierto mientras se mantiene")
    expectEq(h.watch.latest.pipeline, .classic, "hold: camino de texto")
    expectEq(h.transport.openCount, 0, "hold: no abre el socket de conversación")
    await h.session.release()
    await pumpUntil("hold: el chat recibe el turno") { !h.chat.histories.isEmpty }
    // 15b-10: `classic.submit` now runs detached — `release()` returns as
    // soon as the turn task is STARTED, not finished.
    await h.session.awaitClassicTurn()
    expect(h.chat.histories[0].contains { $0.role == .user && $0.content.contains("abre Safari") },
           "hold: lo que oyó el oído")
    expect(h.thread.turns.contains { $0.role == .assistant && $0.content.contains("Listo.") },
           "hold: la respuesta entra al hilo")
    expect(!hasMessage(h.transport.sent, type: "response.create"),
           "hold: cero response.create")
}

/// 23. Soltar sin texto: no se envía nada y la sesión lo dice (`heardNothing`).
/// Wave 15d-4 (TDD row 5): and it goes back to rest with the mic off — the
/// 12b "no cuelga" left a hot mic nobody held (Incredible rests too).
@MainActor func testReleaseWithNothingHeardSaysSo() async {
    let h = makeVoiceHarness()
    let seen = SessionEventBox(h.session.events)
    h.transcriber.stoppedText = ""
    await h.session.hold()
    await pumpUntil("nada: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    // 15b-10: the turn runs detached — wait for all of it before reading
    // state, or the state check can catch it mid-flight.
    await h.session.awaitClassicTurn()
    await pumpUntil("nada: a reposo") { h.watch.latest.state == .idle }
    expect(seen.events.contains { $0 == .heardNothing }, "nada: lo dice")
    expect(h.chat.histories.isEmpty, "nada: no se envía un turno vacío")
    expectEq(h.watch.latest.state, .idle, "nada: vuelve a reposo")
    expect(h.mic.stopped, "nada: el micro se apaga")
    expect(!h.watch.latest.holdArmed, "nada: ningún hold queda armado")
}

/// 23b. Un tap cierra el micro sin enviar y sin decir «no te oí».
@MainActor func testTapDiscardsWithoutSending() async {
    let h = makeVoiceHarness()
    let seen = SessionEventBox(h.session.events)
    h.transcriber.stoppedText = "ruido"
    await h.session.hold()
    await pumpUntil("tap: listening") { h.watch.latest.state == .listening }
    await h.session.discard()
    await pumpUntil("tap: cuelga") {
        h.watch.latest.state == .idle || h.watch.latest.muted
    }
    await settle(0.05)
    expect(h.chat.histories.isEmpty, "tap: nada se envía")
    expect(!seen.events.contains { $0 == .heardNothing }, "tap: y no es «no te oí»")
}

/// 23c. Code review 2026-09-06 (alto): `release()` suspende en el micro
/// antes de aplicar; una pulsación que entra en ese hueco reabría el micro
/// y la suelta vieja lo volvía a cerrar. La suelta que llega tarde se
/// descarta: la pulsación nueva manda.
@MainActor func testAPressDuringAReleaseWins() async {
    let h = makeVoiceHarness()
    h.transcriber.stoppedText = "hola"
    await h.session.hold()
    await pumpUntil("carrera: listening") { h.watch.latest.state == .listening }
    h.mic.receivedBufferDelay = 0.3
    let release = Task { await h.session.release() }
    await settle(0.05)
    await h.session.hold()
    await release.value
    await settle(0.05)
    expect(!h.watch.latest.muted, "carrera: la pulsación nueva deja el micro abierto")
    expectEq(h.watch.latest.state, .listening, "carrera: sigue escuchando")
}

/// 24. Pulsar otra vez después de hablar: sigue el camino de texto, sin realtime.
@MainActor func testHoldWhileSpeakingCutsTheAgent() async {
    let h = makeVoiceHarness()
    h.transcriber.stoppedText = "para"
    h.chat.rounds = [[.text("De acuerdo.")]]
    await h.session.hold()
    await pumpUntil("corte: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("corte: habló") { h.synth.queue.contains("De acuerdo.") }
    await h.session.hold()
    await pumpUntil("corte: otra vez listening") { h.watch.latest.state == .listening }
    expectEq(h.watch.latest.pipeline, .classic, "corte: sigue texto")
    expect(!hasMessage(h.transport.sent, type: "response.cancel"),
           "corte: no hay socket que cancelar")
}

/// 25. Sin clave: el clásico escucha al pulsar y empieza el turno al soltar.
@MainActor func testHoldOnClassic() async {
    let h = makeVoiceHarness(key: nil)
    h.transcriber.stoppedText = "qué hora es"
    h.chat.rounds = [[.text("Las tres.")]]
    await h.session.hold()
    await pumpUntil("clásico: listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .classic
    }
    await h.session.release()
    await pumpUntil("clásico: responde") { h.synth.queue.contains("Las tres.") }
}

/// 6 (12c). El oído arranca al pulsar, sin esperar un socket de conversación.
@MainActor func testTheEarIsOnBeforeTheSessionIsReady() async {
    let h = makeVoiceHarness(autoEvents: [], readyTimeout: 5)
    await h.session.hold()
    await pumpUntil("oído: listening") { h.watch.latest.state == .listening }
    expect(h.transcriber.started, "oído: el transcriptor arranca")
    expectEq(h.transport.openCount, 0, "oído: sin socket de conversación")
    h.mic.yield(MicFrame(pcm16le24k: Data([1, 2, 3, 4]), rms: 0.5))
    await pumpUntil("oído: el frame llega") { !h.transcriber.appended.isEmpty }
    expectEq(h.watch.latest.pipeline, .classic, "oído: camino de texto")
}

/// 7. Una pausa dentro del hold no envía; al soltar viaja el texto del oído.
@MainActor func testAHoldIsOneTurnUnderServerVAD() async {
    let h = makeVoiceHarness()
    h.transcriber.stoppedText = "abre Safari"
    h.chat.rounds = [[.text("Hecho.")]]
    await h.session.hold()
    await pumpUntil("un turno: listening") { h.watch.latest.state == .listening }
    await settle(0.1)
    expect(h.chat.histories.isEmpty, "un turno: la pausa no envía")
    expectEq(h.watch.latest.state, .listening, "un turno: sigue escuchando")
    await h.session.release()
    await pumpUntil("un turno: al soltar viaja") { !h.chat.histories.isEmpty }
    expect(h.chat.histories[0].contains { $0.content.contains("abre Safari") },
           "un turno: lo acumulado, junto")
}

/// 8 (12c). Los parciales del oído salen por `events` mientras se
/// mantiene; tras soltar ya no.
@MainActor func testPartialsReachTheStreamWhileHolding() async {
    let h = makeVoiceHarness()
    let seen = SessionEventBox(h.session.events)
    await h.session.hold()
    await pumpUntil("parciales: listening") { h.watch.latest.state == .listening }
    h.transcriber.yieldPartial("hola")
    await pumpUntil("parciales: llega") { seen.events.contains { $0 == .partialTranscript("hola") } }
    h.transcriber.yieldPartial("hola mundo")
    await pumpUntil("parciales: crece") { seen.events.contains { $0 == .partialTranscript("hola mundo") } }
    await h.session.release()
    await pumpUntil("parciales: ya no listening") { h.watch.latest.state != .listening }
    h.transcriber.yieldPartial("hola mundo tarde")
    await settle(0.1)
    expect(!seen.events.contains { $0 == .partialTranscript("hola mundo tarde") },
           "parciales: tras soltar no salen")
}

/// 8b (16i, seen live 2026-09-25): the app ships a separate realtime ear.
/// On a classic hold the words were read from that ear, which hears nothing
/// there, so the island never showed what Karen was saying.
@MainActor func testClassicPartialsComeFromTheEarThatHears() async {
    let h = makeVoiceHarness(realtimeEar: ScriptedSegmentingEar())
    let seen = SessionEventBox(h.session.events)
    await h.session.hold()
    await pumpUntil("parciales clásico: listening") { h.watch.latest.state == .listening }
    h.transcriber.yieldPartial("abre el correo")
    await pumpUntil("parciales clásico: la isla lo ve") {
        seen.events.contains { $0 == .partialTranscript("abre el correo") }
    }
    await h.session.release()
}

/// 9 (12c). Precalentar prepara el micro y lee la clave; no abre el socket
/// ni arranca el micro ni pide permisos.
@MainActor func testPrewarmTouchesNothingLoud() async {
    let h = makeVoiceHarness()
    await h.session.prewarm()
    expect(h.mic.prewarmed, "prewarm: el micro se prepara")
    expect(!h.mic.started, "prewarm: sin arrancar el micro")
    expect(!h.mic.accessAsked, "prewarm: sin pedir permiso")
    expectEq(h.transport.openCount, 0, "prewarm: sin abrir el socket")
    expectEq(h.secrets.reads, 0, "prewarm: sin tocar el llavero (una lectura puede ser un diálogo)")
    expectEq(h.watch.latest.state, .idle, "prewarm: la máquina no se mueve")
}

/// 10 (12c). Un hold entero deja su línea de tiempos: pulsar, listo,
/// soltar, enviar, primer audio.
@MainActor func testAHoldWritesItsTimeline() async {
    let h = makeVoiceHarness()
    let seen = SessionEventBox(h.session.events)
    h.clock.now = 100
    await h.session.hold()
    await pumpUntil("tiempos: listening") { h.watch.latest.state == .listening }
    h.mic.yield(MicFrame(pcm16le24k: Data([1, 2]), rms: 0.4))
    h.transcriber.yieldPartial("hola")
    await pumpUntil("tiempos: parcial") { seen.events.contains { $0 == .partialTranscript("hola") } }
    h.transcriber.stoppedText = "hola"
    h.chat.rounds = [[.text("Hola.")]]
    h.clock.now = 101
    await h.session.release()
    await pumpUntil("tiempos: enviado") { !h.chat.histories.isEmpty }
    expectEq(await h.session.timeline.pressed, 100, "tiempos: pulsar queda")
    expect(await h.session.timeline.released != nil, "tiempos: soltar queda")
}

/// Wave 15c-0: the brain's first delta marks `.firstToken`, apart from
/// `.firstAudio` — a turn can be slow to think and fast to speak, or the
/// reverse, and the log must tell them apart (wave-15c §1).
@MainActor func testAHoldMarksFirstToken() async {
    let h = makeVoiceHarness()
    h.transcriber.stoppedText = "hola"
    h.chat.rounds = [[.text("Hola, ¿qué tal?")]]
    await h.session.hold()
    await pumpUntil("firstToken: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("firstToken: el turno arrancó") { !h.synth.queue.isEmpty }
    expect(await h.session.timeline.firstToken != nil,
           "firstToken: el primer delta del cerebro queda marcado")
}

/// 11 (12c, code review alto). Tras soltar, el VAD del servidor aún puede
/// cerrar el segmento que iba en vuelo: ese `.finished` tardío no es un
/// turno nuevo. El hold ya envió lo que el oído tenía.
@MainActor func testALateSegmentAfterReleaseSendsNothing() async {
    let h = makeVoiceHarness()
    h.transcriber.stoppedText = "abre Safari"
    h.chat.rounds = [[.text("Hecho.")]]
    await h.session.hold()
    await pumpUntil("tardío: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("tardío: el hold envía") { h.chat.histories.count == 1 }
    await settle(0.15)
    expectEq(h.chat.histories.count, 1, "tardío: un solo turno")
}

/// 11b (12c, code review alto). Un tap descarta; un `.finished` tardío no
/// puede enviar lo que el usuario canceló.
@MainActor func testALateSegmentAfterDiscardSendsNothing() async {
    let ear = ScriptedSegmentingEar()
    let h = makeVoiceHarness(realtimeEar: ear)
    await h.session.hold()
    await pumpUntil("descarte: listening") { h.watch.latest.state == .listening }
    await h.session.discard()
    await pumpUntil("descarte: idle o mute") {
        h.watch.latest.state == .idle || h.watch.latest.muted
    }
    ear.yieldTurn(.speechStarted)
    ear.yieldTurn(.finished(text: "ruido"))
    await settle(0.15)
    expect(h.chat.histories.isEmpty, "descarte: nada viaja")
}

/// 12 (12c, security review medio). Palabras del hold anterior que el
/// oído entrega tarde no se cuelan en el hold siguiente: cada pulsación
/// empieza con el oído en cero.
@MainActor func testLateWordsDoNotJoinTheNextHold() async {
    let h = makeVoiceHarness()
    await h.session.hold()
    await pumpUntil("cuelan: listening") { h.watch.latest.state == .listening }
    h.transcriber.stoppedText = "uno"
    h.chat.rounds = [[.text("Uno.")], [.text("Tres.")]]
    await h.session.release()
    await pumpUntil("cuelan: primer turno") { h.chat.histories.count == 1 }
    await h.session.hold()
    await pumpUntil("cuelan: segundo hold") { h.watch.latest.state == .listening }
    h.transcriber.stoppedText = "tres"
    await h.session.release()
    await pumpUntil("cuelan: segundo turno") { h.chat.histories.count == 2 }
    let lastUser = h.chat.histories[1].last { $0.role == .user }?.content ?? ""
    expect(lastUser.contains("tres"), "cuelan: lo dicho en el segundo hold viaja")
    expect(!lastUser.contains("uno"), "cuelan: lo tardío del primero no")
}

/// 13 (12c, code review medio). Una pulsación que rebota mientras la
/// sesión conecta no reinicia la línea de tiempos: press→ready se mide
/// desde la primera.
@MainActor func testABouncedPressKeepsTheTimeline() async {
    let h = makeVoiceHarness()
    h.clock.now = 100
    await h.session.hold()
    await pumpUntil("rebote: listening") { h.watch.latest.state == .listening }
    h.clock.now = 100.3
    await h.session.hold()
    h.transcriber.stoppedText = "hola"
    h.chat.rounds = [[.text("Hola.")]]
    h.clock.now = 101
    await h.session.release()
    await pumpUntil("rebote: enviado") { !h.chat.histories.isEmpty }
    expectEq(await h.session.timeline.pressed, 100, "rebote: la primera pulsación manda")
}

/// Live bug B (2026-09-22): a tap never reaches `release()`, so it never
/// marked `.released` on the timeline; `hold()`'s bounce check only looked
/// at `released == nil` and mistook the discarded hold for one still in
/// flight, keeping its stale press mark. A tap must not poison the next
/// real hold's clock.
@MainActor func testATapBeforeAHoldDoesNotPoisonItsTimeline() async {
    let h = makeVoiceHarness()
    h.clock.now = 100
    await h.session.hold()
    await pumpUntil("tap-before: listening") { h.watch.latest.state == .listening }
    await h.session.discard()
    await pumpUntil("tap-before: idle or muted") {
        h.watch.latest.state == .idle || h.watch.latest.muted
    }
    h.clock.now = 400
    await h.session.hold()
    await pumpUntil("tap-before: listening again") { h.watch.latest.state == .listening }
    expectEq(await h.session.timeline.pressed, 400, "tap-before: the new hold owns its own press mark")
}

/// DM0 review (HIGH, 2026-09-22). El tool call de un padre pertenece al hold
/// que lo comprometió, no al que esté en curso cuando el server por fin
/// contesta: una marca tardía solía escribirse en la línea de tiempos nueva
/// de un hold que no tenía nada que ver, corrompiendo commit→tool/tool→done.
@MainActor func testALateToolMarkDoesNotJoinTheNextHold() async {
    let h = makeVoiceHarness()
    await h.session.start()
    await pumpUntil("tool tardío: listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .realtime
    }
    // Hold 1 pulsa (el oído arranca en cero) y suelta con lo dicho durante
    // el hold: el texto compromete el turno, como haría un tool call del
    // padre que le sigue.
    await h.session.hold()
    h.transcriber.stoppedText = "abre safari"
    await h.session.release()
    expect(await h.session.timeline.committed != nil, "tool tardío: hold 1 comprometió")
    // El server contesta a tiempo: las marcas caen en la línea de hold 1.
    await h.session.markTool(.toolCallSeen)
    await h.session.markTool(.toolDone)
    let onTime = await h.session.timeline.line()
    expect(onTime?.contains("commit→tool —") == false,
           "tool tardío: a tiempo, commit→tool es un número")

    // Hold 2 pulsa: el reloj se reinicia mientras la llamada de hold 1
    // sigue en vuelo del lado del server.
    await h.session.hold()
    expect(await h.session.timeline.committed == nil, "tool tardío: hold 2 empieza en blanco")
    // La respuesta de hold 1 llega recién ahora, tarde.
    await h.session.markTool(.toolCallSeen)
    expect(await h.session.timeline.toolCallSeen == nil,
           "tool tardío: la marca tardía de hold 1 no se cuela en hold 2")
    await h.session.flushTimeline()
    let hold2Line = await h.session.lastTimeline?.line()
    expect(hold2Line?.contains("commit→tool —") == true,
           "tool tardío: hold 2 se queda sin tool, sigue en —")
}

private let slack = FocusedField(app: "Slack", pid: 42)

/// Wave 14b. Hold with a key does not open the conversation websocket.
@MainActor func testHoldDoesNotOpenRealtime() async {
    let h = makeVoiceHarness()
    h.transcriber.stoppedText = "hola"
    h.chat.rounds = [[.text("Hola.")]]
    await h.session.hold()
    await pumpUntil("14b: listening") { h.watch.latest.state == .listening }
    expectEq(h.transport.openCount, 0, "14b: sin WS de conversación")
    await h.session.release()
    await pumpUntil("14b: chat") { !h.chat.histories.isEmpty }
    expect(!hasMessage(h.transport.sent, type: "response.create"), "14b: cero response.create")
}

/// Wave 14b. Un `delegate` del stream llega al JobSubmitter.
@MainActor func testHoldDelegateReachesTheSubmitter() async {
    let jobs = CapturingSubmitter()
    let h = makeVoiceHarness(jobs: jobs)
    h.transcriber.stoppedText = "crea un archivo"
    h.chat.rounds = [[.handoff(Handoff(goal: "crea prueba.txt", context: ""))]]
    await h.session.hold()
    await pumpUntil("delegate: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("delegate: el submitter vio el encargo") { jobs.goals == ["crea prueba.txt"] }
    expect((h.chat.toolsPerCall.first ?? []).map(\.name).contains("delegate"),
           "delegate: se anuncia la tool")
}

/// Wave 14b. Sin jobs, classic no promete delegate.
@MainActor func testHoldWithoutJobsDoesNotAdvertiseDelegate() async {
    let h = makeVoiceHarness()
    h.transcriber.stoppedText = "hola"
    h.chat.rounds = [[.text("Hola.")]]
    await h.session.hold()
    await pumpUntil("sin jobs: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("sin jobs: chat") { !h.chat.histories.isEmpty }
    expect(!h.chat.toolsSeen.map(\.name).contains("delegate"),
           "sin jobs: no anuncia delegate")
}

/// Wave 14b. open_app en el hold es del padre, no un encargo.
@MainActor func testHoldParentToolIsNotAJob() async {
    let opener = FakeWorkspaceOpener(installed: ["Safari"])
    let jobs = CapturingSubmitter()
    let h = makeVoiceHarness(
        jobs: jobs, parentTools: ParentToolRunner(workspace: opener))
    h.transcriber.stoppedText = "abre safari"
    h.chat.rounds = [
        [.toolCalls([ToolCallRef(id: "c1", name: "open_app",
                                 arguments: #"{"name":"Safari"}"#)])],
        [.text("Listo, abrí Safari.")],
    ]
    await h.session.hold()
    await pumpUntil("manos: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("manos: abrió") { opener.openedApps == ["Safari"] }
    expect(jobs.goals.isEmpty, "manos: no es un encargo")
}

/// Wave 14b. Al terminar el job, la boca dice el anuncio (no realtime).
/// Code review 2026-09-25 (HIGH-B): en palabras propias, nunca la
/// instrucción al modelo (que nombraba el encargo entre «»).
@MainActor func testHoldJobDoneIsSpoken() async {
    let jobs = CapturingSubmitter()
    let h = makeVoiceHarness(jobs: jobs)
    h.transcriber.stoppedText = "crea un archivo"
    h.chat.rounds = [[.handoff(Handoff(goal: "crea prueba.txt", context: ""))]]
    await h.session.hold()
    await pumpUntil("anuncio: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("anuncio: el submitter corrió") { !jobs.goals.isEmpty }
    // 16h-2: the hold acknowledges first and its turn ends; the job's end
    // speaks after, in the gap.
    await pumpUntil("anuncio: el acuse") { h.synth.queue.first == Acknowledgement.delegating(.en) }
    h.synth.yield(.finished)
    await pumpUntil("anuncio: la boca habla") { h.synth.queue.count >= 2 }
    expectEq(h.synth.queue[1], "Done, it is on screen.", "anuncio: palabras propias")
    expect(!h.synth.queue.contains { $0.contains("The specialist answered") },
           "anuncio: nunca la instrucción al modelo")
}

/// Review finding (LOW, 2026-09-22): `TurnMachine.holdReleased`'s
/// `.thinking`/`.speaking` case (wave-dm1-router.md's "live bug" fix) closes
/// the mic and commits again from the native transcript when the key comes
/// up after the server's own VAD already committed the segment. This is a
/// realtime scenario reachable through `release()` alone — the public API
/// does not care whether the pipeline opened through `hold()` or `start()`
/// — so no production code needed touching to exercise it. With nothing new
/// heard since that first commit, the second commit must be a no-op: never
/// a second `response.create`, and never a `response.cancel` for a turn
/// already in flight.
@MainActor func testReleaseWhileThinkingAfterServerCommitSendsNothingExtra() async {
    let ear = ScriptedSegmentingEar()
    let h = makeVoiceHarness(realtimeEar: ear)
    await h.session.start()
    await pumpUntil("thinking: listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .realtime
    }
    ear.yieldTurn(.speechStarted)
    await pumpUntil("thinking: speechOpen") { h.watch.latest.speechOpen }
    ear.yieldTurn(.finished(text: "hola"))
    await pumpUntil("thinking: the server's own VAD already committed") {
        hasMessage(h.transport.sent, type: "response.create")
    }
    expectEq(h.watch.latest.state, .thinking, "thinking: state moved on before the key came up")
    let before = h.transport.sent.count

    await h.session.release()
    // Past commitTurnFromNative's own 250ms settle sleep on the fallback path.
    await settle(0.4)
    let added = Array(h.transport.sent.dropFirst(before))
    expect(!hasMessage(added, type: "response.create"),
           "thinking: nothing new heard, no second response.create")
    expect(!hasMessage(added, type: "response.cancel"),
           "thinking: and no response.cancel for a turn already in flight")
}

/// Live crash 2026-09-23: FN hold → release → router/chat reply spoken →
/// the session went back to `.listening` and re-armed the classic ear,
/// calling `mic.start()` on a mic that was never stopped. MicCapture then
/// crashed installing a second tap on the still-running engine. A hold turn
/// must end in idle with the mic off — the user presses again for the next
/// turn.
@MainActor func testHoldEndsIdleWithMicOffAfterReply() async {
    let h = makeVoiceHarness()
    h.transcriber.stoppedText = "abre Safari"
    h.chat.rounds = [[.text("Listo.")]]
    await h.session.hold()
    await pumpUntil("hold idle: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("hold idle: habla") { h.synth.queue.contains("Listo.") }
    h.synth.yield(.finished)
    await pumpUntil("hold idle: vuelve a idle") { h.watch.latest.state == .idle }
    expect(h.watch.latest.pipeline == nil, "hold idle: sin pipeline")
    expect(!h.watch.latest.muted, "hold idle: muted no importa ya en idle")
    expect(h.mic.stopped, "hold idle: el micro se detiene")
    expectEq(h.mic.startCount, 1, "hold idle: el micro arrancó una sola vez")
    expect(!h.mic.startedWithoutStop, "hold idle: nunca arranca sin haber parado antes")
}

// Wave 15b-0. Soltar → primer audio, medido en el clásico: `.chunkStarted`
// es la única señal de audio que ese camino tiene (`.agentAudioStarted` es
// solo de realtime), y el modelo-en-el-loop nunca marcaba `committed`.

/// 15b-0: the classic path never marked `.firstAudio` before this —
/// `.chunkStarted` from the synthesizer is the only signal a hold that never
/// opens realtime has. One hold, one mark: a second chunk of the same reply
/// must not move it.
@MainActor func testClassicHoldMarksFirstAudioOnce() async {
    let h = makeVoiceHarness()
    h.transcriber.stoppedText = "abre Safari"
    h.chat.rounds = [[.text("Listo.")]]
    h.clock.now = 10
    await h.session.hold()
    await pumpUntil("firstAudio: listening") { h.watch.latest.state == .listening }
    h.clock.now = 11
    await h.session.release()
    await pumpUntil("firstAudio: habla") { h.synth.queue.contains("Listo.") }
    h.clock.now = 11.3
    h.synth.yield(.chunkStarted(text: "Listo.", duration: 0.4))
    await pumpUntilAsync("firstAudio: se aplana") { await h.session.lastTimeline != nil }
    expectEq(await h.session.lastTimeline?.firstAudio, 11.3,
              "firstAudio: chunkStarted lo marca en el clásico")
    h.clock.now = 12
    h.synth.yield(.chunkStarted(text: "más.", duration: 0.2))
    await settle(0.05)
    expectEq(await h.session.lastTimeline?.firstAudio, 11.3,
              "firstAudio: un segundo chunk no lo mueve")
}

/// 15b-0: a stray `.chunkStarted` with no released hold (a job announcement,
/// or any chunk before a press) must not fabricate a `release→audio` — the
/// guard is `released != nil`, not "some speech happened".
@MainActor func testChunkStartedWithoutAHoldDoesNotMark() async {
    let h = makeVoiceHarness()
    h.synth.yield(.chunkStarted(text: "Listo.", duration: 0.3))
    await settle(0.05)
    expect(await h.session.lastTimeline == nil, "sin hold: nada que aplanar")
    expectEq(await h.session.timeline.firstAudio, nil, "sin hold: firstAudio sigue vacío")
}

/// 15b-0: `commitTimeline` used to be `routeThroughDecisionGate`'s own mark
/// (DM1c-2), reached only with a router attached. Every classic hold ends
/// up in `completeHold`'s `.agent` branch, router or not — this is the one
/// place both paths share.
@MainActor func testTheModelPathMarksCommitted() async {
    let h = makeVoiceHarness()
    h.transcriber.stoppedText = "abre Safari"
    h.chat.rounds = [[.text("Listo.")]]
    await h.session.hold()
    await pumpUntil("committed: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntilAsync("committed: marcado") { await h.session.timeline.committed != nil }
    expect(await h.session.timeline.committed != nil,
           "committed: el camino del modelo también compromete el turno")
}

// Wave 15b-1. FN es siempre el agente; dictar tiene su propia tecla — su
// propio flag de lado (Opción derecha por defecto) y sin tragarse eventos.

/// 15b-1: `hold()` (default `dictate: false`, FN's own call) stops reading
/// `voice.mode` altogether. A focused field and `.automatic` used to paste
/// a spoken order into Slack; now the words always reach Companion, the
/// field is never even probed, and the injector never sees them.
@MainActor func testFNNeverDictatesEvenInAutomaticModeWithAField() async {
    let probe = ScriptedFieldProbe(slack)
    let injector = ScriptedInjector()
    let h = makeVoiceHarness(voiceMode: .automatic, fieldProbe: probe, injector: injector)
    let seen = SessionEventBox(h.session.events)
    h.transcriber.stoppedText = "abre Safari"
    h.chat.rounds = [[.text("Listo.")]]
    await h.session.hold()
    await pumpUntil("FN agente: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("FN agente: el texto viaja") { !h.chat.histories.isEmpty }
    expect(injector.texts.isEmpty, "FN agente: el inyector nunca ve nada")
    expectEq(probe.probes, 0, "FN agente: ni se pregunta por el campo")
    expect(!seen.events.contains { if case .dictating = $0 { true } else { false } },
           "FN agente: la island no dice «dictando»")
}

/// 15b-1: `consumes` is pure — config decides, not a live event tap.
@MainActor func testConsumesPureDecision() {
    // The dictation key's own qualifying event: it matches, but this tap is
    // configured never to swallow anything (§8: an eaten modifier gets stuck).
    expect(!HoldKeyTap.consumes(
        code: 61, flags: CGEventFlags(rawValue: 0x40), keyCode: 61,
        flag: CGEventFlags(rawValue: 0x40), swallowsRelease: false),
        "consumes: la tecla de dictado nunca se traga el evento")
    // FN alone, unchanged: still swallowed, so Globe never also fires.
    expect(HoldKeyTap.consumes(
        code: 63, flags: .maskSecondaryFn, keyCode: 63,
        flag: .maskSecondaryFn, swallowsRelease: true),
        "consumes: FN sola sigue tragándose el evento")
    // Opción izquierda (raw bit 0x20) on the SAME keycode as Opción derecha
    // (61): the code matches but the side does not — must never count as
    // ours (15b-1 §11, the measured risk on a Spanish keyboard).
    expect(!HoldKeyTap.consumes(
        code: 61, flags: CGEventFlags(rawValue: 0x20), keyCode: 61,
        flag: CGEventFlags(rawValue: 0x40), swallowsRelease: true),
        "consumes: Opción izquierda no arma la tecla de Opción derecha")
}


final class CapturingSubmitter: JobSubmitter, @unchecked Sendable {
    private let lock = NSLock()
    private var _goals: [String] = []
    var goals: [String] { lock.withLock { _goals } }

    func submit(
        _ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        lock.withLock { _goals.append(handoff.goal) }
        return JobResult(output: "ok", isError: false)
    }
    func cancel() async {}
    func resolveApproval(requestId: String, approved: Bool) async {}
    var isBusy: Bool { get async { false } }
}
