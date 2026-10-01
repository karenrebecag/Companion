import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Wave 15f-7a: la boca de ElevenLabs detrás del mismo puerto `TTSFetching`.
// La clave se lee al pedir, nunca al construir; la voz sale de `Config`.

private let brian = "Gubgw9l4dtIoQA9YZHgx"
private let brianURL =
    "https://api.elevenlabs.io/v1/text-to-speech/\(brian)/stream?output_format=pcm_24000"

private func elevenBody(_ request: URLRequest?) -> [String: Any] {
    guard let data = request?.httpBody,
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return object
}

private func drain(_ stream: AsyncThrowingStream<Data, Error>) async throws -> Data {
    var all = Data()
    for try await chunk in stream { all.append(chunk) }
    return all
}

@Test @MainActor func testTheElevenLabsRequestHasTheDocumentedShape() async {
    let transport = ScriptedTransport()
    transport.stub(url: brianURL, ScriptedReply(status: 200, body: Data([1, 2, 3, 4])))
    let secrets = ScriptedSecrets([.elevenLabs: "  sk_eleven_test_0000  "])
    let es = ElevenLabsTTSClient(
        secrets: secrets, transport: transport, language: .es, voiceID: { brian })
    expectEq(secrets.reads, 0, "elevenlabs: construir no lee el llavero")

    do {
        let audio = try await drain(es.stream("Ya quedó.", voice: .marin))
        expectEq(audio, Data([1, 2, 3, 4]), "elevenlabs: el PCM llega tal cual")
    } catch {
        expect(false, "elevenlabs: stream no debía tirar \(error)")
    }
    let request = transport.requests.last
    expectEq(request?.url?.absoluteString, brianURL, "elevenlabs: URL con voz y pcm_24000")
    expectEq(request?.httpMethod, "POST", "elevenlabs: POST")
    expectEq(request?.value(forHTTPHeaderField: "xi-api-key"), "sk_eleven_test_0000",
             "elevenlabs: la clave va recortada en xi-api-key")
    expect(request?.value(forHTTPHeaderField: "Authorization") == nil,
           "elevenlabs: nunca Authorization")
    expectEq(request?.value(forHTTPHeaderField: "Content-Type"), "application/json",
             "elevenlabs: cuerpo JSON")
    let body = elevenBody(request)
    expectEq(body["text"] as? String, "Ya quedó.", "elevenlabs: text = solo la frase")
    expectEq(body["model_id"] as? String, "eleven_flash_v2_5", "elevenlabs: modelo flash")
    expectEq(body["language_code"] as? String, "es", "elevenlabs: idioma de la app")
    expectEq(Set(body.keys), ["text", "model_id", "language_code"],
             "elevenlabs: ni speed ni instructions ni voice en el cuerpo")
    expect(secrets.reads > 0, "elevenlabs: la clave se lee al pedir")

    let en = ElevenLabsTTSClient(
        secrets: secrets, transport: transport, language: .en, voiceID: { brian })
    do {
        let audio = try await en.fetch("Done.", voice: .cedar)
        expectEq(audio, Data([1, 2, 3, 4]), "elevenlabs: fetch devuelve el cuerpo")
    } catch {
        expect(false, "elevenlabs: fetch no debía tirar \(error)")
    }
    expectEq(elevenBody(transport.requests.last)["language_code"] as? String, "en",
             "elevenlabs: inglés con la app en inglés")
}

@Test @MainActor func testElevenLabsWithoutAKeyNeverSendsARequest() async {
    let transport = ScriptedTransport()
    let client = ElevenLabsTTSClient(
        secrets: ScriptedSecrets([.openAI: "sk-other"]), transport: transport,
        language: .es, voiceID: { brian })
    do {
        _ = try await drain(client.stream("Hola.", voice: .marin))
        expect(false, "sin clave: debía tirar")
    } catch {
        expectEq(error as? ChatError, .invalidKey, "sin clave: invalidKey")
    }
    expect(transport.requests.isEmpty, "sin clave: ninguna petición sale")
}

