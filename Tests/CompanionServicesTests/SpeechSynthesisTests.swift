import CompanionCore
import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

@Test @MainActor func speechSynthesisTests() async {
    testPhraseCache()
    testPhraseCacheLimits()
    testBeginFinishEmptyEmitsFinished()
    testEnqueueOrderChunkVoiceAndSkip()
    testCacheHitSkipsFetch()
    testLongPhraseNeverCached()
    testFetchErrorUsesFallback()
    testFetchAndFallbackFailEmitsFailed()
    testStopDropsPendingKeepsPrefix()
    testBeginResetsSpokenSoFar()
    testTheOfflineVoiceSpeaksTheUserLanguage()
    await testPrewarmDedupsAnInFlightFetch()
    await testStreamedChunksReachPlaybackBeforeTheStreamEnds()
    await testStopDuringAStreamSilencesAndDoesNotCacheThePartial()
    await testACompletedStreamCachesAndReplaysOffline()
}

/// La voz de respaldo entra justo cuando no hay red, que es cuando el usuario
/// menos puede permitirse que le contesten en otro idioma. Estaba fijada en
/// es-MX: el mismo bug del reconocedor, en el otro extremo del turno.
@MainActor func testTheOfflineVoiceSpeaksTheUserLanguage() {
    withSpokenSuite { suite in
        expectEq(
            AVSpeechFallback(language: .en, defaults: suite).voiceLocaleIdentifier,
            "en-US", "respaldo: a quien eligió inglés se le contesta en inglés")
        expectEq(
            AVSpeechFallback(language: .es, defaults: suite).voiceLocaleIdentifier,
            "es-MX", "respaldo: el español conserva la voz que ya tenía")
    }
}

@MainActor func testPhraseCache() {
    withTempDir { dir in
        let cache = PhraseCache(directory: dir)
        do {
            expectEq(try cache.data(for: "hola"), nil, "miss: sin archivo es nil")
            expectEq(try cache.data(for: ""), nil, "miss: vacío no inventa")
            try cache.store(Data("audio".utf8), for: "hola")
            expectEq(try cache.data(for: "hola"), Data("audio".utf8),
                     "roundtrip: recupera lo guardado")
            try cache.store(Data(), for: "vacio")
            expectEq(try cache.data(for: "vacio"), Data(), "roundtrip: Data vacío")
            try cache.store(Data("A".utf8), for: "a")
            try cache.store(Data("FOO".utf8), for: "foobar")
            expect(exists(dir, "af63dc4c8601ec8c"), "fnv: a")
            expect(exists(dir, "85944171f73967e8"), "fnv: foobar")
            expect(exists(dir, "4029fbcc7e6d3137"), "fnv: hola")
            expectEq(try cache.data(for: "a"), Data("A".utf8), "fnv: a aislada")
            expectEq(try cache.data(for: "foobar"), Data("FOO".utf8),
                     "fnv: foobar aislada")
            let phrase = "ñoño — café 👋; DROP"
            let blob = Data(repeating: 0xAB, count: 10_000)
            try cache.store(blob, for: phrase)
            expectEq(try cache.data(for: phrase), blob, "unicode: 10k roundtrip")
            expect(exists(dir, "d422d24f37c14ae6"), "fnv: unicode utf8")
            try cache.store(Data("e".utf8), for: "")
            expectEq(try cache.data(for: ""), Data("e".utf8), "vacío: count 0")
        } catch {
            expect(false, "cache: no debía tirar \(error)")
        }
    }
}

