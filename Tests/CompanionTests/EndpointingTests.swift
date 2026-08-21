import Foundation
import CompanionCore
import Testing

private func drive(_ ep: inout Endpointer, rms: Double,
                   from t0: TimeInterval, to t1: TimeInterval,
                   step: TimeInterval = 0.05) -> Endpointer.Verdict {
    var last = Endpointer.Verdict.listening
    var t = t0
    while t <= t1 {
        last = ep.feed(rms: rms, at: t)
        if last == .finished || last == .timedOut { return last }
        t += step
    }
    return last
}

@Test @MainActor func endpointingTests() {
    testEndpointerHablaYSilencioCierra()
    testEndpointerBlipNoCierra()
    testEndpointerRuidoAmbienteCalibra()
    testEndpointerSpeechStartedUnaVez()
    testEndpointerTimeout()
    testEndpointerQuietClose()
    testSpeechCues()
    testTranscriptEndpointerVentana()
    testTranscriptEndpointerHibrido()
    testTranscriptEndpointerRevisionNoEsCrecimiento()
    testTranscriptEndpointerQuietClose()
    testTranscriptEndpointerTimeout()
    testEchoGuard()
    testEchoGuardWords()
}

@MainActor func testEndpointerHablaYSilencioCierra() {
    var ep = Endpointer(start: 0)
    _ = drive(&ep, rms: 0.02, from: 0, to: 0.4)
    let started = drive(&ep, rms: 0.5, from: 0.45, to: 1.2)
    expect(started == .speechStarted || started == .listening,
           "endpointer: la habla no cierra el turno por sí sola")
    let v = drive(&ep, rms: 0.02, from: 1.25, to: 2.6)
    expect(v == .finished, "endpointer: habla + silencio sostenido termina el turno")
}

@MainActor func testEndpointerBlipNoCierra() {
    var ep = Endpointer(start: 0)
    _ = drive(&ep, rms: 0.02, from: 0, to: 0.4)
    _ = drive(&ep, rms: 0.6, from: 0.5, to: 0.6)
    let v = drive(&ep, rms: 0.02, from: 0.65, to: 2.5)
    expect(v == .listening, "endpointer: un blip corto no dispara el cierre")
}

@MainActor func testEndpointerRuidoAmbienteCalibra() {
    var ep = Endpointer(start: 0)
    _ = drive(&ep, rms: 0.2, from: 0, to: 0.4)
    _ = drive(&ep, rms: 0.21, from: 0.45, to: 1.5)
    let quiet = drive(&ep, rms: 0.2, from: 1.55, to: 3.0)
    expect(quiet == .listening,
           "endpointer: el ruido ambiente no se confunde con habla")
    var sawStart = false
    var t = 3.05
    while t <= 3.6 {
        if ep.feed(rms: 0.4, at: t) == .speechStarted { sawStart = true }
        t += 0.05
    }
    expect(sawStart, "endpointer: habla clara sobre ambiente ruidoso")
}

@MainActor func testEndpointerSpeechStartedUnaVez() {
    var ep = Endpointer(start: 0)
    _ = drive(&ep, rms: 0.02, from: 0, to: 0.4)
    var starts = 0
    var t = 0.45
    while t <= 2.0 {
        if ep.feed(rms: 0.5, at: t) == .speechStarted { starts += 1 }
        t += 0.05
    }
    expectEq(starts, 1, "endpointer: speechStarted se emite una sola vez")
}

@MainActor func testEndpointerTimeout() {
    var cfg = Endpointer.Config()
    cfg.maxUtterance = 3
    var ep = Endpointer(config: cfg, start: 0)
    _ = drive(&ep, rms: 0.02, from: 0, to: 0.4)
    let v = drive(&ep, rms: 0.5, from: 0.45, to: 4.0)
    expect(v == .timedOut, "endpointer: maxUtterance corta un monólogo infinito")
}

@MainActor func testEndpointerQuietClose() {
    var cfg = Endpointer.Config()
    cfg.quietClose = 2
    var ep = Endpointer(config: cfg, start: 0)
    _ = drive(&ep, rms: 0.02, from: 0, to: 0.4)
    let v = drive(&ep, rms: 0.02, from: 0.45, to: 2.5)
    expect(v == .timedOut, "endpointer: mic abierto sin habla se cierra solo")
    expect(!ep.hasSpeech, "endpointer: cerrar sin habla no inventa habla")
}

@MainActor func testSpeechCues() {
    expect(SpeechCues.isIncomplete("quiero que me ayudes con el"),
           "cues: determinante final = frase colgando")
    expect(SpeechCues.isIncomplete("hazlo porque"),
           "cues: conjunción final = frase colgando")
    expect(SpeechCues.isIncomplete("necesito, "),
           "cues: coma final = frase colgando")
    expect(SpeechCues.isIncomplete(""),
           "cues: sin texto todavía no hay frase")
    expect(!SpeechCues.isIncomplete("hola cómo estás"),
           "cues: frase normal sin puntuación se considera terminada")
    expect(!SpeechCues.isIncomplete("dime la hora."),
           "cues: punto final cierra")
    expect(!SpeechCues.isIncomplete("¿qué hora es?"),
           "cues: pregunta cierra")
    expect(SpeechCues.isIncomplete("   "),
           "cues: solo espacios sigue colgando")
    expect(SpeechCues.isIncomplete("sigue —"),
           "cues: raya final = frase colgando")
    expect(!SpeechCues.isIncomplete("listo…"),
           "cues: puntos suspensivos cierran")
    expect(SpeechCues.continuations.contains("porque"),
           "cues: el set español incluye conjunciones")
    expect(SpeechCues.continuations.contains("este…"),
           "cues: el set incluye muletilla con elipsis")
    expect(SpeechCues.continuations.contains("sí"),
           "cues: el set conserva acentos")
    expectEq(SpeechCues.continuations.count, 64,
             "cues: el set español no se recorta ni se infla")
}

