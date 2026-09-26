import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Wave 15f-5 (spec §4 rows 7-8): el cuerpo de la petición lleva `speed` e
// `instructions`, la caché no mezcla audio de otro estilo, y la boca reporta
// sus tres instantes de la primera frase.

private let speechURL = "https://api.openai.com/v1/audio/speech"

private func speechBody(_ request: URLRequest?) -> [String: Any] {
    guard let data = request?.httpBody,
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return object
}

/// Row 7: both paths (prewarm's `fetch`, the live `stream`) send speed 1.1
/// and the conversational instructions of the app's language; `input` is
/// only the sentence.
@Test @MainActor func testTheSpeechRequestCarriesSpeedAndInstructions() async {
    let transport = ScriptedTransport()
    transport.stub(url: speechURL, ScriptedReply(status: 200, body: Data([1, 2])))
    let secrets = ScriptedSecrets([.openAI: "sk-test"])
    let spanish = "Habla en español de México, conversacional, ágil y natural, sin pausas teatrales."

    let es = OpenAITTSClient(secrets: secrets, transport: transport, language: .es)
    do {
        _ = try await es.fetch("Ya quedó, ¿algo más?", voice: .marin)
    } catch {
        expect(false, "cuerpo: fetch no debía tirar \(error)")
    }
    let fetched = speechBody(transport.requests.last)
    expectEq(fetched["speed"] as? Double, 1.1, "cuerpo es: speed 1.1")
    expectEq(fetched["instructions"] as? String, spanish, "cuerpo es: instrucciones del spec")
    expectEq(fetched["input"] as? String, "Ya quedó, ¿algo más?", "cuerpo es: input = la frase")
    expectEq(fetched["response_format"] as? String, "pcm", "cuerpo es: sigue en pcm")
    expectEq(fetched["voice"] as? String, "marin", "cuerpo es: la voz")

    let en = OpenAITTSClient(secrets: secrets, transport: transport, language: .en)
    do {
        for try await _ in en.stream("Done.", voice: .cedar) {}
    } catch {
        expect(false, "cuerpo: stream no debía tirar \(error)")
    }
    let streamed = speechBody(transport.requests.last)
    expectEq(streamed["speed"] as? Double, 1.1, "cuerpo en: speed 1.1")
    let english = streamed["instructions"] as? String ?? ""
    expect(english.contains("English") && english != spanish,
           "cuerpo en: instrucciones en inglés, no las del español")
    expectEq(streamed["input"] as? String, "Done.", "cuerpo en: input = la frase")

    let custom = OpenAITTSClient(
        secrets: secrets, transport: transport, language: .es,
        speed: 1.25, instructions: "Rápido.")
    do {
        _ = try await custom.fetch("Hola.", voice: .marin)
    } catch {
        expect(false, "cuerpo: fetch inyectado no debía tirar \(error)")
    }
    let injected = speechBody(transport.requests.last)
    expectEq(injected["speed"] as? Double, 1.25, "cuerpo: speed inyectable")
    expectEq(injected["instructions"] as? String, "Rápido.", "cuerpo: instrucciones inyectables")
}

/// Row 7: PCM cached at the old settings (speed 1.0, no instructions) must
/// not be replayed once the style changes — the key carries voice, speed
/// and instructions.
@Test @MainActor func testTheCacheKeyCarriesVoiceSpeedAndInstructions() async {
    let transport = ScriptedTransport()
    let secrets = ScriptedSecrets([.openAI: "sk-test"])
    let base = OpenAITTSClient(secrets: secrets, transport: transport, language: .es)
    let slower = OpenAITTSClient(
        secrets: secrets, transport: transport, language: .es, speed: 1.0)
    let plain = OpenAITTSClient(
        secrets: secrets, transport: transport, language: .es, instructions: "Otra.")
    let variant = base.cacheVariant(voice: .marin)
    expect(!variant.isEmpty, "clave: el cliente real declara su estilo")
    expectEq(variant, base.cacheVariant(voice: .marin), "clave: estable")
    expect(variant != base.cacheVariant(voice: .cedar), "clave: cambia con la voz")
    expect(variant != slower.cacheVariant(voice: .marin), "clave: cambia con speed")
    expect(variant != plain.cacheVariant(voice: .marin), "clave: cambia con instrucciones")
    expect(!variant.contains("Habla"), "clave: las instrucciones van con hash, no en claro")

    let dir = makeTTSTempDir("style-key")
    defer { try? FileManager.default.removeItem(at: dir) }
    let cache = PhraseCache(directory: dir)
    do {
        try cache.store(Data("vieja".utf8), for: "Hola.")
        expectEq(try cache.scoped("").data(for: "Hola."), Data("vieja".utf8),
                 "clave: sin variante es la misma caché de siempre")
        expectEq(try cache.scoped("marin|1.1").data(for: "Hola."), nil,
                 "clave: otra variante no ve el audio viejo")
    } catch {
        expect(false, "clave: la caché no debía tirar \(error)")
    }

    let fetch = StyledFetch()
    let play = FakePlay()
    let synth = SpeechSynthesis(
        cache: cache, fetcher: fetch, playback: play, fallback: FakeFallback(), voice: .marin)
    _ = await speak(synth, "Hola.")
    expectEq(fetch.calls, ["Hola."], "clave: el audio viejo no se reproduce; se pide de nuevo")
    expectEq(await play.texts, ["nueva"], "clave: suena el audio con el estilo nuevo")
    expect(await synth.isCached("Hola."), "clave: queda guardado bajo la clave nueva")
    do {
        expectEq(try cache.data(for: "Hola."), Data("vieja".utf8),
                 "clave: el archivo viejo no se sobrescribe")
    } catch {
        expect(false, "clave: leer la caché no debía tirar \(error)")
    }
}