@MainActor func testPhraseCacheLimits() {
    withTempDir { dir in
        let cache = PhraseCache(directory: dir)
        let eighty = String(repeating: "n", count: 80)
        let eightyOne = String(repeating: "n", count: 81)
        do {
            try cache.store(Data("ok".utf8), for: eighty)
            expectEq(try cache.data(for: eighty), Data("ok".utf8), "80: guarda")
            try cache.store(Data("nope".utf8), for: eightyOne)
            expectEq(try cache.data(for: eightyOne), nil, "81: data nil")
            expectEq(try FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil).count, 1, "81: sin archivo")
            try cache.store(Data("wave".utf8), for: String(repeating: "👋", count: 80))
            expectEq(try cache.data(for: String(repeating: "👋", count: 80)),
                     Data("wave".utf8), "80 emoji: Character count")
            try cache.store(Data("no".utf8), for: String(repeating: "👋", count: 81))
            expectEq(try cache.data(for: String(repeating: "👋", count: 81)), nil,
                     "81 emoji: data nil")
            let file = dir.appendingPathComponent("blocked")
            try Data("no-dir".utf8).write(to: file)
            do {
                try PhraseCache(directory: file).store(Data("x".utf8), for: "hola")
                expect(false, "io: dir-archivo debía tirar")
            } catch {
                expect(true, "io: store tira si el directorio es un archivo")
            }
        } catch {
            expect(false, "límites: no debía tirar \(error)")
        }
    }
    let missing = FileManager.default.temporaryDirectory
        .appendingPathComponent("tts-miss-\(UUID().uuidString)", isDirectory: true)
    expect(!FileManager.default.fileExists(atPath: missing.path), "mkdir: no existe")
    let cache = PhraseCache(directory: missing)
    do {
        expectEq(try cache.data(for: "hola"), nil, "mkdir: miss sin dir es nil")
        try cache.store(Data("x".utf8), for: "hola")
        expectEq(try cache.data(for: "hola"), Data("x".utf8), "mkdir: crea dir")
    } catch {
        expect(false, "mkdir: no debía tirar \(error)")
    }
    try? FileManager.default.removeItem(at: missing)
}

@MainActor func testBeginFinishEmptyEmitsFinished() {
    withTempDir { dir in
        runOk("vacío") {
            let (synth, fetch, play, fallback, _) = makeTTS(dir)
            let tap = EventTap.start(synth.events)
            await synth.begin()
            expectEq(await synth.speakingNow, "", "vacío: no habla")
            expectEq(await synth.spokenSoFar(), nil, "vacío: spoken nil")
            await synth.finish()
            expectEq(await tap.waitTerminal(), [.finished], "vacío: finished")
            expect(fetch.calls.isEmpty && fallback.spoken.isEmpty, "vacío: sin I/O")
            expect(await play.played.isEmpty, "vacío: sin play")
        }
    }
}

@MainActor func testEnqueueOrderChunkVoiceAndSkip() {
    withTempDir { dir in
        runOk("orden") {
            let (synth, fetch, play, fallback, _) = makeTTS(dir, voice: .coral)
            let tap = EventTap.start(synth.events)
            await synth.begin()
            await synth.enqueue("")
            await synth.enqueue("   \n")
            await synth.enqueue("  Uno.  ")
            await synth.enqueue("Dos.")
            await synth.enqueue("Tres.")
            await synth.finish()
            expectEq(await tap.waitTerminal(), [
                .chunkStarted(text: "Uno.", duration: 0),
                .chunkStarted(text: "Dos.", duration: 0),
                .chunkStarted(text: "Tres.", duration: 0),
                .finished,
            ], "orden: chunk por frase y finished")
            expectEq(fetch.calls.map(\.text), ["Uno.", "Dos.", "Tres."],
                     "orden: fetch en cola")
            expectEq(fetch.calls.map(\.voice), [.coral, .coral, .coral],
                     "voz: VoiceID al fetch")
            expectEq(await play.texts, ["Uno.", "Dos.", "Tres."],
                     "orden: play en cola")
            expect(fallback.spoken.isEmpty, "orden: sin fallback")
            expectEq(await synth.spokenSoFar(), "Uno. Dos. Tres.",
                     "orden: spoken junta con espacio")
            expectEq(await synth.speakingNow, "", "orden: al terminar no habla")
        }
    }
}

@MainActor func testCacheHitSkipsFetch() {
    withTempDir { dir in
        runOk("cache") {
            let (synth, fetch, play, _, cache) = makeTTS(dir)
            try cache.store(Data("cached".utf8), for: "Hola.")
            expectEq(await speak(synth, "Hola.", "Hola."), [
                .chunkStarted(text: "Hola.", duration: 0),
                .chunkStarted(text: "Hola.", duration: 0),
                .finished,
            ], "cache: dos chunks")
            expect(fetch.calls.isEmpty, "cache: hit no llama fetch")
            expectEq(await play.texts, ["cached", "cached"], "cache: audio guardado")
        }
    }
}

@MainActor func testLongPhraseNeverCached() {
    withTempDir { dir in
        runOk("larga") {
            let (synth, fetch, play, _, cache) = makeTTS(dir)
            let long = String(repeating: "n", count: 81)
            fetch.payload[long] = Data("net".utf8)
            _ = await speak(synth, long, long)
            expectEq(fetch.calls.count, 2, "larga: las dos veces fetch")
            expectEq(try cache.data(for: long), nil, "larga: no queda en cache")
            expectEq(await play.texts, ["net", "net"], "larga: igual se oye")
        }
    }
}

