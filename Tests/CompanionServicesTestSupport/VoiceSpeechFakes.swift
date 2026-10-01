import CompanionCore
import CompanionServices
import Foundation

// Mouth and playback fakes shared by the speech tests of both targets.

/// A scripted mouth: names itself in the audio and in its cache variant.
package final class ScriptedMouth: TTSFetching, @unchecked Sendable {
    private let lock = NSLock()
    private let name: String
    private var stored: [String] = []
    private var storedFailure: Error?
    package var calls: [String] { lock.withLock { stored } }
    package var failure: Error? {
        get { lock.withLock { storedFailure } }
        set { lock.withLock { storedFailure = newValue } }
    }

    package init(_ name: String, failure: Error? = nil) {
        self.name = name
        self.storedFailure = failure
    }

    package func fetch(_ text: String, voice: VoiceID) async throws -> Data {
        lock.withLock { stored.append(text) }
        if let failure { throw failure }
        return Data("\(name):\(text)".utf8)
    }

    package func cacheVariant(voice: VoiceID) -> String { name }
}

package actor FakePlay: SpeechPlayback {
    package private(set) var played: [Data] = []
    package private(set) var stops = 0
    private let blockAt: Int
    private var hold: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    /// Wave 15c-5: the task actually running `for try await chunk in
    /// chunks` — `stop()` cancels this one directly (the pattern
    /// `ChatSSEAttempt` already uses) instead of hoping cancellation
    /// travels on its own through a stream built somewhere else.
    private var consumer: Task<Data, Error>?

    package init(blockAt: Int = .max) { self.blockAt = blockAt }

    package var texts: [String] {
        played.compactMap { String(data: $0, encoding: .utf8) }
    }

    package func play(_ data: Data) async throws {
        try await record(data)
    }

    package func play(_ chunks: AsyncThrowingStream<Data, Error>) async throws -> Data {
        let task = Task { () throws -> Data in
            var assembled = Data()
            for try await chunk in chunks {
                assembled.append(chunk)
                try await self.record(chunk)
            }
            return assembled
        }
        consumer = task
        defer { consumer = nil }
        return try await task.value
    }

    private func record(_ data: Data) async throws {
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

    package func stop() async {
        stops += 1
        consumer?.cancel()
        hold?.resume()
        hold = nil
        started?.resume()
        started = nil
    }

    package func waitBlocked() async {
        if hold != nil { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            if hold != nil { c.resume() } else { started = c }
        }
    }
}

/// English when the sentence has one of the listed words, else Spanish.
package struct FakeRecognizer: LanguageRecognizing {
    package var englishWords: Set<String> = ["we", "need", "the", "is", "hello", "opened"]
    package var confidence = 0.9

    package init(
        englishWords: Set<String> = ["we", "need", "the", "is", "hello", "opened"],
        confidence: Double = 0.9
    ) {
        self.englishWords = englishWords
        self.confidence = confidence
    }

    package func dominant(_ text: String) -> DetectedLanguage? {
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        let english = words.contains { englishWords.contains($0) }
        return DetectedLanguage(code: english ? "en" : "es", confidence: confidence)
    }
}

