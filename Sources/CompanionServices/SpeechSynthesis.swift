import CompanionCore
import Foundation

public protocol SpeechPlayback: Sendable {
    func play(_ data: Data) async throws
    func stop() async
}

public protocol TTSFetching: Sendable {
    func fetch(_ text: String, voice: VoiceID) async throws -> Data
}

public protocol SystemSpeechFallback: Sendable {
    func speak(_ text: String) async throws
}

public actor SpeechSynthesis: SpeechSynthesizer {
    private let cache: PhraseCache
    private let fetcher: any TTSFetching
    private let playback: any SpeechPlayback
    private let fallback: any SystemSpeechFallback
    private let voice: VoiceID

    nonisolated public let events: AsyncStream<SpeechEvent>
    private let continuation: AsyncStream<SpeechEvent>.Continuation

    private var pending: [String] = []
    private var closed = false
    private var stopped = true
    private var failed = false
    private var spokenDone: [String] = []
    private var current = ""
    private var worker: Task<Void, Never>?
    private var signal: CheckedContinuation<Void, Never>?

    public init(
        cache: PhraseCache,
        fetcher: any TTSFetching,
        playback: any SpeechPlayback,
        fallback: any SystemSpeechFallback,
        voice: VoiceID
    ) {
        self.cache = cache
        self.fetcher = fetcher
        self.playback = playback
        self.fallback = fallback
        self.voice = voice
        let pair = AsyncStream.makeStream(of: SpeechEvent.self)
        events = pair.stream
        continuation = pair.continuation
    }

    public var speakingNow: String { current }

    public func spokenSoFar() -> String? {
        let joined = spokenDone.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    public func begin() async {
        await halt(resetSpoken: true)
        closed = false
        failed = false
        stopped = false
        pending.removeAll()
        worker = Task { [weak self] in
            await self?.runLoop()
        }
    }

    public func enqueue(_ sentence: String) {
        let text = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !stopped else { return }
        pending.append(text)
        ping()
    }

    public func finish() {
        closed = true
        ping()
    }

    public func stop() async {
        await halt(resetSpoken: false)
    }

    deinit {
        signal?.resume()
        continuation.finish()
        worker?.cancel()
    }

    private func halt(resetSpoken: Bool) async {
        stopped = true
        pending.removeAll()
        current = ""
        if resetSpoken { spokenDone = [] }
        worker?.cancel()
        worker = nil
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

        var audio: Data?
        do {
            audio = try cache.data(for: text)
        } catch {
            Log.app("tts: phrase cache read failed")
            audio = nil
        }

        if audio == nil {
            do {
                let fetched = try await fetcher.fetch(text, voice: voice)
                if Task.isCancelled || stopped {
                    current = ""
                    return
                }
                // Miss on disk must not drop audio we already paid to fetch.
                do {
                    try cache.store(fetched, for: text)
                } catch {
                    Log.app("tts: phrase cache write failed")
                }
                audio = fetched
            } catch is CancellationError {
                current = ""
                return
            } catch {
                await speakViaFallback(text)
                return
            }
        }

        guard let audio else {
            failed = true
            current = ""
            return
        }
        if Task.isCancelled || stopped {
            current = ""
            return
        }
        continuation.yield(.chunkStarted(text: text, duration: 0))
        do {
            try await playback.play(audio)
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

    private func speakViaFallback(_ text: String) async {
        if Task.isCancelled || stopped {
            current = ""
            return
        }
        Log.app("tts: fetch failed, system fallback")
        continuation.yield(.chunkStarted(text: text, duration: 0))
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
