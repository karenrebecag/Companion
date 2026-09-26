import CompanionCore
import CompanionServices
@testable import CompanionUI
import Foundation
import Testing

@Test @MainActor func voiceSessionTests() async {
    await testStartWithKeyListensRealtime()
    await testRealtimeParentToolAnsweredInline()
    await testClassicParentToolLoopsOneRound()
    await testRealtimeParentToolCardReachesTheThread()
    await testClassicFlushesFragmentBeforeNextRound()
    await testRealtimeTurnCarriesContext()
    await testClassicTurnCarriesContext()
    await testSessionMemoryNeverKeepsContext()
    await testClassicForeignURLAsksThroughTheSheet()
    await testRealtimeForeignURLAsksThroughTheSheet()
    await testRealtimeStaleTextDoesNotAuthorise()
    await testModelCannotApproveItsOwnURL()
    await testMuteAfterSpeechCommitsNativeText()
    await testUserTurnPreemptsActiveResponse()
    await testSegmentingEarDrivesTheTurn()
    await testStreamedReplyAccumulates()
    await testSpeakerEchoIsDroppedButRealInterruptionCuts()
    await testMuteWithoutSpeechDoesNotCommit()
    await testUnmuteClearsAudio()
    await testSpeakingSpeechStartedCancels()
    await testNoKeyClassicListen()
    await testDenyingSpeechIsNotBlamedOnTheVoice()
    await testOpenTimeoutFallsBackClassic()
    await testOfflineStaysInErrorWithoutFallback()
    await testEchoFreeBargeInWhileSpeaking()
    await testSilentMicFailsLoud()
    await testLiveMicSurvivesSilenceWatchdog()
    await testHangUpClosesTransport()
    await testNoBargeInWithoutAEC()
    await testFunctionCallRefusal()
}

@MainActor func testStartWithKeyListensRealtime() async {
    let h = makeVoiceHarness()
    await h.session.start()
    await pumpUntil("start: listening realtime") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .realtime
    }
    expect(h.transport.key == "sk-test", "start: abre con la key")
    expectEq(h.transport.url, RealtimeCodec.url(), "start: URL realtime")
    expect(h.mic.started, "start: micrófono arranca")
    expectEq(h.player.shared, false, "start: AEC off → player propio")
    expect(hasMessage(h.transport.sent, type: "session.update"),
           "start: manda session.update")
    expect(hasVoiceInSessionUpdate(h.transport.sent),
           "start: la primera update lleva voz")
}

/// 9j-1: with a segmenting ear the server's VAD owns the turns — a finished
/// segment commits AS the turn's text, with no local endpointer involved. And
/// over the agent, a one-word segment is a backchannel and is dropped.
@MainActor func testSegmentingEarDrivesTheTurn() async {
    let ear = ScriptedSegmentingEar()
    let h = makeVoiceHarness(realtimeEar: ear)
    await h.session.start()
    await pumpUntil("segmento: listening") { h.watch.latest.state == .listening }
    let before = h.transport.sent.count
    ear.yieldTurn(.speechStarted)
    await pumpUntil("segmento: speechOpen") { h.watch.latest.speechOpen }
    ear.yieldTurn(.finished(text: "crea prueba dos en el desktop"))
    await pumpUntil("segmento: el texto del segmento ES el turno") {
        Array(h.transport.sent.dropFirst(before))
            .contains { $0.contains("crea prueba dos en el desktop") }
    }
    expect(hasMessage(Array(h.transport.sent.dropFirst(before)),
                      type: "response.create"),
           "segmento: y pide la respuesta")

    // Un "ajá" sobre el agente no interrumpe ni se vuelve turno.
    h.transport.yield(.audioDelta(Data([0x01, 0x00])))
    await pumpUntil("segmento: speaking") { h.watch.latest.state == .speaking }
    let during = h.transport.sent.count
    ear.yieldTurn(.finished(text: "ajá"))
    await settle(0.1)
    expect(!Array(h.transport.sent.dropFirst(during))
        .contains { $0.contains("ajá") },
           "segmento: un backchannel de una palabra se tira")
}

