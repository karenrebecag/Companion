import CompanionCore
import Foundation

@MainActor func turnMachineTests() {
    testTurnMachineStartConnect()
    testTurnMachineSpeechCycle()
    testTurnMachineBargeIn()
    testTurnMachineMute()
    testTurnMachineHangUpAndError()
}

@discardableResult
private func apply(
    _ machine: inout TurnMachine, _ event: TurnEvent, at now: TimeInterval = 0
) -> [TurnEffect] {
    machine.handle(event, at: now)
}

private func armRealtime(_ machine: inout TurnMachine) {
    _ = apply(&machine, .startVoice(preferRealtime: true))
    _ = apply(&machine, .realtimeSessionReady)
}

private func armClassicSpeaking(_ machine: inout TurnMachine) {
    _ = apply(&machine, .startVoice(preferRealtime: false))
    _ = apply(&machine, .classicListenArmed)
    _ = apply(&machine, .endpointFinished)
    _ = apply(&machine, .firstSentence)
}

@MainActor func testTurnMachineStartConnect() {
    var m = TurnMachine()
    expectEq(m.snapshot, .idle, "start: snapshot idle de fábrica")
    expect(!m.isEchoGuarded(at: 0), "start: sin eco-guard en idle")

    let opened = apply(&m, .startVoice(preferRealtime: true), at: 1)
    expectEq(opened, [.openRealtimeSession],
             "start: idle + realtime abre la sesión")
    expectEq(m.snapshot.state, .connecting, "start: pasa a connecting")
    expectEq(m.snapshot.pipeline, .realtime, "start: pipeline realtime")
    expect(!m.snapshot.muted, "start: unmute al conectar")
    expect(m.snapshot.pipeline != nil, "start: pipeline no es nil en connecting")

    let ignored = apply(&m, .startVoice(preferRealtime: true), at: 2)
    expectEq(ignored, [], "start: connecting ignora un segundo startVoice")
    expectEq(m.snapshot.state, .connecting, "start: sigue connecting")

    let ignoredAdvance = apply(&m, .advance(hasSpeech: true), at: 2)
    expectEq(ignoredAdvance, [], "start: connecting ignora advance")
    expectEq(apply(&m, .startVoice(preferRealtime: false)), [],
             "start: connecting ignora startVoice(false)")

    let ready = apply(&m, .realtimeSessionReady, at: 3)
    expectEq(ready, [], "start: ready no dispara efectos")
    expectEq(m.snapshot.state, .listening, "start: ready → listening")
    expectEq(m.snapshot.pipeline, .realtime, "start: sigue realtime")
    expect(!m.snapshot.muted, "start: ready deja muted=false")

    var classic = TurnMachine()
    let wait = apply(&classic, .startVoice(preferRealtime: false))
    expectEq(wait, [.requestClassicListen],
             "start: classic pide el mic y espera")
    expectEq(classic.snapshot.state, .idle, "start: classic se queda idle")
    expect(classic.snapshot.pipeline == nil, "start: idle no lleva pipeline")
    _ = apply(&classic, .classicListenArmed)
    expectEq(classic.snapshot.state, .listening, "start: armed → listening")
    expectEq(classic.snapshot.pipeline, .classic, "start: pipeline classic")

    var fromError = TurnMachine(snapshot: TurnSnapshot(state: .error))
    let retry = apply(&fromError, .startVoice(preferRealtime: true))
    expectEq(retry, [.openRealtimeSession],
             "start: error + realtime reabre connecting")
    expectEq(fromError.snapshot.state, .connecting, "start: error se recupera")

    var typed = TurnMachine()
    let submit = apply(&typed, .typedSubmit)
    expectEq(submit, [.submitUtterance], "start: typedSubmit manda el turno")
    expectEq(typed.snapshot.state, .thinking, "start: typed → thinking")
    expect(typed.snapshot.typedTurn, "start: typedTurn queda marcado")
    expect(typed.snapshot.pipeline == nil, "start: typed no abre pipeline")
}

