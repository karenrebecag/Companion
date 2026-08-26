import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// El oído realtime: gpt-live-transcribe por websocket. El wire es puro y se
// prueba sin red; el protocolo se validó contra la API real (probe 2026-08-25).

@Test func openAITranscriberWireTests() {
    testLanguageHint()
    testSessionUpdateShape()
    testTurnDetectionMapping()
    testAppendShape()
    testDeltaParsing()
    testSegmentParsing()
    testErrorParsing()
}

func testLanguageHint() {
    expectEq(OpenAITranscriber.languageHint(from: "es-MX"), "es",
             "hint: es-MX pide español")
    expectEq(OpenAITranscriber.languageHint(from: "en-US"), "en",
             "hint: en-US pide inglés")
    expectEq(OpenAITranscriber.languageHint(from: ""), "en",
             "hint: vacío cae a inglés, no a cadena vacía")
}

func testSessionUpdateShape() {
    let json = parse(OpenAITranscriber.sessionUpdateJSON(
        language: "es", turnDetection: .serverVAD(silenceMs: 700)))
    expectEq(json["type"] as? String, "session.update", "update: tipo")
    let session = json["session"] as? [String: Any] ?? [:]
    expectEq(session["type"] as? String, "transcription",
             "update: sesión de SOLO transcripción")
    let input = ((session["audio"] as? [String: Any])?["input"]
        as? [String: Any]) ?? [:]
    let tx = input["transcription"] as? [String: Any] ?? [:]
    // gpt-transcribe: el único que acepta turn_detection (gpt-live-transcribe
    // lo rechaza y dejaba el oído sordo) y además el más preciso en el probe.
    expectEq(tx["model"] as? String, "gpt-transcribe",
             "update: el modelo de alta precisión que sí segmenta")
    expectEq(tx["languages"] as? [String], ["es"], "update: idioma esperado")
    // 9j-1: el VAD del server segmenta los turnos con la preferencia del
    // usuario — el cliente deja de adivinar cuándo terminó la idea.
    let vad = input["turn_detection"] as? [String: Any] ?? [:]
    expectEq(vad["type"] as? String, "server_vad",
             "update: el server segmenta los turnos")
    let format = input["format"] as? [String: Any] ?? [:]
    expectEq(format["rate"] as? Int, 24000, "update: 24 kHz como el mic")

    // El fallback de resiliencia: sin VAD, el campo viaja null — un oído
    // sordo por config rechazada es el peor modo de falla.
    let fallback = parse(OpenAITranscriber.sessionUpdateJSON(
        language: "es", turnDetection: nil))
    let fbInput = (((fallback["session"] as? [String: Any])?["audio"]
        as? [String: Any])?["input"] as? [String: Any]) ?? [:]
    expect(fbInput["turn_detection"] is NSNull,
           "update: el fallback apaga el VAD, no el oído")
}

func testTurnDetectionMapping() {
    let server = OpenAITranscriber.turnDetectionJSON(.serverVAD(silenceMs: 900))
    expectEq(server["type"] as? String, "server_vad", "vad: tipo server")
    expectEq(server["silence_duration_ms"] as? Int, 900,
             "vad: el silencio del usuario viaja")
    expect(server["create_response"] == nil && server["interrupt_response"] == nil,
           "vad: campos de speech-to-speech no viajan a transcripción")

    let semantic = OpenAITranscriber.turnDetectionJSON(
        .semanticVAD(eagerness: .high))
    expectEq(semantic["type"] as? String, "semantic_vad", "vad: tipo semántico")
    expectEq(semantic["eagerness"] as? String, "high", "vad: eagerness viaja")
}

func testAppendShape() {
    let pcm = Data([0x01, 0x02, 0x03])
    let json = parse(OpenAITranscriber.appendJSON(pcm))
    expectEq(json["type"] as? String, "input_audio_buffer.append", "append: tipo")
    expectEq(json["audio"] as? String, pcm.base64EncodedString(),
             "append: el PCM viaja en base64")
}

func testDeltaParsing() {
    let delta = OpenAITranscriber.delta(fromEvent:
        #"{"type":"conversation.item.input_audio_transcription.delta","delta":" prueba"}"#)
    expectEq(delta, " prueba", "delta: extrae el texto")
    expect(OpenAITranscriber.delta(fromEvent: #"{"type":"session.created"}"#) == nil,
           "delta: otros eventos no son texto")
    expect(OpenAITranscriber.delta(fromEvent: "basura") == nil,
           "delta: basura no truena")
}

func testSegmentParsing() {
    expectEq(OpenAITranscriber.completedTranscript(fromEvent:
        #"{"type":"conversation.item.input_audio_transcription.completed","transcript":"crea prueba dos"}"#),
        "crea prueba dos", "segmento: el completed trae el texto final")
    expect(OpenAITranscriber.completedTranscript(
        fromEvent: #"{"type":"session.created"}"#) == nil,
        "segmento: otros eventos no son segmentos")
    expect(OpenAITranscriber.isSpeechStarted(event:
        #"{"type":"input_audio_buffer.speech_started"}"#),
        "segmento: el server avisa que empezaste a hablar")
    expect(!OpenAITranscriber.isSpeechStarted(event:
        #"{"type":"input_audio_buffer.speech_stopped"}"#),
        "segmento: stopped no es started")
}

func testErrorParsing() {
    let msg = OpenAITranscriber.errorMessage(fromEvent:
        #"{"type":"error","error":{"message":"bad key"}}"#)
    expectEq(msg, "bad key", "error: trae el mensaje del servidor")
    expect(OpenAITranscriber.errorMessage(
        fromEvent: #"{"type":"session.created"}"#) == nil,
        "error: un evento normal no es error")
}

private func parse(_ s: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any] ?? [:]
}