/// The streamed bubble must GROW: showStream replaces what is on screen, so
/// the runtime accumulates deltas before showing — passing fragments made the
/// text flash one word at a time until the whole reply landed at once.
@MainActor func testStreamedReplyAccumulates() async {
    let h = makeVoiceHarness()
    await h.session.start()
    await pumpUntil("stream: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.responseCreated)
    h.transport.yield(.assistantTranscriptDelta("Hola, "))
    h.transport.yield(.assistantTranscriptDelta("¿qué "))
    h.transport.yield(.assistantTranscriptDelta("tal?"))
    await pumpUntil("stream: el texto crece acumulado") {
        h.thread.stream == "Hola, ¿qué tal?"
    }
}

/// 9j-6a: barge-in on SPEAKERS without AEC. The mic hears the agent; that
/// echo transcribes as the agent's own words and is dropped by text overlap.
/// Words that are NOT the agent's are the user really breaking in.
@MainActor func testSpeakerEchoIsDroppedButRealInterruptionCuts() async {
    let ear = ScriptedSegmentingEar()
    let h = makeVoiceHarness(realtimeEar: ear)
    await h.session.start()
    await pumpUntil("eco: listening") { h.watch.latest.state == .listening }
    // El agente habla: su transcript es la referencia del eco.
    h.transport.yield(.responseCreated)
    h.transport.yield(.assistantTranscriptDelta("te cuento la historia del faro"))
    h.transport.yield(.audioDelta(Data([0x01, 0x00])))
    await pumpUntil("eco: speaking") { h.watch.latest.state == .speaking }

    // Las bocinas devuelven las palabras del agente: eco, se tira.
    let before = h.transport.sent.count
    ear.yieldTurn(.finished(text: "cuento la historia del faro"))
    await settle(0.15)
    expect(!Array(h.transport.sent.dropFirst(before))
        .contains { $0.contains("historia del faro") },
           "eco: las palabras del agente no se vuelven turno del usuario")

    // Palabras que NO son del agente: interrupción real → cancela y commitea.
    ear.yieldTurn(.finished(text: "espera mejor hazlo en otra carpeta"))
    await pumpUntil("eco: la interrupción real se commitea") {
        Array(h.transport.sent.dropFirst(before))
            .contains { $0.contains("espera mejor hazlo") }
    }
    expect(hasMessage(Array(h.transport.sent.dropFirst(before)),
                      type: "response.cancel"),
           "eco: y corta al agente")
}

/// Wave 9i: muting mid-utterance commits the turn from the NATIVE transcript —
/// there is no audio buffer at OpenAI to commit any more.
@MainActor func testMuteAfterSpeechCommitsNativeText() async {
    let h = makeVoiceHarness()
    h.transcriber.stoppedText = "hola compa"
    await h.session.start()
    await pumpUntil("mute-speech: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.speechStarted)
    await pumpUntil("mute-speech: speechOpen") { h.watch.latest.speechOpen }
    let before = h.transport.sent.count
    await h.session.toggleMute()
    await pumpUntil("mute-speech: texto nativo enviado") {
        hasMessage(Array(h.transport.sent.dropFirst(before)),
                   type: "conversation.item.create")
    }
    let added = Array(h.transport.sent.dropFirst(before))
    expect(added.contains { $0.contains("hola compa") },
           "mute-speech: viaja el texto de Apple, no audio")
    expect(hasMessage(added, type: "response.create"),
           "mute-speech: response.create tras el texto")
    expect(h.watch.latest.pipeline == .realtime, "mute-speech: sigue realtime")
}

/// The server holds ONE response at a time; a user turn committed mid-response
/// used to be rejected ("already has an active response") and the turn's text
/// was left orphaned — "en mi desktop" answered a question nobody processed.
/// The funnel cancels the active response first: the user's voice outranks it.
@MainActor func testUserTurnPreemptsActiveResponse() async {
    let h = makeVoiceHarness()
    h.transcriber.stoppedText = "en mi desktop"
    await h.session.start()
    await pumpUntil("preempt: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.responseCreated)
    h.transport.yield(.speechStarted)
    await pumpUntil("preempt: speechOpen") { h.watch.latest.speechOpen }
    let before = h.transport.sent.count
    await h.session.toggleMute()  // commits the turn from the native text
    await pumpUntil("preempt: turno enviado") {
        hasMessage(Array(h.transport.sent.dropFirst(before)),
                   type: "response.create")
    }
    let added = Array(h.transport.sent.dropFirst(before))
    let cancelAt = added.firstIndex { $0.contains("response.cancel") }
    let createAt = added.firstIndex { $0.contains("response.create") }
    expect(cancelAt != nil, "preempt: cancela la respuesta activa")
    expect(cancelAt! < createAt!,
           "preempt: el cancel viaja ANTES del create del turno nuevo")
}

@MainActor func testMuteWithoutSpeechDoesNotCommit() async {
    let h = makeVoiceHarness()
    await h.session.start()
    await pumpUntil("mute-quiet: listening") { h.watch.latest.state == .listening }
    expect(!h.watch.latest.speechOpen, "mute-quiet: sin speechOpen")
    let before = h.transport.sent.count
    await h.session.toggleMute()
    await pumpUntil("mute-quiet: muted") { h.watch.latest.muted }
    await settle(0.4)  // past the commit's transcript-settle delay
    let added = Array(h.transport.sent.dropFirst(before))
    expect(!hasMessage(added, type: "conversation.item.create"),
           "mute-quiet: sin turno — no hay texto que mandar")
    expect(!hasMessage(added, type: "response.create"),
           "mute-quiet: sin response.create")
}

@MainActor func testUnmuteClearsAudio() async {
    let h = makeVoiceHarness()
    await h.session.start()
    await pumpUntil("unmute: listening") { h.watch.latest.state == .listening }
    await h.session.toggleMute()
    await pumpUntil("unmute: muted") { h.watch.latest.muted }
    let before = h.transport.sent.count
    await h.session.toggleMute()
    await pumpUntil("unmute: off") { !h.watch.latest.muted }
    let added = Array(h.transport.sent.dropFirst(before))
    expect(hasMessage(added, type: "input_audio_buffer.clear"),
           "unmute: tira el audio rancio")
}

@MainActor func testSpeakingSpeechStartedCancels() async {
    let h = makeVoiceHarness()
    await h.session.start()
    await pumpUntil("barge-in: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.audioDelta(Data([0x01, 0x00, 0x02, 0x00])))
    await pumpUntil("barge-in: speaking") { h.watch.latest.state == .speaking }
    expect(!h.player.played.isEmpty, "barge-in: el PCM llega al player")
    let before = h.transport.sent.count
    h.transport.yield(.speechStarted)
    await pumpUntil("barge-in: listening otra vez") {
        h.watch.latest.state == .listening && h.watch.latest.speechOpen
    }
    let added = Array(h.transport.sent.dropFirst(before))
    expect(hasMessage(added, type: "response.cancel"),
           "barge-in: response.cancel en el json enviado")
    expect(h.player.flushed, "barge-in: flush del player")
}

@MainActor func testNoKeyClassicListen() async {
    let h = makeVoiceHarness(key: nil, autoEvents: [])
    await h.session.start()
    await pumpUntil("classic: listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .classic
    }
    expectEq(h.transcriber.locale, "en-US",
             "classic: SFSpeech en el idioma del usuario")
    expect(h.transcriber.started, "classic: transcriber.start")
    expect(h.transport.key == nil, "classic: no abre realtime sin key")
    expect(h.transport.sent.isEmpty, "classic: no manda frames al WS")
}

/// Negar el reconocimiento de voz es negar un permiso de ENTRADA, y se
/// reportaba como `.speechEngine`, cuya copy manda a revisar la sintesis:
/// quien acababa de decir "no" a un dialogo del sistema era enviado al lugar
/// equivocado, sin una sola pista del permiso que habia negado.
@MainActor func testDenyingSpeechIsNotBlamedOnTheVoice() async {
    let h = makeVoiceHarness(key: nil, autoEvents: [])
    h.transcriber.grantsAuthorization = false
    await h.session.start()
    await pumpUntil("permiso: la sesión no arranca") {
        h.watch.latest.state == .error
    }
    expectEq(h.watch.latest.failure, .speechDenied,
             "permiso: el fallo dice que falta un permiso, no que se rompió el TTS")
    expect(!h.transcriber.started,
           "permiso: sin autorización no se arma el reconocedor")
}

@MainActor func testOpenTimeoutFallsBackClassic() async {
    // Online: the realtime server did not answer, but classic still works.
    let h = makeVoiceHarness(autoEvents: [], readyTimeout: 0.05)
    await h.session.start()
    await pumpUntil("timeout: fallback classic") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .classic
    }
    expectEq(h.transcriber.locale, "en-US", "timeout: arma el transcriber")
    expect(h.transcriber.started, "timeout: transcriber.start")
    // El aviso ya NO sale de aquí: Services escribía su propia redacción del
    // fallo además de la del catálogo, y el usuario leía dos mensajes para un
    // solo problema. El dueño es VoiceViewModel, que lo emite una vez y en el
    // idioma del catálogo (VoiceViewModelTests lo exige).
    expect(h.thread.status.isEmpty,
           "timeout: Services no escribe copy de usuario")
}

@MainActor func testOfflineStaysInErrorWithoutFallback() async {
    let h = makeVoiceHarness(autoEvents: [], readyTimeout: 0.05, online: false)
    await h.session.start()
    await pumpUntil("offline: estado de error") {
        h.watch.latest.state == .error
    }
    expectEq(h.watch.latest.failure, .networkUnavailable,
             "offline: la razón es la falta de red")
    // 12c: the ear comes up with the press; a session that dies offline
    // takes it down again, and the classic path is never armed.
    expect(h.transcriber.stops >= 1,
           "offline: el oído que arrancó con la sesión se apaga con ella")
    expect(h.watch.latest.pipeline != .classic,
           "offline: no cambia de pipeline")
}

@MainActor func testSilentMicFailsLoud() async {
    let h = makeVoiceHarness(micSilenceTimeout: 0.05)
    h.mic.receivedBufferValue = false
    await h.session.start()
    await pumpUntil("mic-silencio: error visible") {
        h.watch.latest.state == .error
    }
    expectEq(h.watch.latest.failure, .micSilent,
             "mic-silencio: la razón es que no entregó audio")
}

@MainActor func testLiveMicSurvivesSilenceWatchdog() async {
    let h = makeVoiceHarness(micSilenceTimeout: 0.05)
    await h.session.start()
    await pumpUntil("mic-vivo: listening") { h.watch.latest.state == .listening }
    await settle(0.15)
    expectEq(h.watch.latest.state, .listening,
             "mic-vivo: el watchdog no dispara con buffers llegando")
}

@MainActor func testHangUpClosesTransport() async {
    let h = makeVoiceHarness()
    await h.session.start()
    await pumpUntil("hangup: listening") { h.watch.latest.state == .listening }
    await h.session.hangUp()
    await pumpUntil("hangup: idle") { h.watch.latest.state == .idle }
    expect(h.transport.closed, "hangup: cierra el transporte")
    expect(h.player.stopped, "hangup: para el player")
    expect(h.mic.stopped, "hangup: para el mic")
}

/// Wave 9i: the mic never reaches OpenAI, so barge-in is a LOCAL decision. On
/// echo-free output (headphones), a vetted frame while the agent speaks cuts
/// it — a `response.cancel`. A single loud frame is a backchannel and does not.
@MainActor func testEchoFreeBargeInWhileSpeaking() async {
    let h = makeVoiceHarness(echoFreeOutput: true)
    await h.session.start()
    await pumpUntil("echo-free: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.audioDelta(Data([0x03, 0x00])))
    await pumpUntil("echo-free: speaking") { h.watch.latest.state == .speaking }
    let before = h.transport.sent.count

    // A single loud frame is a backchannel ("ajá") — must NOT cut the agent.
    h.mic.yield(MicFrame(pcm16le24k: Data([0x11, 0x00]), rms: 0.5))
    await settle(0.05)
    expectEq(cancelCount(Array(h.transport.sent.dropFirst(before))), 0,
             "echo-free: un asentimiento corto no interrumpe")

    // Sustained speech barges in: the agent is cancelled.
    for _ in 0 ..< BackchannelGate.defaultRequiredFrames {
        h.mic.yield(MicFrame(pcm16le24k: Data([0x11, 0x00]), rms: 0.5))
    }
    await pumpUntil("echo-free: hablar sostenido sí interrumpe") {
        cancelCount(Array(h.transport.sent.dropFirst(before))) >= 1
    }
}

/// Without AEC the mic hears the agent (room echo), so sustained frames over
/// the agent must NOT be taken as the user barging in — that would be the
/// agent cutting itself off. No `response.cancel`.
@MainActor func testNoBargeInWithoutAEC() async {
    let h = makeVoiceHarness()
    await h.session.start()
    await pumpUntil("echo: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.audioDelta(Data([0x03, 0x00])))
    await pumpUntil("echo: speaking") { h.watch.latest.state == .speaking }
    let before = h.transport.sent.count

    for _ in 0 ..< BackchannelGate.defaultRequiredFrames * 2 {
        h.mic.yield(MicFrame(pcm16le24k: Data([0x11, 0x00]), rms: 0.5))
    }
    await settle(0.06)
    expectEq(cancelCount(Array(h.transport.sent.dropFirst(before))), 0,
             "echo: sin AEC, hablar sobre el agente no interrumpe (podría ser eco)")
}

@MainActor func testFunctionCallRefusal() async {
    let h = makeVoiceHarness()
    await h.session.start()
    await pumpUntil("fn: listening") { h.watch.latest.state == .listening }
    let before = h.transport.sent.count
    h.transport.yield(
        .functionCall(name: "delegate", arguments: #"{"goal":"x"}"#, callId: "c1"))
    await pumpUntil("fn: output enviado") {
        h.transport.sent.dropFirst(before).contains {
            $0.contains("function_call_output")
        }
    }
    let added = Array(h.transport.sent.dropFirst(before))
    expect(added.contains { $0.contains("Jobs will be available") },
           "fn: negativa de encargos")
    expect(added.contains { $0.contains("c1") }, "fn: call_id viaja")
    expect(hasMessage(added, type: "response.create"),
           "fn: response.create tras el output")
    expect(!h.watch.latest.awaitingExecutor, "fn: no dispara delegateCallStarted")
}

func messageType(_ json: String) -> String? {
    guard let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return obj["type"] as? String
}

func hasMessage(_ sent: [String], type: String) -> Bool {
    sent.contains { messageType($0) == type }
}

private func cancelCount(_ sent: [String]) -> Int {
    sent.filter { messageType($0) == "response.cancel" }.count
}

private func hasVoiceInSessionUpdate(_ sent: [String]) -> Bool {
    for json in sent where messageType(json) == "session.update" {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let session = obj["session"] as? [String: Any],
              let audio = session["audio"] as? [String: Any],
              let output = audio["output"] as? [String: Any],
              let voice = output["voice"] as? String
        else { continue }
        if !voice.isEmpty { return true }
    }
    return false
}

// MARK: - Wave 10b: el padre actúa por voz

/// Realtime: el server hace el loop; el cliente responde el function call en
/// línea — sin encargo, sin hoja — y pide la siguiente respuesta.
@MainActor func testRealtimeParentToolAnsweredInline() async {
    let opener = FakeWorkspaceOpener()
    let h = makeVoiceHarness(parentTools: ParentToolRunner(workspace: opener))
    // 10c 3D: a URL opens unasked only when the user said it.
    h.transcriber.stoppedText = "abre example.com"
    await h.session.start()
    await pumpUntil("padre rt: listening") { h.watch.latest.state == .listening }
    expect(h.transport.sent.contains { $0.contains("session.update") && $0.contains("open_app") },
           "padre rt: session.update declara las tools del padre")
    expect(h.transport.sent.contains { $0.contains("session.update") && $0.contains("hands on this Mac") },
           "padre rt: y las instrucciones dicen que tiene manos")
    h.transport.yield(.speechStarted)
    await pumpUntil("padre rt: speechOpen") { h.watch.latest.speechOpen }
    await h.session.toggleMute()
    await pumpUntil("padre rt: texto comprometido") { hasMessage(h.transport.sent, type: "conversation.item.create") }
    let before = h.transport.sent.count
    h.transport.yield(.functionCall(
        name: "open_url", arguments: #"{"url":"https://example.com"}"#, callId: "c9"))
    await pumpUntil("padre rt: output enviado") {
        h.transport.sent.dropFirst(before).contains { $0.contains("function_call_output") }
    }
    let added = Array(h.transport.sent.dropFirst(before))
    expectEq(opener.openedURLs.map(\.absoluteString), ["https://example.com"],
             "padre rt: el opener fue llamado")
    expect(added.contains { $0.contains("c9") && $0.contains("example.com") },
           "padre rt: el output responde al call_id con el resultado")
    expect(hasMessage(added, type: "response.create"), "padre rt: response.create después")
    expect(!h.watch.latest.awaitingExecutor, "padre rt: no es un encargo")
    expect(h.thread.status.contains { $0.contains("example.com") },
           "padre rt: el hilo registra qué hizo la app sola")
}

/// Clásico: tool call → se ejecuta → segunda ronda con el resultado en el
/// historial → la frase de la segunda ronda llega al sintetizador.
@MainActor func testClassicParentToolLoopsOneRound() async {
    let opener = FakeWorkspaceOpener(installed: ["Safari"])
    let h = makeVoiceHarness(key: nil, parentTools: ParentToolRunner(workspace: opener))
    h.chat.rounds = [
        [.toolCalls([ToolCallRef(id: "c1", name: "open_app", arguments: #"{"name":"Safari"}"#)])],
        [.text("Listo, abrí Safari.")],
    ]
    h.transcriber.stoppedText = "abre safari"
    await h.session.start()
    await pumpUntil("padre cl: listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .classic
    }
    await h.session.advance()
    // 15d-5: the first utterance now ends at the comma.
    await pumpUntil("padre cl: habló la segunda ronda") {
        h.synth.queue == ["Listo,", "abrí Safari."]
    }
    expectEq(opener.openedApps, ["Safari"], "padre cl: se abrió")
    expectEq(h.chat.histories.count, 2, "padre cl: dos rondas")
    expect(h.chat.histories[1].contains { $0.role == .tool && $0.toolCallID == "c1" },
           "padre cl: la ronda 2 vio el resultado")
    expect(h.chat.toolsSeen.map(\.name).contains("open_app"), "padre cl: anuncia open_app")
    expect(!h.chat.toolsSeen.map(\.name).contains("delegate"),
           "padre cl: sin jobs no anuncia delegate")
    expect(h.thread.status.contains { $0.contains("Safari") }, "padre cl: línea de estado")
}

/// La tarjeta de `find_places` viaja por el mismo seam que la de un encargo
/// (`JobEvent.card` → `receiveJobEvent`): el mapa aparece en voz sin encargo.
@MainActor func testRealtimeParentToolCardReachesTheThread() async {
    let place = FoundPlace(name: "Cinépolis Reforma", address: "Reforma 222", lat: 19.43, lng: -99.16)
    let box = JobEventBox()
    let h = makeVoiceHarness(
        parentTools: ParentToolRunner(workspace: FakeWorkspaceOpener(), places: FakePlaces(found: [place])),
        onJobEvent: { box.append($0) })
    await h.session.start()
    await pumpUntil("card rt: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.functionCall(
        name: "find_places", arguments: #"{"query":"cines cerca de Reforma"}"#, callId: "c5"))
    await pumpUntil("card rt: tarjeta") { box.events.contains { if case .card = $0 { true } else { false } } }
    expect(box.events.contains { if case .card(let card) = $0, case .locations(let b) = card.payload {
        b.locations.map(\.name) == ["Cinépolis Reforma"] } else { false } },
           "card rt: la tarjeta lleva el lugar encontrado")
    expect(h.transport.sent.contains { $0.contains("function_call_output") && $0.contains("Cinépolis") },
           "card rt: el modelo lee el nombre, no la coordenada")
}

/// Un fragmento sin punto antes de la acción se dice antes de la siguiente
/// ronda, no pegado a ella: "Voy a abrir Safari" + "Listo." son dos frases.
@MainActor func testClassicFlushesFragmentBeforeNextRound() async {
    let opener = FakeWorkspaceOpener(installed: ["Safari"])
    let h = makeVoiceHarness(key: nil, parentTools: ParentToolRunner(workspace: opener))
    h.chat.rounds = [
        [.text("Voy a abrir Safari"),
         .toolCalls([ToolCallRef(id: "c1", name: "open_app", arguments: #"{"name":"Safari"}"#)])],
        [.text("Listo.")],
    ]
    h.transcriber.stoppedText = "abre safari"
    await h.session.start()
    await pumpUntil("flush cl: listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .classic
    }
    await h.session.advance()
    await pumpUntil("flush cl: dos frases") { h.synth.queue.count >= 2 }
    expectEq(h.synth.queue, ["Voy a abrir Safari", "Listo."], "flush cl: frases separadas, en orden")
}

final class JobEventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [JobEvent] = []
    var events: [JobEvent] { lock.lock(); defer { lock.unlock() }; return _events }
    func append(_ event: JobEvent) { lock.lock(); _events.append(event); lock.unlock() }
}

// MARK: - Wave 10a: el turno de voz lleva contexto

/// El item de usuario que va al server lleva el bloque; el hilo recibe el
/// texto crudo; la fuente es voz.
@MainActor func testRealtimeTurnCarriesContext() async {
    let sensor = FakeContextSensor(TurnContext(source: .typed, focusedApp: "Notes"))
    let h = makeVoiceHarness(sensor: sensor)
    h.transcriber.stoppedText = "hola compa"
    await h.session.start()
    await pumpUntil("ctx rt: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.speechStarted)
    await pumpUntil("ctx rt: speechOpen") { h.watch.latest.speechOpen }
    let before = h.transport.sent.count
    await h.session.toggleMute()
    await pumpUntil("ctx rt: item enviado") {
        hasMessage(Array(h.transport.sent.dropFirst(before)), type: "conversation.item.create")
    }
    let item = h.transport.sent.dropFirst(before).first { $0.contains("conversation.item.create") } ?? ""
    expect(item.contains("<context source=\\\"voice\\\"") || item.contains("<context source=\"voice\""),
           "ctx rt: el item lleva el bloque con fuente voz")
    expect(item.contains("Notes") && item.contains("hola compa"), "ctx rt: app y texto")
    expect(item.contains("how_to_reply"), "ctx rt: la pista de respuesta corta va en el turno")
    expectEq(h.thread.turns.last?.content, "hola compa", "ctx rt: el hilo recibe el texto crudo")
    expect(!sensor.calls.isEmpty, "ctx rt: se sensó")
}

@MainActor func testClassicTurnCarriesContext() async {
    let sensor = FakeContextSensor(TurnContext(source: .typed, focusedApp: "Notes"))
    let h = makeVoiceHarness(key: nil, sensor: sensor)
    h.chat.rounds = [[.text("Listo.")]]
    h.transcriber.stoppedText = "resume esto"
    await h.session.start()
    await pumpUntil("ctx cl: listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .classic
    }
    await h.session.advance()
    await pumpUntil("ctx cl: habló") { h.synth.queue.contains("Listo.") }
    let last = h.chat.histories.first?.last
    expect(last?.role == .user && last?.content.contains("<context source=\"voice\"") == true,
           "ctx cl: el último turno lleva el bloque con fuente voz")
    expect(last?.content.hasSuffix("resume esto") == true, "ctx cl: el texto al final")
    expect(h.thread.turns.contains { $0.role == .user && $0.content == "resume esto" },
           "ctx cl: el hilo recibe el texto crudo")
    expect(h.thread.turns.contains { $0.role == .assistant && $0.content.contains("Listo.") },
           "ctx cl: y la respuesta")
}

/// La nota de sesión (9j-2, solo la cierra el pipeline realtime) toma
/// `memoryTurns()`: las palabras, nunca la compacta con la app al frente.
@MainActor func testSessionMemoryNeverKeepsContext() async {
    let store = RecordingMemoryStore()
    let sensor = FakeContextSensor(TurnContext(source: .typed, focusedApp: "1Password"))
    let h = makeVoiceHarness(sensor: sensor, memoryStore: store)
    h.transcriber.stoppedText = "resume esto"
    await h.session.start()
    await pumpUntil("mem: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.speechStarted)
    await pumpUntil("mem: speechOpen") { h.watch.latest.speechOpen }
    let before = h.transport.sent.count
    await h.session.toggleMute()
    await pumpUntil("mem: item enviado") {
        hasMessage(Array(h.transport.sent.dropFirst(before)), type: "conversation.item.create")
    }
    expect(h.thread.history.contains { $0.content.contains("[voice · 1Password]") },
           "mem: el historial del modelo sí lleva la compacta (como el real)")
    await h.session.hangUp()
    await pumpUntil("mem: nota escrita") { !store.sessions.isEmpty }
    let note = store.sessions.joined()
    expect(note.contains("resume esto"), "mem: la nota conserva la petición")
    expect(!note.contains("1Password") && !note.contains("[voice") && !note.contains("[voz"),
           "mem: la nota no lleva la app ni la compacta")
}

final class RecordingMemoryStore: MemoryStore, @unchecked Sendable {
    private let lock = NSLock()
    private var _sessions: [String] = []
    var sessions: [String] { lock.lock(); defer { lock.unlock() }; return _sessions }
    func load() -> MemoryPack { MemoryPack(core: "", recentSessions: [], notes: []) }
    func appendSession(_ summary: String) throws { lock.lock(); _sessions.append(summary); lock.unlock() }
}

// MARK: - Wave 10c 3D: open_url con puerta, por voz

/// 27. Clásico: un host que no se dijo → la solicitud sale por el mismo seam
/// que la hoja de los encargos y queda pendiente para el "sí" hablado; nada
/// se abre hasta resolver el actor.
@MainActor func testClassicForeignURLAsksThroughTheSheet() async {
    let opener = FakeWorkspaceOpener()
    let approvals = FakeApprovals()
    let box = JobEventBox()
    let h = makeVoiceHarness(
        key: nil, parentTools: ParentToolRunner(workspace: opener),
        onJobEvent: { box.append($0) }, approvals: approvals)
    h.chat.rounds = [
        [.toolCalls([ToolCallRef(id: "c1", name: "open_url", arguments: #"{"url":"https://evil.example/x"}"#)])],
        [.text("Listo.")],
    ]
    h.transcriber.stoppedText = "resume esto"
    await h.session.start()
    await pumpUntil("puerta cl: listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .classic
    }
    // `advance()` runs the classic turn inline and the turn is parked on the
    // sheet: awaiting it here would be the deadlock the sheet resolves.
    let turn = Task { await h.session.advance() }
    await pumpUntil("puerta cl: solicitud") {
        box.events.contains { if case .approvalRequested(let r) = $0 { r.toolName == "open_url" } else { false } }
    }
    expect(opener.openedURLs.isEmpty, "puerta cl: nada abierto mientras espera")
    let request = await approvals.waiting
    expect(request != nil, "puerta cl: el actor tiene la solicitud")
    _ = await approvals.resolve(requestId: request?.requestId ?? "", approved: true)
    await pumpUntil("puerta cl: abre") { !opener.openedURLs.isEmpty }
    expectEq(opener.openedURLs.map(\.absoluteString), ["https://evil.example/x"], "puerta cl: con sí, abre")
    await pumpUntil("puerta cl: segunda ronda") { h.synth.queue.contains("Listo.") }
    await turn.value
}

/// Realtime: mismo caso; el function output espera a la decisión y con
/// "no" lleva la instrucción `denied_by_user`.
@MainActor func testRealtimeForeignURLAsksThroughTheSheet() async {
    let opener = FakeWorkspaceOpener()
    let approvals = FakeApprovals()
    let box = JobEventBox()
    let h = makeVoiceHarness(
        parentTools: ParentToolRunner(workspace: opener),
        onJobEvent: { box.append($0) }, approvals: approvals)
    h.transcriber.stoppedText = "resume esto"
    await h.session.start()
    await pumpUntil("puerta rt: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.speechStarted)
    await pumpUntil("puerta rt: speechOpen") { h.watch.latest.speechOpen }
    await h.session.toggleMute()
    await pumpUntil("puerta rt: item enviado") { hasMessage(h.transport.sent, type: "conversation.item.create") }
    let before = h.transport.sent.count
    h.transport.yield(.functionCall(
        name: "open_url", arguments: #"{"url":"https://evil.example/x"}"#, callId: "c9"))
    await pumpUntil("puerta rt: solicitud") {
        box.events.contains { if case .approvalRequested(let r) = $0 { r.toolName == "open_url" } else { false } }
    }
    expect(opener.openedURLs.isEmpty, "puerta rt: nada abierto")
    expect(!h.transport.sent.dropFirst(before).contains { $0.contains("function_call_output") },
           "puerta rt: el output espera a la decisión")
    let request = await approvals.waiting
    _ = await approvals.resolve(requestId: request?.requestId ?? "", approved: false)
    await pumpUntil("puerta rt: output") {
        h.transport.sent.dropFirst(before).contains { $0.contains("function_call_output") }
    }
    expect(opener.openedURLs.isEmpty, "puerta rt: con no, no abre")
    expect(h.transport.sent.dropFirst(before).contains { $0.contains("denied_by_user") },
           "puerta rt: el modelo lee la instrucción")
}

/// Code review (MEDIO/ALTO): `lastUserText` quedaba viejo; una mención de
/// otro turno autorizaba una URL nueva. Empezar a hablar borra el texto de
/// referencia; un turno sin texto comprometido falla cerrado.
@MainActor func testRealtimeStaleTextDoesNotAuthorise() async {
    let opener = FakeWorkspaceOpener()
    let approvals = FakeApprovals()
    let box = JobEventBox()
    let h = makeVoiceHarness(
        parentTools: ParentToolRunner(workspace: opener),
        onJobEvent: { box.append($0) }, approvals: approvals)
    h.transcriber.stoppedText = "abre example.com"
    await h.session.start()
    await pumpUntil("viejo: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.speechStarted)
    await pumpUntil("viejo: speechOpen") { h.watch.latest.speechOpen }
    await h.session.toggleMute()
    await pumpUntil("viejo: texto comprometido") { hasMessage(h.transport.sent, type: "conversation.item.create") }
    h.transport.yield(.responseDone)
    // A new utterance starts and nothing gets committed (server-side turn).
    h.transport.yield(.speechStarted)
    await settle(0.05)
    h.transport.yield(.functionCall(
        name: "open_url", arguments: #"{"url":"https://example.com/late"}"#, callId: "c1"))
    await pumpUntil("viejo: pide permiso") {
        box.events.contains { if case .approvalRequested(let r) = $0 { r.toolName == "open_url" } else { false } }
    }
    expect(opener.openedURLs.isEmpty, "viejo: la mención del turno anterior no autoriza")
}

/// Security review (verificado, sin test): el modelo no puede pedir
/// `open_url` y contestarse `resolve_approval(true)` en la misma respuesta.
/// Los eventos van en serie: la puerta bloquea hasta la decisión humana.
@MainActor func testModelCannotApproveItsOwnURL() async {
    let opener = FakeWorkspaceOpener()
    let approvals = FakeApprovals()
    let box = JobEventBox()
    let h = makeVoiceHarness(
        jobs: ApprovingSubmitter(),
        parentTools: ParentToolRunner(workspace: opener),
        onJobEvent: { box.append($0) }, approvals: approvals)
    await h.session.start()
    await pumpUntil("auto: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.functionCall(
        name: "open_url", arguments: #"{"url":"https://evil.example/x"}"#, callId: "c1"))
    h.transport.yield(.functionCall(
        name: "resolve_approval", arguments: #"{"approved":true}"#, callId: "c2"))
    await pumpUntil("auto: pide permiso") {
        box.events.contains { if case .approvalRequested(let r) = $0 { r.toolName == "open_url" } else { false } }
    }
    await settle(0.15)
    expect(opener.openedURLs.isEmpty, "auto: el resolve del modelo no abrió nada")
    expect(await approvals.resolutions.isEmpty, "auto: nadie resolvió la petición")
    let request = await approvals.waiting
    _ = await approvals.resolve(requestId: request?.requestId ?? "", approved: false)
    await pumpUntil("auto: output de la negación") { h.transport.sent.contains { $0.contains("denied_by_user") } }
    await pumpUntil("auto: el resolve tardío no encuentra nada") {
        h.transport.sent.contains { $0.contains("c2") && $0.contains("function_call_output") }
    }
    expect(opener.openedURLs.isEmpty, "auto: sigue sin abrir")
}