@MainActor func testFetchErrorUsesFallback() {
    withTempDir { dir in
        runOk("fallback") {
            let (synth, fetch, play, fallback, _) = makeTTS(dir)
            fetch.error = TTSStubError.boom
            expectEq(await speak(synth, "Hola."), [
                .chunkStarted(text: "Hola.", duration: 0),
                .finished,
            ], "fallback: chunk + finished")
            expectEq(fallback.spoken, ["Hola."], "fallback: system speak")
            expect(await play.played.isEmpty, "fallback: no pasa por play")
            expectEq(await synth.spokenSoFar(), "Hola.", "fallback: hablado")
        }
    }
}

@MainActor func testFetchAndFallbackFailEmitsFailed() {
    withTempDir { dir in
        runOk("failed") {
            let (synth, fetch, play, fallback, _) = makeTTS(dir)
            fetch.error = TTSStubError.boom
            fallback.error = TTSStubError.boom
            let got = await speak(synth, "Hola.")
            expectEq(got.last, .failed, "fail: termina en failed")
            expect(!got.contains(.finished), "fail: no finished")
            expect(await play.played.isEmpty, "fail: nada que reproducir")
            expectEq(await synth.spokenSoFar(), nil, "fail: no sonó")
        }
    }
}

@MainActor func testStopDropsPendingKeepsPrefix() {
    withTempDir { dir in
        runOk("stop") {
            let (synth, fetch, play, _, _) = makeTTS(dir, blockAt: 2)
            await synth.begin()
            await synth.enqueue("Uno.")
            await synth.enqueue("Dos.")
            await synth.enqueue("Tres.")
            await synth.finish()
            await play.waitBlocked()
            expectEq(await synth.speakingNow, "Dos.", "stop: habla la segunda")
            expectEq(await synth.spokenSoFar(), "Uno.", "stop: prefix es Uno.")
            await synth.stop()
            expectEq(await synth.speakingNow, "", "stop: speakingNow vacío")
            expectEq(await synth.spokenSoFar(), "Uno.", "stop: conserva prefix")
            expectEq(await play.texts, ["Uno.", "Dos."], "stop: no llega a Tres")
            // 15f-5: while Dos sounds, Tres may already be requested (one
            // ahead) — it is paid for, never heard, and nothing past it is.
            expectEq(Array(fetch.calls.map(\.text).prefix(2)), ["Uno.", "Dos."],
                     "stop: Uno y Dos se piden en orden")
            expect(fetch.calls.count <= 3, "stop: nunca más de una por delante")
            expect(await play.stops > 0, "stop: corta playback")
        }
    }
}

@MainActor func testBeginResetsSpokenSoFar() {
    withTempDir { dir in
        runOk("reset") {
            let (synth, _, _, _, _) = makeTTS(dir)
            let tap = EventTap.start(synth.events)
            await synth.begin()
            await synth.enqueue("Uno.")
            await synth.finish()
            _ = await tap.waitTerminal()
            expectEq(await synth.spokenSoFar(), "Uno.", "reset: primer turno")
            let port: any SpeechSynthesizer = synth
            await port.begin()
            expectEq(await port.spokenSoFar(), nil, "reset: begin limpia spoken")
            expectEq(await port.speakingNow, "", "reset: begin no habla")
            await port.enqueue("Dos.")
            await port.finish()
            expectEq(await tap.waitTerminal(), [
                .chunkStarted(text: "Dos.", duration: 0),
                .finished,
            ], "reset: segundo turno")
            expectEq(await port.spokenSoFar(), "Dos.", "reset: spoken del nuevo")
        }
    }
}

