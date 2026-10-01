import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Code review 2026-09-25 (MEDIUM-A, MEDIUM-B, LOW-3).
// MEDIUM-A: the router remembered which sentences the OpenAI fallback voiced
// in a ledger keyed by TEXT. Two identical sentences, one voiced by
// ElevenLabs and one by the fallback, swapped marks — OpenAI audio was
// stored as ElevenLabs — and a mark left by a prefetch cut by `stop()` was
// never taken, so a later good ElevenLabs sentence was not cached.
// MEDIUM-B: with ElevenLabs failing, every sentence paid a failed request
// first; there was no breaker.
// LOW-3: a Keychain read error fell to OpenAI without a word in the log.

private let voice = "Gubgw9l4dtIoQA9YZHgx"

/// Fails on the listed call numbers (1-based), names itself otherwise.
private final class SequenceMouth: TTSFetching, @unchecked Sendable {
    private let lock = NSLock()
    private let name: String
    private let failing: [Int: Error]
    private var stored: [String] = []
    var calls: [String] { lock.withLock { stored } }

    init(_ name: String, failing: [Int: Error] = [:]) {
        self.name = name
        self.failing = failing
    }

    func fetch(_ text: String, voice: VoiceID) async throws -> Data {
        let number: Int = lock.withLock {
            stored.append(text)
            return stored.count
        }
        if let failure = failing[number] { throw failure }
        return Data("\(name):\(text)".utf8)
    }

    func cacheVariant(voice: VoiceID) -> String { name }
}

/// Holds the first sentence's playback until `release()` answers true, so
/// the prefetch of the second one is known to have run before the first
/// asks whether it may be cached.
private actor GatedFirstPlay: SpeechPlayback {
    private let release: @Sendable () -> Bool
    private var first = true
    init(release: @escaping @Sendable () -> Bool) { self.release = release }

    func play(_ data: Data) async throws {}

    func play(_ chunks: AsyncThrowingStream<Data, Error>) async throws -> Data {
        var assembled = Data()
        for try await chunk in chunks { assembled.append(chunk) }
        if first {
            first = false
            let deadline = Date().addingTimeInterval(5)
            while !release(), Date() < deadline {
                try await Task.sleep(nanoseconds: 1_000_000)
            }
        }
        return assembled
    }

    func stop() async {}
}

private final class TestInstant: @unchecked Sendable {
    private let lock = NSLock()
    private let base = ContinuousClock.now
    private var offset: Duration = .zero
    var now: ContinuousClock.Instant { lock.withLock { base + offset } }
    func advance(_ by: Duration) { lock.withLock { offset += by } }
}

private final class BrokenKeychain: SecretStore, @unchecked Sendable {
    struct Locked: Error {}
    func read(_ key: SecretKey) throws -> String? { throw Locked() }
    func write(_ key: SecretKey, value: String) throws {}
    func delete(_ key: SecretKey) throws {}
}

private func logLines(_ url: URL, containing needle: String) -> [Substring] {
    let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    return text.split(separator: "\n").filter { $0.contains(needle) }
}

private func tempLog(_ label: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-\(label)-\(UUID().uuidString).log")
}

private func cached(_ cache: PhraseCache, _ phrase: String) -> String? {
    do {
        return try cache.data(for: phrase).map { String(decoding: $0, as: UTF8.self) }
    } catch {
        return nil
    }
}

private func streamed(_ router: MouthRouter, _ text: String) async -> String {
    var all = Data()
    do {
        for try await chunk in router.resolved().stream(text, voice: .marin) { all.append(chunk) }
    } catch {
        return "error"
    }
    return String(decoding: all, as: UTF8.self)
}

// MARK: - MEDIUM-A

@Test @MainActor func testIdenticalSentencesKeepTheirOwnProvenance() async {
    let dir = makeTTSTempDir("provenance-twins")
    defer { try? FileManager.default.removeItem(at: dir) }
    let eleven = SequenceMouth("eleven", failing: [2: ChatError.httpStatus(500)])
    let openAI = SequenceMouth("openai")
    let router = MouthRouter(
        elevenLabs: eleven, openAI: openAI,
        secrets: ScriptedSecrets([.elevenLabs: "sk_eleven_test_0000"]), voiceID: { voice })
    let synth = SpeechSynthesis(
        cache: PhraseCache(directory: dir), fetcher: router,
        playback: GatedFirstPlay(release: { !openAI.calls.isEmpty }),
        fallback: FakeFallback(), voice: .marin)
    _ = await speak(synth, "Listo.", "Listo.")
    expectEq(eleven.calls.count, 2, "M-A: las dos frases se pidieron a ElevenLabs")
    expectEq(openAI.calls, ["Listo."], "M-A: la segunda cayó a OpenAI")
    let base = PhraseCache(directory: dir)
    expectEq(cached(base.scoped("eleven"), "Listo."), "eleven:Listo.",
             "M-A: la primera se guarda bajo ElevenLabs con su propio audio")
    expect(cached(base.scoped("openai"), "Listo.") == nil,
           "M-A: la de respaldo no se guarda")
}