@Test @MainActor func testElevenLabsSurfacesTheHTTPStatus() async {
    let transport = ScriptedTransport()
    transport.stub(url: brianURL, ScriptedReply(status: 401, body: Data("{}".utf8)))
    let client = ElevenLabsTTSClient(
        secrets: ScriptedSecrets([.elevenLabs: "sk_eleven_test_0000"]), transport: transport,
        language: .es, voiceID: { brian })
    do {
        _ = try await drain(client.stream("Hola.", voice: .marin))
        expect(false, "401: debía tirar")
    } catch {
        expectEq(error as? ChatError, .httpStatus(401), "401: el estado viaja en el error")
    }
}

/// Security review 2026-09-25 (LOW-1): a voice id is config, not code.
/// Escaping kept a hostile one inside its path segment; now anything but
/// 1-64 ASCII letters and digits is refused before a request (or a Keychain
/// read) exists.
@Test @MainActor func testAMalformedVoiceIDIsRefusedWithoutARequest() async {
    let bad = ["../../v1/user?x=1", "abc%2Fdef", "vozñandú", "Gubgw9l4dtIoQA9YZHgx\u{0301}",
               "", "   ", "abc def", String(repeating: "a", count: 65)]
    for voice in bad {
        let transport = ScriptedTransport()
        let secrets = ScriptedSecrets([.elevenLabs: "sk_eleven_test_0000"])
        let client = ElevenLabsTTSClient(
            secrets: secrets, transport: transport, language: .es, voiceID: { voice })
        do {
            _ = try await client.fetch("Hola.", voice: .marin)
            expect(false, "L1: '\(voice)' debía rechazarse")
        } catch {
            expect(error is ElevenLabsTTSClient.InvalidVoiceID,
                   "L1: '\(voice)' se rechaza como voz inválida")
        }
        do {
            _ = try await drain(client.stream("Hola.", voice: .marin))
            expect(false, "L1: stream con '\(voice)' debía rechazarse")
        } catch {
            expect(error is ElevenLabsTTSClient.InvalidVoiceID,
                   "L1: stream también rechaza '\(voice)'")
        }
        expect(transport.requests.isEmpty, "L1: '\(voice)' nunca sale a la red")
        expectEq(secrets.reads, 0, "L1: ni lee el llavero para '\(voice)'")
    }
    let longest = String(repeating: "a", count: 64)
    expect(ElevenLabsTTSClient.isValidVoiceID(longest), "L1: 64 alfanuméricos valen")
    expect(ElevenLabsTTSClient.isValidVoiceID(brian), "L1: un id real vale")
    expect(ElevenLabsTTSClient.isValidVoiceID("  \(brian) \n"),
           "L1: los blancos de los extremos se recortan antes de validar")
}

@Test @MainActor func testTheElevenLabsCacheVariantCarriesModelAndVoice() {
    let secrets = ScriptedSecrets([.elevenLabs: "sk_eleven_test_0000"])
    let a = ElevenLabsTTSClient(
        secrets: secrets, transport: ScriptedTransport(), language: .es, voiceID: { brian })
    let b = ElevenLabsTTSClient(
        secrets: secrets, transport: ScriptedTransport(), language: .es, voiceID: { "otraVoz123" })
    expectEq(a.cacheVariant(voice: .marin), "elevenlabs/eleven_flash_v2_5/\(brian)",
             "caché: proveedor/modelo/voz")
    expect(a.cacheVariant(voice: .marin) != b.cacheVariant(voice: .marin),
           "caché: otra voz, otra clave")
    expectEq(a.cacheVariant(voice: .marin), a.cacheVariant(voice: .cedar),
             "caché: la voz de OpenAI no aplica")
    expectEq(secrets.reads, 0, "caché: la variante no toca el llavero")
}

