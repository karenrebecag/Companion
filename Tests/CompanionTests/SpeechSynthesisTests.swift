import CompanionCore
import CompanionServices
import Foundation
import Testing

@Test @MainActor func speechSynthesisTests() {
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
            expectEq(fetch.calls.map(\.text), ["Uno.", "Dos."],
                     "stop: no fetch de Tres")
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

enum TTSStubError: Error { case boom }

final class FakeFetch: TTSFetching, @unchecked Sendable {
    var calls: [(text: String, voice: VoiceID)] = []
    var payload: [String: Data] = [:]
    var error: Error?
    func fetch(_ text: String, voice: VoiceID) async throws -> Data {
        calls.append((text, voice))
        if let error { throw error }
        return payload[text] ?? Data(text.utf8)
    }
}

actor FakePlay: SpeechPlayback {
    private(set) var played: [Data] = []
    private(set) var stops = 0
    private let blockAt: Int
    private var hold: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    init(blockAt: Int = .max) { self.blockAt = blockAt }

    var texts: [String] {
        played.compactMap { String(data: $0, encoding: .utf8) }
    }

    func play(_ data: Data) async throws {
        played.append(data)
        guard played.count >= blockAt else { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            hold = c
            let wake = started
            started = nil
            wake?.resume()
        }
        try Task.checkCancellation()
    }

    func stop() async {
        stops += 1
        hold?.resume()
        hold = nil
        started?.resume()
        started = nil
    }

    func waitBlocked() async {
        if hold != nil { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            if hold != nil { c.resume() } else { started = c }
        }
    }
}

final class FakeFallback: SystemSpeechFallback, @unchecked Sendable {
    var spoken: [String] = []
    var error: Error?
    func speak(_ text: String) async throws {
        if let error { throw error }
        spoken.append(text)
    }
}

actor EventTap {
    private var buffer: [SpeechEvent] = []
    private var waiter: CheckedContinuation<[SpeechEvent], Never>?

    static func start(_ stream: AsyncStream<SpeechEvent>) -> EventTap {
        let tap = EventTap()
        Task { await tap.pull(stream) }
        return tap
    }

    private func pull(_ stream: AsyncStream<SpeechEvent>) async {
        for await event in stream {
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