@MainActor func testTurnMachineSpeechCycle() {
    var m = TurnMachine()
    armRealtime(&m)

    let started = apply(&m, .serverSpeechStarted, at: 10)
    expectEq(started, [], "ciclo: speechStarted en listening no cancela")
    expect(m.snapshot.speechOpen, "ciclo: speechOpen al oír")
    expectEq(m.snapshot.state, .listening, "ciclo: sigue listening")

    let stopped = apply(&m, .serverSpeechStopped, at: 11)
    expectEq(stopped, [], "ciclo: speechStopped no dispara I/O")
    expectEq(m.snapshot.state, .thinking, "ciclo: speechStopped → thinking")
    expect(!m.snapshot.speechOpen, "ciclo: speechOpen cierra al parar")

    let audio = apply(&m, .agentAudioStarted, at: 12)
    expectEq(audio, [], "ciclo: agentAudioStarted no dispara I/O")
    expectEq(m.snapshot.state, .speaking, "ciclo: audio del agente → speaking")

    let now: TimeInterval = 20
    let drained = apply(&m, .playerDrained, at: now)
    expectEq(drained, [], "ciclo: playerDrained no dispara I/O")
    expectEq(m.snapshot.state, .listening, "ciclo: drained → listening")
    expect(m.isEchoGuarded(at: now),
           "ciclo: eco-guard activo justo al drenar")
    expect(m.isEchoGuarded(at: now + 0.349),
           "ciclo: eco-guard cubre casi 350 ms")
    expect(!m.isEchoGuarded(at: now + TurnMachine.echoGuardDuration),
           "ciclo: eco-guard caduca a los 0.35 s")
    expect(!m.isEchoGuarded(at: now + 0.35),
           "ciclo: en el borde ya no está guardado")

    _ = apply(&m, .serverSpeechStopped, at: 21)
    _ = apply(&m, .agentAudioStarted, at: 22)
    expectEq(m.snapshot.state, .speaking, "ciclo: vuelve a speaking")
    let completed = apply(&m, .responseCompleted(hasPendingAudio: false), at: 23)
    expectEq(completed, [], "ciclo: responseCompleted(false) no dispara I/O")
    expectEq(m.snapshot.state, .listening,
             "ciclo: responseCompleted sin cola → listening")
    expect(m.isEchoGuarded(at: 23),
           "ciclo: responseCompleted(false) arma el eco-guard")

    _ = apply(&m, .agentAudioStarted, at: 24)
    let pending = apply(&m, .responseCompleted(hasPendingAudio: true), at: 24)
    expectEq(pending, [], "ciclo: con audio pendiente no cambia")
    expectEq(m.snapshot.state, .speaking,
             "ciclo: responseCompleted(true) espera al player")

    _ = apply(&m, .playerDrained, at: 25)
    _ = apply(&m, .serverSpeechStopped, at: 26)
    expectEq(m.snapshot.state, .thinking, "ciclo: de nuevo thinking")
    _ = apply(&m, .delegateCallStarted, at: 26)
    expect(m.snapshot.awaitingExecutor, "ciclo: delegate deja awaiting")
    expectEq(m.snapshot.state, .thinking, "ciclo: delegate se queda thinking")
    let held = apply(&m, .responseCompleted(hasPendingAudio: false), at: 27)
    expectEq(held, [], "ciclo: awaitingExecutor ignora responseCompleted")
    expectEq(m.snapshot.state, .thinking, "ciclo: no vuelve a listening")
    let sent = apply(&m, .functionOutputSent, at: 28)
    expectEq(sent, [], "ciclo: functionOutput no dispara I/O")
    expect(!m.snapshot.awaitingExecutor, "ciclo: output libera awaiting")
    expectEq(m.snapshot.state, .thinking, "ciclo: output → thinking")
    _ = apply(&m, .responseCompleted(hasPendingAudio: false), at: 29)
    expectEq(m.snapshot.state, .listening,
             "ciclo: responseCompleted sin awaiting → listening")

    var classic = TurnMachine()
    _ = apply(&classic, .startVoice(preferRealtime: false))
    _ = apply(&classic, .classicListenArmed)
    let end = apply(&classic, .endpointFinished)
    expectEq(end, [.submitUtterance], "ciclo: endpoint finished manda el turno")
    expectEq(classic.snapshot.state, .thinking, "ciclo: classic → thinking")
    let sentence = apply(&classic, .firstSentence)
    expectEq(sentence, [.beginSpeechStream], "ciclo: firstSentence abre TTS")
    expectEq(classic.snapshot.state, .speaking, "ciclo: firstSentence → speaking")
    expect(classic.snapshot.streamingStarted, "ciclo: streamingStarted")
    expectEq(apply(&classic, .firstSentence), [],
             "ciclo: firstSentence repetido no reabre el stream")

    let reply = apply(&classic, .replyCompleted)
    expectEq(reply, [.finishSpeechStream],
             "ciclo: reply con stream ya abierto solo cierra")
    expect(classic.snapshot.inConversation, "ciclo: una respuesta abre conversación")
}

