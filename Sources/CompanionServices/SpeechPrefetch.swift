import Foundation

/// Wave 15f-5: one sentence's TTS request, opened ahead of its turn to
/// sound. The pump drains the fetcher's stream into a buffer of its own, so
/// the first chunk is already in hand when the sentence before it ends —
/// and cancelling the pump is an explicit way to close that request, instead
/// of trusting a dropped stream to cancel itself.
struct SpeechPrefetch: Sendable {
    let text: String
    /// The mouth decided for this sentence (security review 2026-09-25,
    /// LOW-3): its variant keys the cache when the sentence is stored.
    let mouth: any TTSFetching
    let chunks: AsyncThrowingStream<Data, Error>
    private let pump: Task<Void, Never>

    init(_ text: String, mouth: any TTSFetching, upstream: AsyncThrowingStream<Data, Error>) {
        let (chunks, continuation) = AsyncThrowingStream<Data, Error>.makeStream()
        let pump = Task {
            do {
                for try await chunk in upstream { continuation.yield(chunk) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in pump.cancel() }
        self.text = text
        self.mouth = mouth
        self.chunks = chunks
        self.pump = pump
    }

    func cancel() {
        pump.cancel()
    }
}

extension SpeechSynthesis {
    /// Splices the chunk already pulled off `rest`'s iterator back onto the
    /// front, so `playback` still sees a single, in-order stream — cancelling
    /// the returned stream's consumer cancels the pump that feeds it, the
    /// same `onTermination` shape as `ChatTransport.lines(for:)`.
    static func relay(
        first: Data, rest: AsyncThrowingStream<Data, Error>.Iterator
    ) -> AsyncThrowingStream<Data, Error> {
        let box = IteratorBox(rest)
        return AsyncThrowingStream { continuation in
            continuation.yield(first)
            let pump = Task {
                do {
                    while let chunk = try await box.next() {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in pump.cancel() }
        }
    }
}

/// `AsyncThrowingStream.Iterator` is not `Sendable`; `relay`'s pump task is
/// its only owner from the moment it is boxed, so `@unchecked` is safe —
/// the same single-owner shape as `StreamGraph` in `OpenAITTS.swift`.
private final class IteratorBox: @unchecked Sendable {
    private var iterator: AsyncThrowingStream<Data, Error>.Iterator
    init(_ iterator: AsyncThrowingStream<Data, Error>.Iterator) {
        self.iterator = iterator
    }
    func next() async throws -> Data? {
        try await iterator.next()
    }
}
