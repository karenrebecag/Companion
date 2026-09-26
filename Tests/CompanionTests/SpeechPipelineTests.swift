import CompanionCore
import CompanionServices
import Foundation
import Testing

// Wave 15f-5 (spec §4 row 6): la boca en tubería. Mientras suena la frase N,
// la petición de la N+1 ya está en vuelo; nunca más de una por delante, y
// `stop()` cancela también la que se adelantó.

/// Row 6: the request for the 2nd sentence leaves before the 1st has
/// finished sounding, and the 3rd is not requested while the 1st still
/// plays — one request ahead, never two.
@Test @MainActor func testTheNextSentenceIsRequestedWhileTheCurrentOnePlays() async {
    let dir = makeTTSTempDir("pipeline-order")
    defer { try? FileManager.default.removeItem(at: dir) }
    let log = PipelineLog()
    let fetch = ScriptedStreamFetch(log: log)
    let play = GatedPlayback(log: log)
    let synth = SpeechSynthesis(
        cache: PhraseCache(directory: dir), fetcher: fetch, playback: play,
        fallback: FakeFallback(), voice: .marin)
    let tap = EventTap.start(synth.events)
    await synth.begin()
    await synth.enqueue("Uno.")
    await synth.enqueue("Dos.")
    await synth.enqueue("Tres.")
    await synth.finish()

    await pumpUntilAsync("tubería: Uno suena") { await play.playing == "Uno." }
    await pumpUntil("tubería: Dos se pide mientras Uno suena") {
        log.entries.contains("stream Dos.")
    }
    await settle(0.1)
    expect(!log.entries.contains("play end Uno."),
           "tubería: Uno sigue sonando cuando sale la petición de Dos")
    expect(!log.entries.contains("stream Tres."),
           "tubería: nunca dos peticiones por delante de la que suena")

    await play.release()
    await pumpUntilAsync("tubería: Dos suena") { await play.playing == "Dos." }
    await pumpUntil("tubería: Tres se pide mientras Dos suena") {
        log.entries.contains("stream Tres.")
    }
    let entries = log.entries
    if let tres = entries.firstIndex(of: "stream Tres."),
       let unoEnd = entries.firstIndex(of: "play end Uno.") {
        expect(tres > unoEnd, "tubería: Tres sale solo cuando Uno ya terminó")
    } else {
        expect(false, "tubería: faltan marcas en \(entries)")
    }
    await play.release()
    await pumpUntilAsync("tubería: Tres suena") { await play.playing == "Tres." }
    await play.release()
    let events = await tap.waitTerminal()
    expectEq(events.last, .finished, "tubería: termina bien")
    expectEq(log.entries.filter { $0.hasPrefix("stream ") },
             ["stream Uno.", "stream Dos.", "stream Tres."],
             "tubería: una petición por frase, en orden")
    expectEq(await play.heard, ["Uno.", "Dos.", "Tres."], "tubería: se oye en orden")
}

/// Row 6: `stop()` while the 2nd sentence is prefetched cancels that
/// request too — no stream left running, no audio after the stop.
@Test @MainActor func testStopDuringAPrefetchCancelsTheRequestAhead() async {
    let dir = makeTTSTempDir("pipeline-stop")
    defer { try? FileManager.default.removeItem(at: dir) }
    let log = PipelineLog()
    let fetch = ScriptedStreamFetch(log: log, hanging: ["Dos."])
    let play = GatedPlayback(log: log)
    let synth = SpeechSynthesis(
        cache: PhraseCache(directory: dir), fetcher: fetch, playback: play,
        fallback: FakeFallback(), voice: .marin)
    await synth.begin()
    await synth.enqueue("Uno.")
    await synth.enqueue("Dos.")
    await synth.finish()
    await pumpUntilAsync("stop: Uno suena") { await play.playing == "Uno." }
    await pumpUntil("stop: Dos ya está pedida") { log.entries.contains("stream Dos.") }

    await synth.stop()
    await pumpUntil("stop: la petición adelantada se cancela") {
        log.entries.contains("cancelled Dos.")
    }
    await play.release()
    await settle(0.1)
    expectEq(await play.heard, ["Uno."], "stop: nada suena después del stop")
    expect(!log.entries.contains("play start Dos."), "stop: Dos nunca llega al player")
}

// MARK: - Fakes

/// One ordered record of what the mouth asked for and what it played, written
/// from the fetcher (nonisolated) and the player (its own actor) alike.
final class PipelineLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    func add(_ entry: String) { lock.withLock { stored.append(entry) } }
    var entries: [String] { lock.withLock { stored } }
}

/// Each sentence answers with its own text as a single PCM chunk. A
/// `hanging` sentence sends its first chunk and never finishes, so only a
/// cancellation can end it.
final class ScriptedStreamFetch: TTSFetching, @unchecked Sendable {
    private let log: PipelineLog
    private let hanging: Set<String>

    init(log: PipelineLog, hanging: Set<String> = []) {
        self.log = log
        self.hanging = hanging
    }

    func fetch(_ text: String, voice: VoiceID) async throws -> Data { Data(text.utf8) }

    func stream(_ text: String, voice: VoiceID) -> AsyncThrowingStream<Data, Error> {
        log.add("stream \(text)")
        let log = log
        let hang = hanging.contains(text)
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { reason in
                if case .cancelled = reason { log.add("cancelled \(text)") }
            }
            continuation.yield(Data(text.utf8))
            if !hang { continuation.finish() }
        }
    }
}

/// Plays a sentence, then holds it "sounding" until the test releases it —
/// the window in which the next request must already be in flight.
actor GatedPlayback: SpeechPlayback {
    private let log: PipelineLog
    private(set) var heard: [String] = []
    private(set) var playing: String?
    private var gate: CheckedContinuation<Void, Never>?
    private var released = 0
    private var ended = 0

    init(log: PipelineLog) { self.log = log }

    func play(_ data: Data) async throws {
        _ = try await sound(data)
    }

    func play(_ chunks: AsyncThrowingStream<Data, Error>) async throws -> Data {
        var assembled = Data()
        for try await chunk in chunks { assembled.append(chunk) }
        return try await sound(assembled)
    }

    private func sound(_ audio: Data) async throws -> Data {
        let name = String(decoding: audio, as: UTF8.self)
        heard.append(name)
        playing = name
        log.add("play start \(name)")
        if released <= ended {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in gate = c }
        }
        ended += 1
        playing = nil
        log.add("play end \(name)")
        return audio
    }

    /// Ends the sentence sounding now (or the next one, if none is yet).
    func release() {
        released += 1
        gate?.resume()
        gate = nil
    }

    func stop() async {
        gate?.resume()
        gate = nil
    }
}
