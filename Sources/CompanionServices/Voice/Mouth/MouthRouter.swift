import CompanionCore
import Foundation

/// Wave 15f-7a: picks the hold's mouth per request, so saving or deleting
/// the ElevenLabs key in Settings takes effect on the next sentence and
/// nothing reads the Keychain at boot. Without ElevenLabs the mouth is the
/// system voice: the router answers with a mouth that fails before any audio,
/// which `SpeechSynthesis` already speaks through AVSpeech.
package struct MouthRouter: TTSFetching, Sendable {
    private let elevenLabs: any TTSFetching
    private let secrets: any SecretStore
    private let voiceID: @Sendable () -> String
    private let breaker: ElevenLabsBreaker

    package init(
        elevenLabs: any TTSFetching,
        secrets: any SecretStore, voiceID: @escaping @Sendable () -> String,
        cooldown: Duration = .seconds(60),
        now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
    ) {
        self.elevenLabs = elevenLabs
        self.secrets = secrets
        self.voiceID = voiceID
        breaker = ElevenLabsBreaker(cooldown: cooldown, now: now)
    }

    /// Security review 2026-09-25 (LOW-3): the one Keychain read of a
    /// sentence. `SpeechSynthesis` asks once and uses the returned mouth for
    /// the lookup, the stream and the store, so the variant the audio is
    /// cached under is always the mouth that voiced it. Code review
    /// 2026-09-25 (MEDIUM-A): the returned mouth is new per sentence and
    /// remembers on its own whether it fell back, so that answer travels
    /// with the stream instead of living in a table keyed by text.
    package func resolved() -> any TTSFetching {
        choice().mouth
    }

    private func choice() -> (mouth: any TTSFetching, service: String) {
        guard let key = elevenLabsKey(), breaker.allows(key: key) else {
            return (SystemVoiceMouth(), "avspeech")
        }
        return (ElevenLabsFirst(primary: elevenLabs, breaker: breaker, key: key), "elevenlabs")
    }

    package func cacheVariant(voice: VoiceID) -> String {
        resolved().cacheVariant(voice: voice)
    }

    package func fetch(_ text: String, voice: VoiceID) async throws -> Data {
        let (mouth, service) = choice()
        Log.outbound("tts: \(service)")
        return try await mouth.fetch(text, voice: voice)
    }

    package func stream(_ text: String, voice: VoiceID) -> AsyncThrowingStream<Data, Error> {
        let (mouth, service) = choice()
        Log.outbound("tts: \(service)")
        return mouth.stream(text, voice: voice)
    }

    /// Streamed through the router itself, the mouth that voiced the text
    /// is gone by the time this is asked: never claim a variant for it.
    package func mayCache(_ text: String) -> Bool { false }

    package func warm() async {
        await resolved().warm()
    }

    /// The key when ElevenLabs is the chosen mouth, nil otherwise.
    private func elevenLabsKey() -> String? {
        let key: String?
        do {
            key = try secrets.read(.elevenLabs)
            breaker.keychainRead(ok: true)
        } catch {
            breaker.keychainRead(ok: false)
            return nil
        }
        let trimmed = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard ElevenLabsMouth.isChosen(hasKey: !trimmed.isEmpty, voiceID: voiceID()) else {
            return nil
        }
        return trimmed
    }
}

/// The mouth when ElevenLabs is not chosen or is paused. It never makes a
/// sound: the error before the first byte is what sends the sentence to the
/// system voice.
private struct SystemVoiceMouth: TTSFetching {
    func fetch(_ text: String, voice: VoiceID) async throws -> Data {
        throw MouthError.systemVoice
    }

    func stream(_ text: String, voice: VoiceID) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: MouthError.systemVoice)
        }
    }
}

/// Not a network failure: the sentence is meant for the system voice.
package enum MouthError: Error, Sendable, Equatable {
    case systemVoice
}