@Test @MainActor func testElevenLabsWarmIsAHandshakeWithoutTheKey() async {
    let transport = ScriptedTransport()
    transport.stub(url: "https://api.elevenlabs.io/v1/models", ScriptedReply(status: 401))
    let secrets = ScriptedSecrets([.elevenLabs: "sk_eleven_test_0000"])
    let client = ElevenLabsTTSClient(
        secrets: secrets, transport: transport, language: .es, voiceID: { brian })
    await client.warm()
    let request = transport.requests.last
    expectEq(request?.url?.absoluteString, "https://api.elevenlabs.io/v1/models", "warm: host")
    expectEq(request?.httpMethod, "GET", "warm: GET")
    expect(request?.value(forHTTPHeaderField: "xi-api-key") == nil, "warm: sin clave")
    expect(request?.httpBody == nil, "warm: sin cuerpo")
    expectEq(secrets.reads, 0, "warm: nunca toca el llavero")
}

// MARK: - Router

@Test @MainActor func testTheRouterPicksElevenLabsOnlyWithKeyAndVoice() async {
    let cases: [(key: String?, voice: String, expected: String, label: String)] = [
        ("sk_eleven_test_0000", brian, "eleven", "clave+voz"),
        ("sk_eleven_test_0000", "", "openai", "clave sin voz"),
        ("sk_eleven_test_0000", "   ", "openai", "clave con voz en blanco"),
        (nil, brian, "openai", "voz sin clave"),
        ("   ", brian, "openai", "clave en blanco"),
    ]
    for c in cases {
        var values: [SecretKey: String] = [.openAI: "sk-test"]
        if let key = c.key { values[.elevenLabs] = key }
        let eleven = ScriptedMouth("eleven")
        let openAI = ScriptedMouth("openai")
        let voice = c.voice
        let router = MouthRouter(
            elevenLabs: eleven, openAI: openAI,
            secrets: ScriptedSecrets(values), voiceID: { voice })
        do {
            let audio = try await drain(router.stream("Hola.", voice: .marin))
            expectEq(String(decoding: audio, as: UTF8.self), "\(c.expected):Hola.",
                     "router \(c.label): habla \(c.expected)")
        } catch {
            expect(false, "router \(c.label): no debía tirar \(error)")
        }
        expectEq(router.cacheVariant(voice: .marin), c.expected,
                 "router \(c.label): la caché es la de \(c.expected)")
    }
}

@Test @MainActor func testTheRouterReadsNoKeyUntilAsked() {
    let secrets = ScriptedSecrets([.elevenLabs: "sk_eleven_test_0000"])
    let router = MouthRouter(
        elevenLabs: ScriptedMouth("eleven"), openAI: ScriptedMouth("openai"),
        secrets: secrets, voiceID: { brian })
    _ = SpeechSynthesis(
        cache: PhraseCache(directory: makeTTSTempDir("router-boot")), fetcher: router,
        playback: FakePlay(), fallback: FakeFallback(), voice: .marin)
    expectEq(secrets.reads, 0, "arranque: ni el router ni la boca leen el llavero")
}

@Test @MainActor func testAnElevenLabsFailureRetriesOnceThroughOpenAI() async {
    let logURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-eleven-\(UUID().uuidString).log")
    defer { try? FileManager.default.removeItem(at: logURL) }
    let eleven = ScriptedMouth("eleven", failure: ChatError.httpStatus(429))
    let openAI = ScriptedMouth("openai")
    let router = MouthRouter(
        elevenLabs: eleven, openAI: openAI,
        secrets: ScriptedSecrets([.elevenLabs: "sk_eleven_test_0000"]), voiceID: { brian })
    await Log.capturing(to: logURL) {
        do {
            let audio = try await drain(router.stream("Secreto.", voice: .marin))
            expectEq(String(decoding: audio, as: UTF8.self), "openai:Secreto.",
                     "fallback: la frase la dice OpenAI")
        } catch {
            expect(false, "fallback: no debía tirar \(error)")
        }
    }
    expectEq(eleven.calls, ["Secreto."], "fallback: ElevenLabs se intentó una vez")
    expectEq(openAI.calls, ["Secreto."], "fallback: OpenAI una sola vez")
    let text = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
    let lines = text.split(separator: "\n").filter { $0.contains("tts: elevenlabs failed") }
    expectEq(lines.count, 1, "fallback: una línea")
    expect(lines.first?.hasSuffix("tts: elevenlabs failed status=429, openai fallback") == true,
           "fallback: solo números (\(lines))")
    expect(!text.contains("Secreto"), "fallback: el log nunca lleva la frase")
}