@MainActor func testTurnMachineBargeIn() {
    let saying = "te cuento la historia"
    var m = TurnMachine()
    armClassicSpeaking(&m)
    expectEq(m.snapshot.state, .speaking, "barge-in: parte speaking")
    expectEq(m.snapshot.pipeline, .classic, "barge-in: pipeline classic")

    let echo = apply(&m, .heardWhileSpeaking(heard: "la historia",
                                             agentSaying: saying))
    expectEq(echo, [], "barge-in: el eco no interrumpe")
    expectEq(m.snapshot.state, .speaking, "barge-in: eco se queda speaking")
    expect(!m.snapshot.interruptionPending, "barge-in: eco no marca pending")

    let filler = apply(&m, .heardWhileSpeaking(heard: "mmm",
                                               agentSaying: saying))
    expectEq(filler, [], "barge-in: una muletilla no interrumpe")
    expectEq(m.snapshot.state, .speaking, "barge-in: <2 palabras se queda")

    let empty = apply(&m, .heardWhileSpeaking(heard: "", agentSaying: saying))
    expectEq(empty, [], "barge-in: vacío no interrumpe")

    let real = apply(&m, .heardWhileSpeaking(heard: "oye espera",
                                             agentSaying: saying))
    expectEq(real, [.cancelAgentOutput],
             "barge-in: interrupción real cancela al agente")
    expectEq(m.snapshot.state, .listening, "barge-in: real → listening")
    expect(m.snapshot.interruptionPending, "barge-in: real marca pending")

    var unicode = TurnMachine()
    armClassicSpeaking(&unicode)
    let accented = apply(&unicode, .heardWhileSpeaking(
        heard: "oye espera ya entendí", agentSaying: saying))
    expectEq(accented, [.cancelAgentOutput],
             "barge-in: unicode propio sí interrumpe")

    var rt = TurnMachine()
    armRealtime(&rt)
    _ = apply(&rt, .agentAudioStarted)
    expectEq(rt.snapshot.state, .speaking, "barge-in: realtime speaking")
    let tap = apply(&rt, .advance(hasSpeech: false))
    expectEq(tap, [.cancelAgentOutput],
             "barge-in: tap en speaking realtime cancela")
    expectEq(rt.snapshot.state, .listening, "barge-in: tap → listening")

    _ = apply(&rt, .agentAudioStarted)
    let server = apply(&rt, .serverSpeechStarted)
    expectEq(server, [.cancelAgentOutput],
             "barge-in: speechStarted en speaking cancela")
    expectEq(rt.snapshot.state, .listening, "barge-in: server barge → listening")
    expect(rt.snapshot.speechOpen, "barge-in: speechOpen queda armado")

    let heardOnRealtime = apply(&rt, .heardWhileSpeaking(
        heard: "oye espera", agentSaying: saying))
    expectEq(heardOnRealtime, [],
             "barge-in: heardWhileSpeaking no aplica en realtime")

    var idle = TurnMachine()
    expectEq(apply(&idle, .heardWhileSpeaking(heard: "oye espera",
                                              agentSaying: saying)),
             [], "barge-in: idle ignora heardWhileSpeaking")
}

