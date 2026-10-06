import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// El oído realtime: gpt-live-transcribe por websocket. El wire es puro y se
// prueba sin red; el protocolo se validó contra la API real (probe 2026-08-25).

@Test func openAITranscriberWireTests() {
    testSessionUpdateShape()
    testTurnDetectionMapping()
    testAppendShape()
    testDeltaParsing()
    testSegmentParsing()
    testErrorParsing()
    testTheEarLogsCountsNotWords()
}

func testSessionUpdateShape() {
    let json = parse(OpenAITranscriber.sessionUpdateJSON(
        languages: ["es"], turnDetection: .serverVAD(silenceMs: 700)))
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
        languages: ["es"], turnDetection: nil))
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

/// 12e. Lo que el oído oye es del usuario: el log cuenta caracteres y
/// nunca palabras (deuda de la revisión de 12b, vista en vivo 2026-09-06
/// con «ear: segment «Hola, ¿estás ahí?»» en el log).
func testTheEarLogsCountsNotWords() {
    let hearing = OpenAITranscriber.earLine(hearing: "Hola, ¿estás ahí?")
    let segment = OpenAITranscriber.earLine(segment: "Hola. Hola, hola.")
    expect(hearing.hasPrefix("ear: hearing"), "oído: la línea sigue diciendo que oye")
    expect(segment.hasPrefix("ear: segment"), "oído: y que cerró un segmento")
    expect(hearing.contains("17 chars"), "oído: cuenta")
    expect(segment.contains("17 chars"), "oído: cuenta el segmento")
    expect(!hearing.contains("Hola"), "oído: nunca las palabras")
    expect(!segment.contains("Hola"), "oído: nunca el segmento")
}

// MARK: - start() on a scripted socket

/// A server the test plays: it records what the ear sends and delivers
/// events on demand, so the language list can be checked on the wire.
final class ScriptedEarSocket: EarSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var _sent: [String] = []
    private var handler: (@Sendable (Result<String?, Error>) -> Void)?

    var sent: [String] { lock.withLock { _sent } }

    func resume() {}
    func cancel() {}
    func send(_ text: String) async throws { lock.withLock { _sent.append(text) } }
    func sendDetached(_ text: String) { lock.withLock { _sent.append(text) } }
    func receive(_ handler: @escaping @Sendable (Result<String?, Error>) -> Void) {
        lock.withLock { self.handler = handler }
    }

    func deliver(_ json: String) {
        let next = lock.withLock { () -> (@Sendable (Result<String?, Error>) -> Void)? in
            defer { handler = nil }
            return handler
        }
        next?(.success(json))
    }
}

private final class EarSockets: @unchecked Sendable {
    private let lock = NSLock()
    private var made: [ScriptedEarSocket] = []
    var all: [ScriptedEarSocket] { lock.withLock { made } }

    func make() -> ScriptedEarSocket {
        let socket = ScriptedEarSocket()
        lock.withLock { made.append(socket) }
        return socket
    }
}

private final class ChosenLanguages: @unchecked Sendable {
    private let lock = NSLock()
    private var codes: [String]
    init(_ codes: [String]) { self.codes = codes }
    var value: [String] {
        get { lock.withLock { codes } }
        set { lock.withLock { codes = newValue } }
    }
}

private func ear(
    _ chosen: ChosenLanguages, _ sockets: EarSockets
) -> OpenAITranscriber {
    OpenAITranscriber(
        keyProvider: { "sk-test" }, languages: { chosen.value },
        connect: { _ in sockets.make() })
}

private func transcription(of update: String) -> [String: Any] {
    let session = parse(update)["session"] as? [String: Any] ?? [:]
    let input = ((session["audio"] as? [String: Any])?["input"] as? [String: Any]) ?? [:]
    return input["transcription"] as? [String: Any] ?? [:]
}

private func turnDetection(of update: String) -> Any? {
    let session = parse(update)["session"] as? [String: Any] ?? [:]
    let input = ((session["audio"] as? [String: Any])?["input"] as? [String: Any]) ?? [:]
    return input["turn_detection"]
}

@Test func openAITranscriberStartSendsTheChosenLanguages() async {
    let sockets = EarSockets()
    let transcriber = ear(ChosenLanguages(["es", "fr"]), sockets)
    try? await transcriber.start(localeIdentifier: "en-US")
    let update = sockets.all.first?.sent.first ?? ""
    expectEq(transcription(of: update)["languages"] as? [String], ["es", "fr"],
             "oído: start manda la lista elegida, no el idioma de la interfaz")
    expectEq(parse(update)["type"] as? String, "session.update", "oído: lo primero es la config")

    let none = EarSockets()
    let automatic = ear(ChosenLanguages([]), none)
    try? await automatic.start(localeIdentifier: "es-MX")
    let open = transcription(of: none.all.first?.sent.first ?? "")
    expect(open["languages"] == nil, "oído: sin elección, start no manda idiomas")
    expectEq(open["model"] as? String, "gpt-transcribe", "oído: el modelo sigue")
}

@Test func openAITranscriberRetryResendsTheSameListWithoutVAD() async {
    let sockets = EarSockets()
    let chosen = ChosenLanguages(["es", "fr"])
    let transcriber = ear(chosen, sockets)
    try? await transcriber.start(localeIdentifier: "en-US")
    // A change after start must not leak into the retry of this session.
    chosen.value = ["de"]
    sockets.all.first?.deliver(#"{"type":"error","error":{"message":"turn detection"}}"#)
    let sent = sockets.all.first?.sent ?? []
    expectEq(sent.count, 2, "oído: config rechazada, un reintento")
    let retry = sent.last ?? ""
    expectEq(transcription(of: retry)["languages"] as? [String], ["es", "fr"],
             "oído: el reintento reenvía la misma lista de la sesión")
    expect(turnDetection(of: retry) is NSNull, "oído: el reintento apaga el VAD")

    let none = EarSockets()
    let automatic = ear(ChosenLanguages([]), none)
    try? await automatic.start(localeIdentifier: "en-US")
    none.all.first?.deliver(#"{"type":"error","error":{"message":"turn detection"}}"#)
    let emptyRetry = none.all.first?.sent.last ?? ""
    expect(transcription(of: emptyRetry)["languages"] == nil,
           "oído: el reintento de un oído automático tampoco inventa idiomas")
    expect(turnDetection(of: emptyRetry) is NSNull, "oído: y también sin VAD")
}

@Test func openAITranscriberReadsTheListAtEveryStart() async {
    let sockets = EarSockets()
    let chosen = ChosenLanguages(["es"])
    let transcriber = ear(chosen, sockets)
    try? await transcriber.start(localeIdentifier: "en-US")
    chosen.value = ["it", "pt"]
    try? await transcriber.start(localeIdentifier: "en-US")
    expectEq(sockets.all.count, 2, "oído: cada start abre su socket")
    expectEq(transcription(of: sockets.all[0].sent.first ?? "")["languages"] as? [String],
             ["es"], "oído: la primera sesión llevó la lista de entonces")
    expectEq(transcription(of: sockets.all[1].sent.first ?? "")["languages"] as? [String],
             ["it", "pt"], "oído: el cambio llegó a la segunda sesión")
}
