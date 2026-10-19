import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// Scribe v2 Realtime (ElevenLabs). Fixtures are written by hand from the
// documented message fields of /v1/speech-to-text/realtime (API reference,
// checked 2026-10-19). Everything here is pure: no socket, no clock.

private let sessionStartedFixture = """
{"message_type":"session_started","session_id":"sess_0001",\
"config":{"model_id":"scribe_v2_realtime","keepalive_interval_ms":1000}}
"""

private let partialFixture = """
{"message_type":"partial_transcript","text":"hola como"}
"""

private let committedFixture = """
{"message_type":"committed_transcript","text":"Hola, ¿cómo estás?"}
"""

private let emptyCommitFixture = """
{"message_type":"committed_transcript","text":""}
"""

private let authErrorFixture = """
{"message_type":"auth_error","error":"Invalid API key"}
"""

@Test func scribeParsesDocumentedServerEvents() {
    expectEq(ScribeTranscriber.event(fromJSON: sessionStartedFixture),
             .sessionStarted, "scribe: session_started abre el envío")
    expectEq(ScribeTranscriber.event(fromJSON: partialFixture),
             .partial("hola como"), "scribe: partial_transcript es hipótesis")
    expectEq(ScribeTranscriber.event(fromJSON: committedFixture),
             .committed("Hola, ¿cómo estás?"), "scribe: committed_transcript es final")
    expectEq(ScribeTranscriber.event(fromJSON: "{\"message_type\":\"warning\"}"),
             .ignored, "scribe: un tipo no mapeado se ignora")
}

// turn_prediction commits when the model predicts the speaker finished, so a
// committed transcript is the end-of-turn signal the session already consumes.
@Test func scribeTurnPredictionCommitIsEndOfTurn() {
    var transcript = ScribeTranscript()
    let turn = transcript.apply(ScribeTranscriber.event(fromJSON: committedFixture))
    expectEq(turn, .finished(text: "Hola, ¿cómo estás?"),
             "scribe: commit de turn_prediction = fin de turno con el texto del segmento")
    expectEq(transcript.currentText, "Hola, ¿cómo estás?",
             "scribe: el texto del turno sigue disponible tras el commit, como en OpenAI")
}

@Test func scribeAccumulatesCommittedSegmentsWithLivePartial() {
    var transcript = ScribeTranscript()
    _ = transcript.apply(.committed("hola"))
    _ = transcript.apply(.committed("como estas"))
    _ = transcript.apply(.partial("tengo"))
    expectEq(transcript.currentText, "hola como estas tengo",
             "scribe: el texto de la sesión une segmentos y la hipótesis viva")
}

@Test func scribeEmptyCommitIsNotATurn() {
    var transcript = ScribeTranscript()
    let turn = transcript.apply(ScribeTranscriber.event(fromJSON: emptyCommitFixture))
    expect(turn == nil, "scribe: un commit vacío no cierra turno (no hay habla)")
}

@Test func scribeErrorKindIsReportedNotRetriedAsTranscript() {
    expectEq(ScribeTranscriber.event(fromJSON: authErrorFixture),
             .failed(kind: "auth_error"), "scribe: error se reporta por tipo, sin texto")
}

@Test func scribeOversizedInboundFrameIsDropped() {
    let huge = String(repeating: "a", count: ScribeTranscriber.maxInboundBytes + 1)
    let json = "{\"message_type\":\"partial_transcript\",\"text\":\"\(huge)\"}"
    expectEq(ScribeTranscriber.event(fromJSON: json), .ignored,
             "scribe: un mensaje sobre el tope no llega al parser")
}

@Test func scribeChunkMessageCarriesDocumentedFields() {
    let pcm = Data([0x01, 0x02, 0x03, 0x04])
    let obj = parseObject(ScribeTranscriber.chunkJSON(pcm))
    expectEq(obj["message_type"] as? String, "input_audio_chunk", "chunk: tipo")
    expectEq(obj["audio_base_64"] as? String, pcm.base64EncodedString(), "chunk: audio base64")
    expectEq(obj["commit"] as? Bool, false, "chunk: commit manual apagado (turn_prediction decide)")
    expectEq(obj["sample_rate"] as? Int, 24000, "chunk: 24 kHz, el formato del mic")
}