/// Row 8: the first sentence of a turn reports cut, request and first
/// byte, in that order and before it sounds; later sentences stay quiet.
/// The log line carries only the number.
@Test @MainActor func testTheFirstSentenceReportsItsMouthMarks() async {
    let dir = makeTTSTempDir("mouth-marks")
    defer { try? FileManager.default.removeItem(at: dir) }
    let logURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-mouth-\(UUID().uuidString).log")
    defer { try? FileManager.default.removeItem(at: logURL) }
    let fetch = ScriptedStreamFetch(log: PipelineLog())
    let synth = SpeechSynthesis(
        cache: PhraseCache(directory: dir), fetcher: fetch, playback: FakePlay(),
        fallback: FakeFallback(), voice: .marin)
    let tap = EventTap.start(synth.events, keepMarks: true)
    await Log.capturing(to: logURL) {
        await synth.begin()
        await synth.enqueue("Uno.")
        await synth.enqueue("Dos.")
        await synth.finish()
        expectEq(await tap.waitTerminal(), [
            .mark(.firstCut), .mark(.ttsRequest), .mark(.firstByte),
            .chunkStarted(text: "Uno.", duration: 0),
            .chunkStarted(text: "Dos.", duration: 0),
            .finished,
        ], "marcas: solo la primera frase, en orden y antes de sonar")
    }
    let text = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
    let lines = text.split(separator: "\n").filter { $0.contains("tts: first byte") }
    expectEq(lines.count, 1, "marcas: una línea de primer byte por turno")
    let ok = lines.first.map { line in
        line.range(of: #"tts: first byte \d+ms$"#, options: .regularExpression) != nil
    } ?? false
    expect(ok, "marcas: la línea lleva solo el número (\(lines))")
    expect(!text.contains("Uno."), "marcas: el log nunca lleva la frase")
}

/// Row 8: a scripted classic turn — the mouth's marks land on the session's
/// clock and the `voice timeline:` line carries the three new segments with
/// values; `firstToken→audio` stays. Marks with no released hold are a
/// stranger's (a job announcement) and are dropped.
@Test @MainActor func testTheVoiceTimelineCarriesTheMouthSegments() async {
    let logURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-timeline-\(UUID().uuidString).log")
    defer { try? FileManager.default.removeItem(at: logURL) }
    await Log.capturing(to: logURL) {
        let h = makeVoiceHarness()
        h.synth.yield(.mark(.firstCut))
        await settle(0.05)
        expectEq(await h.session.timeline.firstCut, nil, "boca: sin hold no se marca")

        h.transcriber.stoppedText = "abre Safari"
        h.chat.rounds = [[.text("Listo.")]]
        h.clock.now = 10
        await h.session.hold()
        await pumpUntil("boca: listening") { h.watch.latest.state == .listening }
        h.clock.now = 11
        await h.session.release()
        await pumpUntil("boca: habla") { h.synth.queue.contains("Listo.") }
        h.clock.now = 11.4
        h.synth.yield(.mark(.firstCut))
        await pumpUntilAsync("boca: firstCut") { await h.session.timeline.firstCut != nil }
        h.clock.now = 11.42
        h.synth.yield(.mark(.ttsRequest))
        await pumpUntilAsync("boca: ttsRequest") { await h.session.timeline.ttsRequest != nil }
        h.clock.now = 12.0
        h.synth.yield(.mark(.firstByte))
        await pumpUntilAsync("boca: firstByte") { await h.session.timeline.firstByte != nil }
        h.clock.now = 12.03
        h.synth.yield(.chunkStarted(text: "Listo.", duration: 0))
        await pumpUntilAsync("boca: se aplana") { await h.session.lastTimeline != nil }
    }
    let text = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
    let line = text.split(separator: "\n").first { $0.contains("voice timeline:") }
        .map(String.init) ?? ""
    expect(line.contains("firstCut→ttsRequest 20"), "boca: corte a petición (\(line))")
    expect(line.contains("ttsRequest→firstByte 580"), "boca: petición a primer byte (\(line))")
    expect(line.contains("firstByte→audible 30"), "boca: primer byte a audible (\(line))")
    expect(line.contains("firstToken→audio"), "boca: firstToken→audio sigue en la línea")
}

/// Row 8: a fetcher with a style of its own; returns fresh audio every time.
final class StyledFetch: TTSFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []
    var calls: [String] { lock.withLock { stored } }

    func fetch(_ text: String, voice: VoiceID) async throws -> Data {
        lock.withLock { stored.append(text) }
        return Data("nueva".utf8)
    }

    func cacheVariant(voice: VoiceID) -> String { "\(voice.rawValue)|1.1|abc" }
}
