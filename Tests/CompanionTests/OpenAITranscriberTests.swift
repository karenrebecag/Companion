import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// El oído realtime: gpt-live-transcribe por websocket. El wire es puro y se
// prueba sin red; el protocolo se validó contra la API real (probe 2026-08-25).

@Test func openAITranscriberWireTests() {
    testLanguageHint()
    testSessionUpdateShape()
    testAppendShape()
    testDeltaParsing()
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
    let json = parse(OpenAITranscriber.sessionUpdateJSON(language: "es"))
    expectEq(json["type"] as? String, "session.update", "update: tipo")
    let session = json["session"] as? [String: Any] ?? [:]
    expectEq(session["type"] as? String, "transcription",
             "update: sesión de SOLO transcripción")
    let input = ((session["audio"] as? [String: Any])?["input"]
        as? [String: Any]) ?? [:]
    let tx = input["transcription"] as? [String: Any] ?? [:]
    expectEq(tx["model"] as? String, "gpt-live-transcribe",
             "update: el modelo vigente, no la generación 4o retirada")
    expectEq(tx["languages"] as? [String], ["es"], "update: idioma esperado")
    expect(input["turn_detection"] is NSNull,
           "update: el turno lo decide el cliente, no el servidor")
    let format = input["format"] as? [String: Any] ?? [:]
    expectEq(format["rate"] as? Int, 24000, "update: 24 kHz como el mic")
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