/// Code review 2026-09-23 (medio): two presses warming the same missing
/// phrase used to fire two fetches — `prewarm`'s own Task is fire-and-forget,
/// so nothing stopped a second call from racing the first before the cache
/// had a chance to fill.
// Not `runOk`/`withTempDir`: that pair bridges a SYNC closure into async by
// blocking the main thread on a semaphore — deadlocks the moment the async
// body hops back onto the (blocked) MainActor, which `pumpUntilAsync` does.
@MainActor func testPrewarmDedupsAnInFlightFetch() async {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-tts-dedup-\(UUID().uuidString)", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    } catch {
        expect(false, "dedup: no se pudo crear el temp dir \(error)")
        return
    }
    defer { try? FileManager.default.removeItem(at: dir) }

    let cache = PhraseCache(directory: dir)
    let fetch = GatedFetch()
    let synth = SpeechSynthesis(
        cache: cache, fetcher: fetch, playback: FakePlay(),
        fallback: FakeFallback(), voice: .marin)
    await fetch.block("Uno.")
    await synth.prewarm(["Uno.", "Dos."])
    await fetch.waitUntilBlocked("Uno.")
    // A second press asks for "Uno." again while its fetch is still in
    // flight: it must not start a second round trip. (The gate only holds
    // the FIRST call to "Uno." — a leftover duplicate sails through
    // unblocked, so it shows up as an extra call instead of a hang.)
    await synth.prewarm(["Uno.", "Tres."])
    await settle(0.05)
    await fetch.release()
    await pumpUntilAsync("dedup: las frases nuevas llegan a fetch") {
        let calls = await fetch.calls
        return calls.contains("Dos.") && calls.contains("Tres.")
    }
    let calls = await fetch.calls
    expectEq(calls.filter { $0 == "Uno." }.count, 1,
             "dedup: Uno. se pide una sola vez aunque dos prewarm lo pidan")
    expect(calls.contains("Dos.") && calls.contains("Tres."),
           "dedup: la frase nueva de cada prewarm sí se pide")
}

/// A fetch that blocks only the FIRST call to a given phrase, so a test can
/// hold that one open and observe a second `prewarm` call racing it — a
/// leftover duplicate sails through unblocked instead of deadlocking the
/// test on a second, orphaned continuation. Same continuation-exchange
/// shape as `FakePlay.blockAt`.
actor GatedFetch: TTSFetching {
    private(set) var calls: [String] = []
    private var blockedOnce: Set<String> = []
    private var blockedPhrase: String?
    private var gate: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?

    func block(_ phrase: String) { blockedOnce.insert(phrase) }

    func fetch(_ text: String, voice: VoiceID) async throws -> Data {
        calls.append(text)
        guard blockedOnce.remove(text) != nil else { return Data(text.utf8) }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            gate = c
            blockedPhrase = text
            if let waiter { waiter.resume() }
            waiter = nil
        }
        return Data(text.utf8)
    }

    func waitUntilBlocked(_ phrase: String) async {
        if blockedPhrase == phrase { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            waiter = c
        }
    }

    func release() {
        gate?.resume()
        gate = nil
    }
}

/// Wave 15c-5 TDD row 13: the mouth must not wait for the whole sentence to
/// download before it starts moving air. Gate held before the 3rd of 3
/// chunks so the assertion catches the player with only the first two in
/// hand — proof they were scheduled before the stream even finished.
@MainActor func testStreamedChunksReachPlaybackBeforeTheStreamEnds() async {
    let dir = makeTTSTempDir("stream-order")
    defer { try? FileManager.default.removeItem(at: dir) }
    let fetch = GatedChunkFetch()
    await fetch.script("Hola.", chunks: [Data("A".utf8), Data("B".utf8), Data("C".utf8)], gateBeforeIndex: 2)
    let play = FakePlay()
    let synth = SpeechSynthesis(
        cache: PhraseCache(directory: dir), fetcher: fetch, playback: play,
        fallback: FakeFallback(), voice: .marin)
    await synth.begin()
    await synth.enqueue("Hola.")
    await synth.finish()
    await fetch.waitUntilGated()
    await pumpUntilAsync("streaming: los dos primeros llegan a playback") {
        await play.played.count == 2
    }
    expectEq(await play.played.count, 2,
             "streaming: el player ya tiene los dos primeros antes de que llegue el tercero")
    await fetch.release()
    await pumpUntilAsync("streaming: el tercer chunk llega") {
        await play.played.count == 3
    }
    expectEq(await play.texts, ["A", "B", "C"], "streaming: orden preservado")
}

