import CompanionCore
import Foundation

package protocol SpeechPlayback: Sendable {
    /// A fully-downloaded buffer — the cache-hit path.
    func play(_ data: Data) async throws
    /// Wave 15c-5: schedules PCM chunks as they arrive instead of waiting
    /// for the whole sentence. Returns everything actually scheduled, so
    /// the caller can cache exactly what was heard — a `stop()` mid-stream
    /// leaves this short of the full sentence, which is the signal to skip
    /// caching a partial.
    func play(_ chunks: AsyncThrowingStream<Data, Error>) async throws -> Data
    func stop() async
}

package protocol TTSFetching: Sendable {
    func fetch(_ text: String, voice: VoiceID) async throws -> Data
    /// Wave 15c-5: the same audio as `fetch`, delivered as it arrives over
    /// the wire so playback can start before the sentence has finished
    /// downloading.
    func stream(_ text: String, voice: VoiceID) -> AsyncThrowingStream<Data, Error>
    /// Wave 15b-4: open a connection to the endpoint ahead of the first
    /// phrase. A fetcher with nothing to warm (a test fake) does nothing.
    func warm() async
    /// Wave 15f-5: everything besides the text that changes the audio this
    /// fetcher returns, so the phrase cache never replays another style.
    /// Empty (the default) keeps the plain per-phrase key.
    func cacheVariant(voice: VoiceID) -> String
    /// Wave 15f-7a: whether the audio just streamed for `text` really is the
    /// style `cacheVariant` names. A fetcher that had to serve it from a
    /// fallback voice answers no, so it is heard but never replayed later as
    /// the other voice. Asked once per streamed sentence.
    func mayCache(_ text: String) -> Bool
    /// Security review 2026-09-25 (LOW-3): the fetcher that voices ONE
    /// sentence. A router decides here, once; everything else answers self.
    func resolved() -> any TTSFetching
}

extension TTSFetching {
    package func warm() async {}

    package func cacheVariant(voice: VoiceID) -> String { "" }

    package func mayCache(_ text: String) -> Bool { true }

    package func resolved() -> any TTSFetching { self }