/// The ElevenLabs decision for ONE sentence. A failure before the first byte
/// goes to the system voice, never to another cloud voice.
private final class ElevenLabsFirst: TTSFetching, @unchecked Sendable {
    let primary: any TTSFetching
    let breaker: ElevenLabsBreaker
    let key: String

    init(primary: any TTSFetching, breaker: ElevenLabsBreaker, key: String) {
        self.primary = primary
        self.breaker = breaker
        self.key = key
    }

    func cacheVariant(voice: VoiceID) -> String { primary.cacheVariant(voice: voice) }

    /// Only `prewarm` fetches, and a failed warm-up is just skipped.
    func fetch(_ text: String, voice: VoiceID) async throws -> Data {
        try await primary.fetch(text, voice: voice)
    }

    func stream(_ text: String, voice: VoiceID) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.relay(text, voice: voice, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func warm() async { await primary.warm() }

    /// ElevenLabs only. A failure before its first byte pauses it and reaches
    /// `SpeechSynthesis`, which speaks the sentence with the system voice.
    /// Once audio has started, a later error is not retried: switching voices
    /// mid-sentence would be worse than the cut.
    private func relay(
        _ text: String, voice: VoiceID,
        into continuation: AsyncThrowingStream<Data, Error>.Continuation
    ) async throws {
        var iterator = primary.stream(text, voice: voice).makeAsyncIterator()
        var status = 0
        var failure: Error?
        let first: Data?
        do {
            first = try await iterator.next()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if case ChatError.httpStatus(let code) = error { status = code }
            failure = error
            first = nil
        }
        if let first {
            continuation.yield(first)
            while let chunk = try await iterator.next() { continuation.yield(chunk) }
            return
        }
        try Task.checkCancellation()
        Log.app("tts: elevenlabs failed status=\(status), system voice")
        breaker.trip(status: status, key: key)
        // The ElevenLabs error itself, so the log and the caller see what failed.
        throw failure ?? ChatError.empty
    }
}

/// Code review 2026-09-25 (MEDIUM-B): ElevenLabs failing before its first
/// byte makes every sentence pay a dead request before the system voice. One failure
/// pauses it for `cooldown`; a 401 means the key itself is bad, so it stays
/// paused until a different key is saved (or the app restarts).
private final class ElevenLabsBreaker: @unchecked Sendable {
    private static let unauthorized = 401

    private let cooldown: Duration
    private let now: @Sendable () -> ContinuousClock.Instant
    private let lock = NSLock()
    private var pausedUntil: ContinuousClock.Instant?
    /// A digest, not the key: nothing here needs the secret itself.
    private var rejectedKey: Int?
    private var keychainFailureLogged = false

    init(cooldown: Duration, now: @escaping @Sendable () -> ContinuousClock.Instant) {
        self.cooldown = cooldown
        self.now = now
    }

    func allows(key: String) -> Bool {
        lock.withLock {
            if let rejected = rejectedKey {
                guard rejected != key.hashValue else { return false }
                rejectedKey = nil
            }
            if let until = pausedUntil {
                guard now() >= until else { return false }
                pausedUntil = nil
            }
            return true
        }
    }

    func trip(status: Int, key: String) {
        let line: String? = lock.withLock {
            if status == Self.unauthorized {
                let fresh = rejectedKey != key.hashValue
                rejectedKey = key.hashValue
                return fresh ? "tts: elevenlabs paused until key changes status=\(status)" : nil
            }
            let fresh = pausedUntil.map { now() >= $0 } ?? true
            pausedUntil = now() + cooldown
            return fresh ? "tts: elevenlabs paused \(cooldown.components.seconds)s status=\(status)" : nil
        }
        if let line { Log.app(line) }
    }

    /// One line per run of failures: a locked Keychain would otherwise log
    /// on every sentence.
    func keychainRead(ok: Bool) {
        let log: Bool = lock.withLock {
            if ok {
                keychainFailureLogged = false
                return false
            }
            defer { keychainFailureLogged = true }
            return !keychainFailureLogged
        }
        if log { Log.app("tts: keychain read failed") }
    }
}