/// Wave 15c-5 TDD row 14: `stop()` mid-sentence silences right away and the
/// interrupted download must never land in the phrase cache.
@MainActor func testStopDuringAStreamSilencesAndDoesNotCacheThePartial() async {
    let dir = makeTTSTempDir("stream-stop")
    defer { try? FileManager.default.removeItem(at: dir) }
    let cache = PhraseCache(directory: dir)
    let fetch = GatedChunkFetch()
    await fetch.script("Hola.", chunks: [Data("A".utf8), Data("B".utf8), Data("C".utf8)], gateBeforeIndex: 1)
    let play = FakePlay()
    let synth = SpeechSynthesis(
        cache: cache, fetcher: fetch, playback: play, fallback: FakeFallback(), voice: .marin)
    await synth.begin()
    await synth.enqueue("Hola.")
    await synth.finish()
    await fetch.waitUntilGated()
    await pumpUntilAsync("stop en vivo: el primer chunk llega a playback") {
        await play.played.count == 1
    }
    expectEq(await play.played.count, 1, "stop en vivo: solo el primer chunk sonó")
    await synth.stop()
    expect(await play.stops > 0, "stop en vivo: corta playback de inmediato")
    await fetch.release()
    await settle(0.1)
    expectEq(await play.played.count, 1,
              "stop en vivo: lo que llega tras stop no se reproduce")
    do {
        expectEq(try cache.data(for: "Hola."), nil, "stop en vivo: no cachea lo parcial")
    } catch {
        expect(false, "stop en vivo: leer la caché no debía tirar \(error)")
    }
}

/// Wave 15c-5 TDD row 15: once the stream finishes, the full phrase is
/// cached and a later hold — even offline — replays it without a fetch.
@MainActor func testACompletedStreamCachesAndReplaysOffline() async {
    let dir = makeTTSTempDir("stream-cache")
    defer { try? FileManager.default.removeItem(at: dir) }
    let cache = PhraseCache(directory: dir)
    let fetch = GatedChunkFetch()
    await fetch.script("Hola.", chunks: [Data("A".utf8), Data("B".utf8), Data("C".utf8)])
    let play = FakePlay()
    let synth = SpeechSynthesis(
        cache: cache, fetcher: fetch, playback: play, fallback: FakeFallback(), voice: .marin)
    let tap = EventTap.start(synth.events)
    await synth.begin()
    await synth.enqueue("Hola.")
    await synth.finish()
    expectEq(await tap.waitTerminal(), [
        .chunkStarted(text: "Hola.", duration: 0),
        .finished,
    ], "offline: termina bien la primera vez")
    do {
        expectEq(try cache.data(for: "Hola."), Data("ABC".utf8),
                 "offline: cachea el PCM completo, en orden")
    } catch {
        expect(false, "offline: leer la caché no debía tirar \(error)")
    }

    let offlineFetch = FakeFetch()
    offlineFetch.error = TTSStubError.boom
    let replayPlay = FakePlay()
    let replay = SpeechSynthesis(
        cache: cache, fetcher: offlineFetch, playback: replayPlay,
        fallback: FakeFallback(), voice: .marin)
    expectEq(await speak(replay, "Hola."), [
        .chunkStarted(text: "Hola.", duration: 0),
        .finished,
    ], "offline: la repetición también termina bien")
    expect(offlineFetch.calls.isEmpty, "offline: sin red, no hay fetch")
    expectEq(await replayPlay.texts, ["ABC"], "offline: reproduce el PCM cacheado")
}

/// Wave 15c-5: a phrase delivered as separate PCM chunks instead of one
/// blob, with an optional gate before one of them — lets a test observe
/// that earlier chunks already reached playback before a later one arrives,
/// the same continuation-exchange shape as `GatedFetch`/`FakePlay.blockAt`.
actor GatedChunkFetch: TTSFetching {
    private(set) var calls: [String] = []
    private var scripted: [String: [Data]] = [:]
    private var gateBefore: [String: Int] = [:]
    private var gate: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    private var gated = false

    func script(_ phrase: String, chunks: [Data], gateBeforeIndex: Int? = nil) {
        scripted[phrase] = chunks
        if let gateBeforeIndex { gateBefore[phrase] = gateBeforeIndex }
    }

    func fetch(_ text: String, voice: VoiceID) async throws -> Data {
        calls.append(text)
        return (scripted[text] ?? []).reduce(Data(), +)
    }

    nonisolated func stream(_ text: String, voice: VoiceID) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let pump = Task {
                await self.record(text)
                let parts = await self.parts(for: text)
                let holdIndex = await self.gateIndex(for: text)
                for (index, part) in parts.enumerated() {
                    if Task.isCancelled { break }
                    if index == holdIndex { await self.hold() }
                    continuation.yield(part)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in pump.cancel() }
        }
    }

    private func record(_ text: String) { calls.append(text) }
    private func parts(for text: String) -> [Data] { scripted[text] ?? [] }
    private func gateIndex(for text: String) -> Int? { gateBefore[text] }

    private func hold() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            gate = c
            gated = true
            let wake = waiter
            waiter = nil
            wake?.resume()
        }
    }

    func waitUntilGated() async {
        if gated { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in waiter = c }
    }

    func release() {
        gated = false
        gate?.resume()
        gate = nil
    }
}