/// Both mouths down: the synthesizer's own path takes over, and OpenAI was
/// asked exactly once — no loop between the two.
@Test @MainActor func testBothMouthsDownFallToTheSystemVoice() async {
    let dir = makeTTSTempDir("both-down")
    defer { try? FileManager.default.removeItem(at: dir) }
    let eleven = ScriptedMouth("eleven", failure: ChatError.httpStatus(500))
    let openAI = ScriptedMouth("openai", failure: ChatError.httpStatus(503))
    let router = MouthRouter(
        elevenLabs: eleven, openAI: openAI,
        secrets: ScriptedSecrets([.elevenLabs: "sk_eleven_test_0000"]), voiceID: { brian })
    let fallback = FakeFallback()
    let synth = SpeechSynthesis(
        cache: PhraseCache(directory: dir), fetcher: router, playback: FakePlay(),
        fallback: fallback, voice: .marin)
    _ = await speak(synth, "Hola.")
    expectEq(fallback.spoken, ["Hola."], "ambas caídas: habla la voz del sistema")
    expectEq(eleven.calls, ["Hola."], "ambas caídas: ElevenLabs una vez")
    expectEq(openAI.calls, ["Hola."], "ambas caídas: OpenAI una vez")
}

/// Audio voiced by the OpenAI fallback must never be replayed later as if
/// it were the ElevenLabs voice.
@Test @MainActor func testFallbackAudioIsNeverCachedAsElevenLabs() async {
    let dir = makeTTSTempDir("fallback-cache")
    defer { try? FileManager.default.removeItem(at: dir) }
    let eleven = ScriptedMouth("eleven", failure: ChatError.httpStatus(401))
    let openAI = ScriptedMouth("openai")
    let secrets = ScriptedSecrets([.elevenLabs: "sk_eleven_test_0000"])
    let router = MouthRouter(
        elevenLabs: eleven, openAI: openAI, secrets: secrets, voiceID: { brian })
    let synth = SpeechSynthesis(
        cache: PhraseCache(directory: dir), fetcher: router, playback: FakePlay(),
        fallback: FakeFallback(), voice: .marin)
    _ = await speak(synth, "Listo.")
    expect(!(await synth.isCached("Listo.")), "fallback: no se guarda bajo ElevenLabs")

    // `events` is a single-consumer stream, so a second turn on the same
    // synthesizer would hang the tap; a fresh one over the same cache and
    // router is what the next hold gets anyway.
    // Code review 2026-09-25 (MEDIUM-B): a 401 pauses ElevenLabs until the
    // key changes, so recovering means saving a new one.
    eleven.failure = nil
    secrets.values[.elevenLabs] = "sk_eleven_test_1111"
    let recovered = SpeechSynthesis(
        cache: PhraseCache(directory: dir), fetcher: router, playback: FakePlay(),
        fallback: FakeFallback(), voice: .marin)
    _ = await speak(recovered, "Listo.")
    expectEq(eleven.calls, ["Listo.", "Listo."], "recuperado: se vuelve a pedir a ElevenLabs")
    expect(await recovered.isCached("Listo."), "recuperado: ahora sí se guarda")
}