    /// Default: the whole body as a single chunk, via `fetch` — correct for
    /// every fake in the test suite that only implements `fetch`; only
    /// `OpenAITTSClient` needs true streaming, so it is the only conformer
    /// that overrides this.
    package func stream(_ text: String, voice: VoiceID) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let data = try await fetch(text, voice: voice)
                    continuation.yield(data)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

package protocol SystemSpeechFallback: Sendable {
    func speak(_ text: String) async throws
}

package actor SpeechSynthesis: SpeechSynthesizer {
    private let baseCache: PhraseCache
    private let fetcher: any TTSFetching
    private let playback: any SpeechPlayback
    private let fallback: any SystemSpeechFallback
    private let voice: VoiceID

    nonisolated package let events: AsyncStream<SpeechEvent>
    private let continuation: AsyncStream<SpeechEvent>.Continuation

    private var pending: [String] = []
    private var closed = false
    private var stopped = true
    private var failed = false
    private var spokenDone: [String] = []
    private var current = ""
    private var worker: Task<Void, Never>?
    private var signal: CheckedContinuation<Void, Never>?
    /// Code review 2026-09-23 (medio): two presses warming the same missing
    /// phrase used to fire two fetches — `prewarm`'s Task is fire-and-forget,
    /// so nothing stopped a second call from racing the first before the
    /// cache had a chance to fill. Reserved the moment a fetch is queued,
    /// freed when it lands (hit or miss) — the actor's own isolation is the
    /// lock.
    private var prewarming: Set<String> = []
    /// Wave 15f-5: the next sentence's request, opened while the current one
    /// sounds so its TTFB is paid under the audio instead of as a gap. One at
    /// most: a reply cut short must not have paid for three sentences ahead.
    private var ahead: SpeechPrefetch?
    /// A sentence is sounding — the only window in which `ahead` may open.
    private var audible = false
    /// The first sentence of the turn has not reached `enqueue` / `utter`
    /// yet: its instants are the ones the timeline measures.
    private var cutUnreported = false
    private var requestUnmeasured = false

    package init(
        cache: PhraseCache,
        fetcher: any TTSFetching,
        playback: any SpeechPlayback,
        fallback: any SystemSpeechFallback,
        voice: VoiceID
    ) {
        // Scoped per use, not here: a fetcher that routes between mouths
        // decides its style from the Keychain, which is never read at boot.
        self.baseCache = cache
        self.fetcher = fetcher
        self.playback = playback
        self.fallback = fallback
        self.voice = voice
        let pair = AsyncStream.makeStream(of: SpeechEvent.self)
        events = pair.stream
        continuation = pair.continuation
    }

    /// Keyed by the fetcher's style so PCM cached at another voice, speed
    /// or instructions is never replayed as this one.
    private var cache: PhraseCache { cache(for: fetcher.resolved()) }

    private func cache(for mouth: any TTSFetching) -> PhraseCache {
        baseCache.scoped(mouth.cacheVariant(voice: voice))
    }

    package var speakingNow: String { current }

    package func spokenSoFar() -> String? {
        let joined = spokenDone.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    package func begin() async {
        await halt(resetSpoken: true)
        closed = false
        failed = false
        stopped = false
        cutUnreported = true
        requestUnmeasured = true
        pending.removeAll()
        worker = Task { [weak self] in
            await self?.runLoop()
        }
    }

    package func enqueue(_ sentence: String) {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !stopped else { return }
        pending.append(text)
        if cutUnreported {
            cutUnreported = false
            continuation.yield(.mark(.firstCut))
        }
        fillAhead()
        ping()
    }

    package func finish() {
        closed = true
        ping()
    }

    package func stop() async {
        await halt(resetSpoken: false)
    }

    /// Reads the cache only — never fetches. `AckPolicy` calls this to
    /// decide, before speaking, whether the specific reply is already on
    /// disk.
    package func isCached(_ phrase: String) async -> Bool {
        cachedAudio(phrase) != nil
    }

    /// Fetches and stores each phrase that is not already cached, in a Task
    /// of its own: the caller (a hold's own reply, or the press-time fan-out)
    /// must never wait for this, and it must never touch `pending`/`current`
    /// or emit `.chunkStarted` — nothing here is meant to be heard.
    package func prewarm(_ phrases: [String]) async {
        let fresh = phrases.filter { !prewarming.contains($0) }
        guard !fresh.isEmpty else { return }
        for phrase in fresh { prewarming.insert(phrase) }
        Task { [weak self, cache, fetcher, voice] in
            for phrase in fresh {
                await Self.prewarmOne(phrase, cache: cache, fetcher: fetcher, voice: voice)
                await self?.donePrewarming(phrase)
            }
        }
    }

    private func donePrewarming(_ phrase: String) {
        prewarming.remove(phrase)
    }

    package func warmConnection() async {
        await fetcher.warm()
    }

    private static func prewarmOne(
        _ phrase: String, cache: PhraseCache, fetcher: any TTSFetching, voice: VoiceID
    ) async {
        do {
            if try cache.data(for: phrase) != nil { return }
        } catch {
            Log.app("tts: phrase cache read failed")
        }
        do {
            let audio = try await fetcher.fetch(phrase, voice: voice)
            try cache.store(audio, for: phrase)
        } catch {
            Log.app("tts: prewarm fetch failed")
        }
    }

    deinit {
        signal?.resume()
        continuation.finish()
        worker?.cancel()
        ahead?.cancel()
    }

    private func halt(resetSpoken: Bool) async {
        stopped = true
        pending.removeAll()
        current = ""
        if resetSpoken { spokenDone = [] }
        worker?.cancel()
        worker = nil
        ahead?.cancel()
        ahead = nil
        audible = false
        ping()
        await playback.stop()
    }

    private func ping() {
        signal?.resume()
        signal = nil
    }

    private func runLoop() async {
        while !Task.isCancelled && !stopped {
            if !pending.isEmpty {
                let next = pending.removeFirst()
                await utter(next)
                continue
            }
            if closed {
                if !stopped {
                    continuation.yield(
                        failed && spokenDone.isEmpty ? .failed : .finished)
                }
                return
            }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                if stopped || closed || !pending.isEmpty {
                    cont.resume()
                } else {
                    signal = cont
                }
            }
        }
    }

    private func utter(_ text: String) async {
        if Task.isCancelled || stopped { return }
        current = text
        let measured = requestUnmeasured
        requestUnmeasured = false
        if let ready = takeAhead(for: text) {
            await streamFromNetwork(text, ready.chunks, mouth: ready.mouth, requestedAt: nil)
            return
        }
        let mouth = fetcher.resolved()
        if let cached = cachedAudio(text, in: cache(for: mouth)) {
            await playCached(text, cached)
        } else {
            var requestedAt: ContinuousClock.Instant?
            if measured {
                continuation.yield(.mark(.ttsRequest))
                requestedAt = .now
            }
            await streamFromNetwork(
                text, mouth.stream(text, voice: voice), mouth: mouth, requestedAt: requestedAt)
        }
    }

    private func cachedAudio(_ text: String) -> Data? {
        cachedAudio(text, in: cache)
    }

    private func cachedAudio(_ text: String, in cache: PhraseCache) -> Data? {
        do {
            return try cache.data(for: text)
        } catch {
            Log.app("tts: phrase cache read failed")
            return nil
        }
    }

    /// Opens the request for the sentence right after the one sounding.
    /// Only `pending.first`: the one after it waits until this one sounds.
    private func fillAhead() {
        guard audible, !stopped, ahead == nil, let next = pending.first else { return }
        let mouth = fetcher.resolved()
        guard cachedAudio(next, in: cache(for: mouth)) == nil else { return }
        ahead = SpeechPrefetch(
            next, mouth: mouth, upstream: mouth.stream(next, voice: voice))
    }

    private func takeAhead(for text: String) -> SpeechPrefetch? {
        guard let ready = ahead else { return nil }
        ahead = nil
        guard ready.text == text else {
            ready.cancel()
            return nil
        }
        return ready
    }

    /// Every path that makes a sentence heard goes through here, so the
    /// next request opens the moment this one starts sounding.
    private func startAudible(_ text: String) {
        continuation.yield(.chunkStarted(text: text, duration: 0))
        audible = true
        fillAhead()
    }

    /// A cancelled worker belongs to a halted turn; `halt` already reset
    /// the flag and a newer turn may own it now.
    private func endAudible() {
        if !Task.isCancelled { audible = false }
    }

    private func reportFirstByte(since start: ContinuousClock.Instant) {
        continuation.yield(.mark(.firstByte))
        let ms = Int(((ContinuousClock.now - start) / .milliseconds(1)).rounded())
        Log.app("tts: first byte \(ms)ms")
    }

    /// Already on disk: one shot, no network, marks `.chunkStarted` the
    /// instant playback is about to start.
    private func playCached(_ text: String, _ audio: Data) async {
        if Task.isCancelled || stopped { current = ""; return }
        startAudible(text)
        defer { endAudible() }
        do {
            try await playback.play(audio)
            if Task.isCancelled || stopped { current = ""; return }
            spokenDone.append(text)
            current = ""
        } catch is CancellationError {
            current = ""
        } catch {
            failed = true
            current = ""
        }
    }

    /// Wave 15c-5: pulls the first PCM chunk by hand before handing the
    /// rest to `playback` — that is what tells this function whether the
    /// phrase never made a sound at all (network/auth failure: fall back to
    /// the system voice, same as before) or whether it started speaking and
    /// something later went wrong (mark `failed`, no fallback mid-sentence).
    private func streamFromNetwork(
        _ text: String, _ chunks: AsyncThrowingStream<Data, Error>,
        mouth: any TTSFetching, requestedAt: ContinuousClock.Instant?
    ) async {
        var iterator = chunks.makeAsyncIterator()
        let first: Data?
        do {
            first = try await iterator.next()
        } catch is CancellationError {
            current = ""
            return
        } catch {
            await speakViaFallback(text)
            return
        }
        guard let first else {
            // No audio at all — same shape as an empty fetch.
            await speakViaFallback(text)
            return
        }
        if Task.isCancelled || stopped { current = ""; return }
        if let requestedAt { reportFirstByte(since: requestedAt) }
        startAudible(text)
        defer { endAudible() }
        let rest = Self.relay(first: first, rest: iterator)
        do {
            let assembled = try await playback.play(rest)
            if Task.isCancelled || stopped { current = ""; return }
            if mouth.mayCache(text) {
                do {
                    try cache(for: mouth).store(assembled, for: text)
                } catch {
                    Log.app("tts: phrase cache write failed")
                }
            }
            spokenDone.append(text)
            current = ""
        } catch is CancellationError {
            current = ""
        } catch {
            failed = true
            current = ""
        }
    }

    private func speakViaFallback(_ text: String) async {
        if Task.isCancelled || stopped {
            current = ""
            return
        }
        Log.app("tts: fetch failed, system fallback")
        startAudible(text)
        defer { endAudible() }
        do {
            try await fallback.speak(text)
            if Task.isCancelled || stopped {
                current = ""
                return
            }
            spokenDone.append(text)
            current = ""
        } catch is CancellationError {
            current = ""
        } catch {
            failed = true
            current = ""
        }
    }
}