@Test func scribeEndpointIsElevenLabsWithTurnPrediction() throws {
    let url = try #require(ScribeTranscriber.endpoint(language: "es"))
    let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
    expectEq(parts?.scheme, "wss", "endpoint: solo wss")
    expectEq(parts?.host, "api.elevenlabs.io", "endpoint: solo el host global de ElevenLabs")
    expectEq(parts?.path, "/v1/speech-to-text/realtime", "endpoint: ruta documentada")
    let query = Dictionary(uniqueKeysWithValues:
        (parts?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    expectEq(query["model_id"], "scribe_v2_realtime", "endpoint: modelo Scribe v2 Realtime")
    expectEq(query["commit_strategy"], "turn_prediction", "endpoint: fin de turno por el modelo")
    expectEq(query["language_code"], "es", "endpoint: idioma de la app")
    expectEq(query["audio_format"], "pcm_24000", "endpoint: PCM16 a 24 kHz, sin remuestreo")
    expect(query["xi-api-key"] == nil && query["token"] == nil,
           "endpoint: ninguna credencial en la URL")
}

@Test func scribeKeyTravelsOnlyInTheHeaderToElevenLabs() throws {
    let url = try #require(ScribeTranscriber.endpoint(language: "en"))
    let request = try #require(ScribeTranscriber.request(url: url, key: "sk_test_secret"))
    expectEq(request.value(forHTTPHeaderField: "xi-api-key"), "sk_test_secret",
             "key: va en el header xi-api-key")
    expect(!(request.url?.absoluteString.contains("sk_test_secret") ?? true),
           "key: nunca aparece en la URL")
}

@Test func scribeRefusesToSendKeyToAnotherHost() throws {
    let evil = try #require(URL(string: "wss://evil.example.com/v1/speech-to-text/realtime"))
    expect(ScribeTranscriber.request(url: evil, key: "sk_test_secret") == nil,
           "key: un host ajeno no recibe request con la clave")
    let plain = try #require(URL(string: "ws://api.elevenlabs.io/v1/speech-to-text/realtime"))
    expect(ScribeTranscriber.request(url: plain, key: "sk_test_secret") == nil,
           "key: sin wss no sale la clave")
}

@Test func scribeRedirectsStayOnElevenLabs() throws {
    let ok = try #require(URL(string: "https://api.elevenlabs.io/v1/speech-to-text/realtime"))
    let off = try #require(URL(string: "https://attacker.example.com/collect"))
    expect(ScribeTranscriber.isAllowedRedirect(to: ok), "redirect: al mismo host se sigue")
    expect(!ScribeTranscriber.isAllowedRedirect(to: off),
           "redirect: a otro host se corta antes de llevar la clave")
}

@Test func scribeLanguageFollowsAppLocale() {
    expectEq(ScribeTranscriber.languageCode(from: "es-MX"), "es", "lang: es-MX pide español")
    expectEq(ScribeTranscriber.languageCode(from: "en-US"), "en", "lang: en-US pide inglés")
    expectEq(ScribeTranscriber.languageCode(from: "pt-BR"), "pt", "lang: pt-BR pide portugués")
    expectEq(ScribeTranscriber.languageCode(from: "de-DE"), "en",
             "lang: un idioma fuera de la app cae a inglés")
}

@Test func scribeReconnectBackoffIsBounded() {
    expect(ScribeTranscriber.retryDelay(afterAttempt: 0) != nil, "backoff: primer reintento")
    expect(ScribeTranscriber.retryDelay(afterAttempt: 1) != nil, "backoff: segundo reintento")
    expect(ScribeTranscriber.retryDelay(afterAttempt: 2) == nil,
           "backoff: tercer intento se rinde, no reintenta para siempre")
}

@Test func realtimeEarPrefersElevenLabsKey() {
    expectEq(RealtimeEarChoice.resolve(elevenLabsKey: "el_key", openAIKey: "sk_openai"),
             .scribe, "selección: clave de ElevenLabs gana a OpenAI")
}

@Test func realtimeEarFallsBackToOpenAIKey() {
    expectEq(RealtimeEarChoice.resolve(elevenLabsKey: nil, openAIKey: "sk_openai"),
             .openAI, "selección: sin ElevenLabs usa OpenAI")
}

@Test func realtimeEarWithoutKeysIsNone() {
    expectEq(RealtimeEarChoice.resolve(elevenLabsKey: nil, openAIKey: nil),
             .unavailable, "selección: sin claves no hay oído realtime")
    expectEq(RealtimeEarChoice.resolve(elevenLabsKey: "   ", openAIKey: nil),
             .unavailable, "selección: una clave en blanco cuenta como ausente")
}

private func parseObject(_ json: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]
}