@MainActor func testTranscriptEndpointerVentana() {
    var quick = TranscriptEndpointer(start: 0)
    _ = quick.feed(text: "dime la hora", level: 0, at: 1.0)
    expect(quick.feed(text: "dime la hora", level: 0, at: 1.4) == .listening,
           "ventana: antes del mínimo sigue escuchando")
    expect(quick.feed(text: "dime la hora", level: 0, at: 1.7) == .finished,
           "ventana: frase terminada cierra en el umbral corto")

    var slow = TranscriptEndpointer(start: 0)
    _ = slow.feed(text: "quiero que me ayudes con el", level: 0, at: 1.0)
    expect(slow.feed(text: "quiero que me ayudes con el", level: 0, at: 2.0) == .listening,
           "ventana: frase colgando no cierra en el umbral corto")
    expect(slow.feed(text: "quiero que me ayudes con el", level: 0, at: 3.7) == .finished,
           "ventana: frase colgando cierra al agotar el umbral largo")
}

@MainActor func testTranscriptEndpointerHibrido() {
    var ep = TranscriptEndpointer(start: 0)
    _ = ep.feed(text: "dime la hora", level: 0.5, at: 1.0)
    expect(ep.feed(text: "dime la hora", level: 0.5, at: 1.8) == .listening,
           "híbrido: con voz activa no cierra pese al texto estable")
    expect(ep.feed(text: "dime la hora", level: 0.5, at: 3.8) == .finished,
           "híbrido: el audio nunca alarga más allá de la ventana")
}

@MainActor func testTranscriptEndpointerRevisionNoEsCrecimiento() {
    var ep = TranscriptEndpointer(start: 0)
    _ = ep.feed(text: "veinte caracteres ok", level: 0, at: 1.0)
    _ = ep.feed(text: "quince letras", level: 0, at: 1.5)
    expect(ep.feed(text: "quince letras", level: 0, at: 2.3) == .finished,
           "transcript-ep: una revisión a la baja no cuenta como habla nueva")
}

@MainActor func testTranscriptEndpointerQuietClose() {
    var cfg = TranscriptEndpointer.Config()
    cfg.quietClose = 2
    var ep = TranscriptEndpointer(config: cfg, start: 0)
    _ = ep.feed(text: "", level: 0, at: 1.0)
    expect(ep.feed(text: "", level: 0, at: 2.5) == .timedOut,
           "transcript-ep: mic abierto sin habla se cierra solo")
    expect(!ep.hasSpeech, "transcript-ep: cerrar sin habla no inventa habla")
}

@MainActor func testTranscriptEndpointerTimeout() {
    var cfg = TranscriptEndpointer.Config()
    cfg.maxUtterance = 3
    var ep = TranscriptEndpointer(config: cfg, start: 0)
    _ = ep.feed(text: "dime la hora", level: 0, at: 1.0)
    expect(ep.feed(text: "dime la hora", level: 0, at: 3.1) == .timedOut,
           "transcript-ep: maxUtterance corta un monólogo infinito")
    expect(ep.feed(text: "dime la hora", level: 0, at: 4.0) == .timedOut,
           "transcript-ep: el veredicto terminal se conserva")
}

@MainActor func testEchoGuard() {
    let saying = "Claro, te cuento la historia de un viaje muy largo"
    expect(EchoGuard.isEcho(heard: "te cuento la historia", agentSaying: saying),
           "eco: repetir lo que el widget dice es eco, no interrupción")
    expect(!EchoGuard.isEcho(heard: "espera para ya entendí", agentSaying: saying),
           "eco: palabras propias no son eco")
    expect(EchoGuard.isEcho(heard: "", agentSaying: saying),
           "eco: sin palabras no hay interrupción")

    expect(EchoGuard.isRealInterruption(heard: "oye espera", agentSaying: saying),
           "barge-in: dos palabras propias interrumpen")
    expect(!EchoGuard.isRealInterruption(heard: "mmm", agentSaying: saying),
           "barge-in: una muletilla no interrumpe")
    expect(!EchoGuard.isRealInterruption(heard: "la historia", agentSaying: saying),
           "barge-in: el eco no interrumpe aunque traiga dos palabras")
}

@MainActor func testEchoGuardWords() {
    expectEq(EchoGuard.words(""), [], "words: vacío no produce tokens")
    expectEq(EchoGuard.words("a b c"), [], "words: una letra no cuenta")
    expectEq(EchoGuard.words("hola, mundo!"), ["hola", "mundo"],
             "words: puntuación no es palabra")
    expectEq(EchoGuard.words("TE Cuento"), ["te", "cuento"],
             "words: minúsculas y tokens de 2+")
    expect(!EchoGuard.isEcho(heard: "oye espera", agentSaying: ""),
           "eco: si el agente no dice nada, lo oído no es eco")
    expect(!EchoGuard.isRealInterruption(heard: "", agentSaying: "hola mundo"),
           "barge-in: silencio no interrumpe")
    expect(!EchoGuard.isRealInterruption(heard: "sí", agentSaying: "otra cosa"),
           "barge-in: una sola palabra no alcanza")
}