@MainActor func testTurnMachineMute() {
    var m = TurnMachine()
    expectEq(apply(&m, .toggleMute(hasPendingAudio: false)), [],
             "mute: idle no hace nada")
    expect(!m.snapshot.muted, "mute: idle no voltea muted")

    var classic = TurnMachine()
    _ = apply(&classic, .startVoice(preferRealtime: false))
    _ = apply(&classic, .classicListenArmed)
    expectEq(apply(&classic, .toggleMute(hasPendingAudio: true)), [],
             "mute: classic no mutea")
    expect(!classic.snapshot.muted, "mute: classic ignora el gesto")

    armRealtime(&m)
    expectEq(m.snapshot.state, .listening, "mute: realtime listening")
    expect(!m.snapshot.speechOpen, "mute: sin habla abierta")

    let muteQuiet = apply(&m, .toggleMute(hasPendingAudio: false))
    expectEq(muteQuiet, [.setMicEnabled(false)],
             "mute: sin speechOpen solo apaga el mic")
    expect(m.snapshot.muted, "mute: muted ON")
    expectEq(m.snapshot.state, .listening, "mute: el estado no cambia")
    expect(!m.snapshot.speechOpen, "mute: speechOpen sigue cerrado")

    let unmuteListen = apply(&m, .toggleMute(hasPendingAudio: false))
    expectEq(unmuteListen, [.setMicEnabled(true), .clearInputAudio],
             "mute: unmute reabre y limpia el buffer")
    expect(!m.snapshot.muted, "mute: muted OFF")
    expectEq(m.snapshot.state, .listening, "mute: ya listening se queda")

    _ = apply(&m, .serverSpeechStarted)
    expect(m.snapshot.speechOpen, "mute: speechOpen al hablar")
    let muteTalk = apply(&m, .toggleMute(hasPendingAudio: false))
    expectEq(muteTalk, [.setMicEnabled(false), .commitAndRespond],
             "mute: con speechOpen cierra el turno a mano")
    expect(m.snapshot.muted, "mute: muted ON a media frase")
    expect(!m.snapshot.speechOpen, "mute: commit cierra speechOpen")
    expectEq(m.snapshot.state, .listening, "mute: ON no cambia de fase")

    _ = apply(&m, .toggleMute(hasPendingAudio: false))
    expect(!m.snapshot.muted, "mute: OFF de nuevo")

    _ = apply(&m, .agentAudioStarted)
    expectEq(m.snapshot.state, .speaking, "mute: speaking para el unmute")
    _ = apply(&m, .toggleMute(hasPendingAudio: true))
    expect(m.snapshot.muted, "mute: ON en speaking")
    let unmutePending = apply(&m, .toggleMute(hasPendingAudio: true))
    expectEq(unmutePending, [.setMicEnabled(true), .clearInputAudio],
             "mute: unmute con audio pendiente no empuja listening")
    expectEq(m.snapshot.state, .speaking,
             "mute: hasPendingAudio deja speaking")
    expect(!m.snapshot.muted, "mute: OFF")

    _ = apply(&m, .toggleMute(hasPendingAudio: false))
    expect(m.snapshot.muted, "mute: ON otra vez")
    let unmuteJump = apply(&m, .toggleMute(hasPendingAudio: false))
    expectEq(unmuteJump, [.setMicEnabled(true), .clearInputAudio],
             "mute: unmute sin cola endereza a listening")
    expectEq(m.snapshot.state, .listening,
             "mute: !listening y !pending → listening")
    expect(!m.snapshot.speechOpen, "mute: unmute cierra speechOpen")

    var connecting = TurnMachine()
    _ = apply(&connecting, .startVoice(preferRealtime: true))
    expectEq(apply(&connecting, .toggleMute(hasPendingAudio: false)), [],
             "mute: connecting no mutea")
}