func makeTTSTempDir(_ label: String) -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-tts-\(label)-\(UUID().uuidString)", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    } catch {
        expect(false, "\(label): no se pudo crear el temp dir \(error)")
    }
    return dir
}

enum TTSStubError: Error { case boom }

// The synthesis actor calls these doubles off the test's thread while the
// test reads them back, so every field goes through one lock (TSan caught
// `calls` racing in testStopDropsPendingKeepsPrefix).
final class FakeFetch: TTSFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [(text: String, voice: VoiceID)] = []
    private var _payload: [String: Data] = [:]
    private var _error: Error?

    var calls: [(text: String, voice: VoiceID)] { lock.withLock { _calls } }
    var payload: [String: Data] {
        get { lock.withLock { _payload } }
        set { lock.withLock { _payload = newValue } }
    }
    var error: Error? {
        get { lock.withLock { _error } }
        set { lock.withLock { _error = newValue } }
    }

    func fetch(_ text: String, voice: VoiceID) async throws -> Data {
        let (error, data) = lock.withLock {
            _calls.append((text, voice))
            return (_error, _payload[text])
        }
        if let error { throw error }
        return data ?? Data(text.utf8)
    }
}

final class FakeFallback: SystemSpeechFallback, @unchecked Sendable {
    private let lock = NSLock()
    private var _spoken: [String] = []
    private var _error: Error?

    var spoken: [String] { lock.withLock { _spoken } }
    var error: Error? {
        get { lock.withLock { _error } }
        set { lock.withLock { _error = newValue } }
    }

    func speak(_ text: String) async throws {
        try lock.withLock {
            if let _error { throw _error }
            _spoken.append(text)
        }
    }
}

actor EventTap {
    private var buffer: [SpeechEvent] = []
    private var waiter: CheckedContinuation<[SpeechEvent], Never>?
    /// 15f-5: the mouth's timing marks are their own contract; the tests
    /// about what is spoken and in what order read the list without them.
    private let keepMarks: Bool

    private init(keepMarks: Bool) { self.keepMarks = keepMarks }

    static func start(_ stream: AsyncStream<SpeechEvent>, keepMarks: Bool = false) -> EventTap {
        let tap = EventTap(keepMarks: keepMarks)
        Task { await tap.pull(stream) }
        return tap
    }

    private func pull(_ stream: AsyncStream<SpeechEvent>) async {
        for await event in stream {
            if case .mark = event, !keepMarks { continue }
            buffer.append(event)
            if event == .finished || event == .failed, let waiter {
                self.waiter = nil
                waiter.resume(returning: take())
            }
        }
    }

    func waitTerminal() async -> [SpeechEvent] {
        await withCheckedContinuation { cont in
            if let last = buffer.last, last == .finished || last == .failed {
                cont.resume(returning: take())
            } else {
                waiter = cont
            }
        }
    }

    private func take() -> [SpeechEvent] {
        let shot = buffer
        buffer.removeAll()
        return shot
    }
}

func makeTTS(
    _ dir: URL, voice: VoiceID = .marin, blockAt: Int = .max
) -> (SpeechSynthesis, FakeFetch, FakePlay, FakeFallback, PhraseCache) {
    let fetch = FakeFetch()
    let play = FakePlay(blockAt: blockAt)
    let fallback = FakeFallback()
    let cache = PhraseCache(directory: dir)
    let synth = SpeechSynthesis(
        cache: cache, fetcher: fetch, playback: play, fallback: fallback, voice: voice)
    return (synth, fetch, play, fallback, cache)
}

func speak(_ synth: SpeechSynthesis, _ sentences: String...) async -> [SpeechEvent] {
    let tap = EventTap.start(synth.events)
    await synth.begin()
    for sentence in sentences { await synth.enqueue(sentence) }
    await synth.finish()
    return await tap.waitTerminal()
}

func exists(_ dir: URL, _ name: String) -> Bool {
    FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path)
}