@Test @MainActor func testAStoppedPrefetchLeavesNoMarkBehind() async {
    let dir = makeTTSTempDir("provenance-stop")
    defer { try? FileManager.default.removeItem(at: dir) }
    let eleven = SequenceMouth("eleven", failing: [2: ChatError.httpStatus(500)])
    let openAI = SequenceMouth("openai")
    let router = MouthRouter(
        elevenLabs: eleven, openAI: openAI,
        secrets: ScriptedSecrets([.elevenLabs: "sk_eleven_test_0000"]), voiceID: { voice },
        cooldown: .zero)
    let play = FakePlay(blockAt: 1)
    let synth = SpeechSynthesis(
        cache: PhraseCache(directory: dir), fetcher: router, playback: play,
        fallback: FakeFallback(), voice: .marin)
    await synth.begin()
    await synth.enqueue("Uno.")
    await synth.enqueue("Dos.")
    await play.waitBlocked()
    await pumpUntil("M-A: el prefetch de 'Dos.' cayó a OpenAI") { openAI.calls == ["Dos."] }
    await synth.stop()

    let next = SpeechSynthesis(
        cache: PhraseCache(directory: dir), fetcher: router, playback: FakePlay(),
        fallback: FakeFallback(), voice: .marin)
    _ = await speak(next, "Dos.")
    expectEq(eleven.calls, ["Uno.", "Dos.", "Dos."], "M-A: la frase se vuelve a pedir a ElevenLabs")
    expectEq(cached(PhraseCache(directory: dir).scoped("eleven"), "Dos."), "eleven:Dos.",
             "M-A: tras un stop no queda marca: el audio bueno se guarda")
}

// MARK: - MEDIUM-B

@Test @MainActor func testA429PausesElevenLabsForTheCooldown() async {
    let url = tempLog("breaker-429")
    defer { try? FileManager.default.removeItem(at: url) }
    let clock = TestInstant()
    let eleven = SequenceMouth("eleven", failing: [1: ChatError.httpStatus(429)])
    let openAI = SequenceMouth("openai")
    let router = MouthRouter(
        elevenLabs: eleven, openAI: openAI,
        secrets: ScriptedSecrets([.elevenLabs: "sk_eleven_test_0000"]), voiceID: { voice },
        now: { clock.now })
    await Log.capturing(to: url) {
        expectEq(await streamed(router, "Uno."), "openai:Uno.", "M-B: la primera cae a OpenAI")
        expectEq(await streamed(router, "Dos."), "openai:Dos.", "M-B: la segunda va directo a OpenAI")
        expectEq(eleven.calls, ["Uno."], "M-B: sin segunda llamada a ElevenLabs")
        clock.advance(.seconds(59))
        expectEq(await streamed(router, "Tres."), "openai:Tres.", "M-B: 59 s sigue en pausa")
        clock.advance(.seconds(2))
        expectEq(await streamed(router, "Cuatro."), "eleven:Cuatro.",
                 "M-B: pasado el enfriamiento se vuelve a intentar ElevenLabs")
    }
    let lines = logLines(url, containing: "tts: elevenlabs paused")
    expectEq(lines.count, 1, "M-B: una sola línea de pausa")
    expect(lines.first?.hasSuffix("tts: elevenlabs paused 60s status=429") == true,
           "M-B: formato (\(lines))")
}

@Test @MainActor func testA401PausesUntilTheKeyChanges() async {
    let clock = TestInstant()
    let secrets = ScriptedSecrets([.elevenLabs: "sk_eleven_test_0000"])
    let eleven = SequenceMouth("eleven", failing: [1: ChatError.httpStatus(401)])
    let openAI = SequenceMouth("openai")
    let router = MouthRouter(
        elevenLabs: eleven, openAI: openAI, secrets: secrets, voiceID: { voice },
        now: { clock.now })
    expectEq(await streamed(router, "Uno."), "openai:Uno.", "M-B: 401 cae a OpenAI")
    clock.advance(.seconds(3600))
    expectEq(await streamed(router, "Dos."), "openai:Dos.", "M-B: una hora después sigue en pausa")
    expectEq(eleven.calls, ["Uno."], "M-B: con la misma clave no se reintenta")
    secrets.values[.elevenLabs] = "sk_eleven_test_1111"
    expectEq(await streamed(router, "Tres."), "eleven:Tres.",
             "M-B: una clave nueva (Ajustes) reabre ElevenLabs")
}

// MARK: - LOW-3

@Test @MainActor func testAKeychainErrorIsLoggedOnceAndFallsToOpenAI() async {
    let url = tempLog("keychain-error")
    defer { try? FileManager.default.removeItem(at: url) }
    let eleven = SequenceMouth("eleven")
    let router = MouthRouter(
        elevenLabs: eleven, openAI: SequenceMouth("openai"),
        secrets: BrokenKeychain(), voiceID: { voice })
    await Log.capturing(to: url) {
        expectEq(await streamed(router, "Uno."), "openai:Uno.", "L3: sin llavero, OpenAI")
        expectEq(await streamed(router, "Dos."), "openai:Dos.", "L3: y sigue en OpenAI")
    }
    expectEq(eleven.calls, [], "L3: ElevenLabs nunca se llama")
    let lines = logLines(url, containing: "tts: keychain read failed")
    expectEq(lines.count, 1, "L3: una sola línea")
    expect(lines.first?.hasSuffix("tts: keychain read failed") == true, "L3: sin clave ni detalle")
}