@MainActor func testTurnMachineHangUpAndError() {
    var m = TurnMachine()
    armRealtime(&m)
    _ = apply(&m, .replyCompleted)
    expect(m.snapshot.inConversation
           || m.snapshot.state == .listening
           || m.snapshot.state == .speaking,
           "hangup: sesión viva antes de colgar")

    var live = TurnMachine()
    _ = apply(&live, .typedSubmit)
    _ = apply(&live, .replyCompleted)
    expect(live.snapshot.inConversation,
           "hangup: una respuesta marca inConversation")
    expectEq(live.snapshot.state, .speaking, "hangup: reply sin stream → speaking")
    let hung = apply(&live, .hangUp)
    expectEq(live.snapshot.state, .idle, "hangup: → idle")
    expect(!live.snapshot.inConversation, "hangup: inConversation false")
    expect(live.snapshot.pipeline == nil, "hangup: pipeline nil")
    expect(!live.snapshot.muted, "hangup: muted false")
    expect(!live.snapshot.speechOpen, "hangup: speechOpen false")
    expectEq(live.snapshot.echoGuardUntil, 0, "hangup: eco-guard unset")
    expect(!live.snapshot.typedTurn, "hangup: typedTurn limpio")
    expectEq(hung, [], "hangup: typed sin pipeline no cierra I/O")

    let hangRealtime = apply(&m, .hangUp)
    expectEq(hangRealtime, [.closeRealtime],
             "hangup: realtime cierra la sesión")
    expectEq(m.snapshot.state, .idle, "hangup: realtime → idle")
    expect(!m.snapshot.inConversation, "hangup: realtime limpia conversación")
    expect(m.snapshot.pipeline == nil, "hangup: realtime deja pipeline nil")
    expectEq(apply(&m, .hangUp), [], "hangup: idle es idempotente")

    var classic = TurnMachine()
    _ = apply(&classic, .startVoice(preferRealtime: false))
    _ = apply(&classic, .classicListenArmed)
    let hangClassic = apply(&classic, .hangUp)
    expectEq(hangClassic, [.stopClassicIO], "hangup: classic suelta mic/TTS")
    expectEq(classic.snapshot.state, .idle, "hangup: classic → idle")

    var stale = TurnMachine()
    _ = apply(&stale, .startVoice(preferRealtime: false))
    _ = apply(&stale, .hangUp)
    expectEq(apply(&stale, .classicListenArmed), [],
             "hangup: arm tardío tras colgar no reabre listen")
    expectEq(stale.snapshot.state, .idle, "hangup: sigue idle")
    expect(stale.snapshot.pipeline == nil, "hangup: arm tardío no inventa pipeline")

    var typedArm = TurnMachine()
    _ = apply(&typedArm, .typedSubmit)
    expectEq(apply(&typedArm, .classicListenArmed), [],
             "hangup: arm classic no pisa un typed thinking")
    expectEq(typedArm.snapshot.state, .thinking, "hangup: typed sigue thinking")

    var connecting = TurnMachine()
    _ = apply(&connecting, .startVoice(preferRealtime: true))
    let failed = apply(&connecting, .voiceStartFailed(.micDenied))
    expectEq(failed, [.noteFailure(.micDenied), .closeRealtime],
             "error: voiceStartFailed sin conversación → error + close")
    expectEq(connecting.snapshot.state, .error, "error: → error")
    expect(connecting.snapshot.pipeline == nil, "error: pipeline nil")
    expect(!connecting.snapshot.inConversation, "error: sin conversación")

    var dropped = TurnMachine()
    armRealtime(&dropped)
    expect(!dropped.snapshot.inConversation,
           "error: realtime listo aún no es conversación")
    let session = apply(&dropped, .turnFailed(.sessionDropped))
    expectEq(session, [.noteFailure(.sessionDropped), .closeRealtime],
             "error: sessionDropped sin conversación → error + close")
    expectEq(dropped.snapshot.state, .error, "error: sessionDropped → error")
    expect(dropped.snapshot.pipeline == nil, "error: drop deja pipeline nil")

    var recover = TurnMachine()
    _ = apply(&recover, .typedSubmit)
    _ = apply(&recover, .replyCompleted)
    expect(recover.snapshot.inConversation, "error: hay conversación")
    _ = apply(&recover, .hangUp)
    expect(!recover.snapshot.inConversation, "error: hangup la borra")
    _ = apply(&recover, .typedSubmit)
    _ = apply(&recover, .replyCompleted)
    let miss = apply(&recover, .voiceStartFailed(.micUnavailable))
    expect(miss.contains(.noteFailure(.micUnavailable)),
           "error: con conversación anota el fallo")
    expect(miss.contains(.requestClassicListen),
           "error: con conversación rearma classic")
    expectEq(recover.snapshot.state, .listening,
             "error: recover → listening")
    expectEq(recover.snapshot.pipeline, .classic,
             "error: recover cae a classic")

    var speech = TurnMachine()
    armClassicSpeaking(&speech)
    let tts = apply(&speech, .speechFailed)
    expect(tts.contains(.noteFailure(.speechEngine)),
           "error: TTS caído se anota")
    expectEq(speech.snapshot.state, .error, "error: speechFailed → error")

    var empty = TurnMachine()
    _ = apply(&empty, .startVoice(preferRealtime: false))
    _ = apply(&empty, .classicListenArmed)
    let heard = apply(&empty, .utteranceEmpty)
    expect(heard.contains(.noteFailure(.notHeard)),
           "error: primer turno vacío falla")
    expectEq(empty.snapshot.state, .error, "error: notHeard → error")

    var timeout = TurnMachine()
    _ = apply(&timeout, .startVoice(preferRealtime: false))
    _ = apply(&timeout, .classicListenArmed)
    let quiet = apply(&timeout, .endpointTimedOut(hasSpeech: false))
    expectEq(quiet, [.stopClassicIO], "error: timeout sin habla cuelga")
    expectEq(timeout.snapshot.state, .idle, "error: timeout quieto → idle")

    var thinkingTap = TurnMachine()
    armRealtime(&thinkingTap)
    _ = apply(&thinkingTap, .serverSpeechStopped)
    let tapThink = apply(&thinkingTap, .advance(hasSpeech: false))
    expectEq(tapThink, [.closeRealtime],
             "hangup: tap en thinking realtime cuelga")
    expectEq(thinkingTap.snapshot.state, .idle, "hangup: thinking tap → idle")
}
