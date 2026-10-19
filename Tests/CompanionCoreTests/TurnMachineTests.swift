import CompanionCore
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func turnMachineTests() {
    testTurnMachineStartClassic()
    testTurnMachineSpeechCycleClassic()
    testTurnMachineBargeInClassic()
    testTurnMachineHoldClassic()
    testTurnMachineInterrupt()
    testTurnMachineHoldClassicEndsIdleAfterReply()
    testTurnMachineHandsFreeClassicRelistensAfterReply()
    testTurnMachineHangUpAndErrorClassic()
}

@MainActor func testTurnMachineStartClassic() {
    var m = TurnMachine()
    expectEq(m.snapshot, .idle, "start: snapshot idle de fábrica")
    expect(!m.isEchoGuarded(at: 0), "start: sin eco-guard en idle")

    expectEq(apply(&m, .startVoice), [.requestClassicListen],
             "start: classic pide el mic y espera")
    expectEq(m.snapshot.state, .idle, "start: classic se queda idle")
    expect(m.snapshot.pipeline == nil, "start: idle no lleva pipeline")
    _ = apply(&m, .classicListenArmed)
    expectEq(m.snapshot.state, .listening, "start: armed → listening")
    expectEq(m.snapshot.pipeline, .classic, "start: pipeline classic")
    expectEq(apply(&m, .startVoice), [], "start: listening ignora startVoice")

    var fromError = TurnMachine(snapshot: TurnSnapshot(state: .error))
    expectEq(apply(&fromError, .startVoice), [.requestClassicListen],
             "start: error reintenta el mic")

    var typed = TurnMachine()
    let submit = apply(&typed, .typedSubmit)
    expectEq(submit, [.submitUtterance], "start: typedSubmit manda el turno")
    expectEq(typed.snapshot.state, .thinking, "start: typed → thinking")
    expect(typed.snapshot.typedTurn, "start: typedTurn queda marcado")
    expect(typed.snapshot.pipeline == nil, "start: typed no abre pipeline")
}

@MainActor func testTurnMachineSpeechCycleClassic() {
    var classic = TurnMachine()
    _ = apply(&classic, .startVoice)
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

@MainActor func testTurnMachineBargeInClassic() {
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
    expectEq(real, [.cancelAgentOutput(steer: true)],
             "barge-in: interrupción real cancela al agente")
    expectEq(m.snapshot.state, .listening, "barge-in: real → listening")
    expect(m.snapshot.interruptionPending, "barge-in: real marca pending")

    var unicode = TurnMachine()
    armClassicSpeaking(&unicode)
    let accented = apply(&unicode, .heardWhileSpeaking(
        heard: "oye espera ya entendí", agentSaying: saying))
    expectEq(accented, [.cancelAgentOutput(steer: true)],
             "barge-in: unicode propio sí interrumpe")

    var idle = TurnMachine()
    expectEq(apply(&idle, .heardWhileSpeaking(heard: "oye espera",
                                              agentSaying: saying)),
             [], "barge-in: idle ignora heardWhileSpeaking")
}

@MainActor func testTurnMachineHoldClassic() {
    var m = TurnMachine()
    expectEq(apply(&m, .holdPressed), [.requestClassicListen], "clásico: pide escuchar")
    _ = apply(&m, .classicListenArmed)
    expectEq(apply(&m, .holdReleased(hasSpeech: true)), [.submitUtterance], "clásico: soltar con voz envía")
    expectEq(m.snapshot.state, .thinking, "clásico: thinking")

    var quiet = TurnMachine()
    _ = apply(&quiet, .holdPressed)
    _ = apply(&quiet, .classicListenArmed)
    expectEq(apply(&quiet, .holdReleased(hasSpeech: false)), [.stopClassicIO], "clásico: sin voz cuelga")
    expectEq(quiet.snapshot.state, .idle, "clásico: idle")
}

/// 20. Interrumpir corta lo que la voz piensa o dice y deja el micro como
/// estaba; en reposo no hace nada.
@MainActor func testTurnMachineInterrupt() {
    var m = TurnMachine()
    expectEq(apply(&m, .interrupt), [], "interrupt: idle nada")

    // Code review 2026-09-23 (alto): classic has no endpointer, so
    // `.requestClassicListen` (`cutClassicTurn`'s reopen for a fresh press)
    // left a hot, unowned mic listening with no key down to ever close it.
    // Interrupt is not a press — it ends idle with the mic torn down.
    var classic = TurnMachine()
    _ = apply(&classic, .holdPressed)
    _ = apply(&classic, .classicListenArmed)
    _ = apply(&classic, .holdReleased(hasSpeech: true))
    expectEq(classic.snapshot.state, .thinking, "interrupt clásico: thinking")
    expectEq(apply(&classic, .interrupt), [.cancelAgentOutput(steer: false), .stopClassicIO],
             "interrupt clásico: corta el turno y apaga el micro, no lo reabre")
    expectEq(classic.snapshot.state, .idle, "interrupt clásico: idle, no listening")
    expect(classic.snapshot.pipeline == nil, "interrupt clásico: sin pipeline armado")
    expect(!classic.snapshot.muted, "interrupt clásico: hangUp deja muted en false")
}

/// Live crash 2026-09-23: a HOLD classic turn (FN press → release → reply
/// spoken) went back to `.listening` and issued `.requestClassicListen`,
/// re-opening a mic that was never stopped — MicCapture.startOnce() then
/// installed a second tap on the still-running engine and crashed. A hold
/// must end in idle with the mic off; the user presses again for the next
/// turn, unlike hands-free listening.
@MainActor func testTurnMachineHoldClassicEndsIdleAfterReply() {
    var m = TurnMachine()
    _ = apply(&m, .holdPressed)
    _ = apply(&m, .classicListenArmed)
    _ = apply(&m, .holdReleased(hasSpeech: true))
    expectEq(m.snapshot.state, .thinking, "hold classic: thinking")
    _ = apply(&m, .firstSentence)
    expectEq(m.snapshot.state, .speaking, "hold classic: speaking")
    expectEq(apply(&m, .speechFinished), [.stopClassicIO],
              "hold classic: the reply's end closes the mic instead of relistening")
    expectEq(m.snapshot.state, .idle, "hold classic: idle, waiting for the next press")
    expect(m.snapshot.pipeline == nil, "hold classic: no pipeline left armed")
    expect(!m.snapshot.holdArmed, "hold classic: disarmed")
}

/// Hands-free classic (no hold, `start()`) is unaffected: nobody has to
/// press again, so it keeps relistening after a reply — today's behavior.
@MainActor func testTurnMachineHandsFreeClassicRelistensAfterReply() {
    var m = TurnMachine()
    _ = apply(&m, .startVoice)
    _ = apply(&m, .classicListenArmed)
    _ = apply(&m, .advance(hasSpeech: true))
    expectEq(m.snapshot.state, .thinking, "hands-free: thinking")
    _ = apply(&m, .firstSentence)
    expectEq(apply(&m, .speechFinished), [.requestClassicListen],
              "hands-free: still relistens after the reply")
    expectEq(m.snapshot.state, .listening, "hands-free: listening again")
}

@MainActor func testTurnMachineHangUpAndErrorClassic() {
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

    var classic = TurnMachine()
    _ = apply(&classic, .startVoice)
    _ = apply(&classic, .classicListenArmed)
    let hangClassic = apply(&classic, .hangUp)
    expectEq(hangClassic, [.stopClassicIO], "hangup: classic suelta mic/TTS")
    expectEq(classic.snapshot.state, .idle, "hangup: classic → idle")

    var stale = TurnMachine()
    _ = apply(&stale, .startVoice)
    _ = apply(&stale, .hangUp)
    // 15d-1: the runtime did start the mic for that arm; `[]` left it on
    // with nobody listening. It is torn down, never reopened.
    expectEq(apply(&stale, .classicListenArmed), [.stopClassicIO],
             "hangup: arm tardío tras colgar no reabre listen y apaga el micro")
    expectEq(stale.snapshot.state, .idle, "hangup: sigue idle")
    expect(stale.snapshot.pipeline == nil, "hangup: arm tardío no inventa pipeline")

    var typedArm = TurnMachine()
    _ = apply(&typedArm, .typedSubmit)
    expectEq(apply(&typedArm, .classicListenArmed), [],
             "hangup: arm classic no pisa un typed thinking")
    expectEq(typedArm.snapshot.state, .thinking, "hangup: typed sigue thinking")

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
    _ = apply(&empty, .startVoice)
    _ = apply(&empty, .classicListenArmed)
    let heard = apply(&empty, .utteranceEmpty)
    expect(heard.contains(.noteFailure(.notHeard)),
           "error: primer turno vacío falla")
    expectEq(empty.snapshot.state, .error, "error: notHeard → error")

    var timeout = TurnMachine()
    _ = apply(&timeout, .startVoice)
    _ = apply(&timeout, .classicListenArmed)
    let quiet = apply(&timeout, .endpointTimedOut(hasSpeech: false))
    expectEq(quiet, [.stopClassicIO], "error: timeout sin habla cuelga")
    expectEq(timeout.snapshot.state, .idle, "error: timeout quieto → idle")
}

@discardableResult
private func apply(
    _ machine: inout TurnMachine, _ event: TurnEvent, at now: TimeInterval = 0
) -> [TurnEffect] {
    machine.handle(event, at: now)
}

private func armClassicSpeaking(_ machine: inout TurnMachine) {
    _ = apply(&machine, .startVoice)
    _ = apply(&machine, .classicListenArmed)
    _ = apply(&machine, .endpointFinished)
    _ = apply(&machine, .firstSentence)
}
