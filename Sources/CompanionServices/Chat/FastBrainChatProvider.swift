import CompanionCore
import Foundation

/// Wave 15c-3: the hold's brain, pinned to the fast provider (Cerebras since
/// 15e-3, `HoldBrainCatalog.fast`) while it has a key — the
/// role existed since 14a but nothing ever read it (wave-15c §1). A failure
/// BEFORE the first delta falls back to `ladder` (the hold's own ladder) in
/// the SAME turn, so a hold never goes mute for one provider; once a delta
/// has reached the caller, nothing here retries — a second provider
/// speaking the same turn would double the audio (TDD rows 9-10).
package final class FastBrainChatProvider: ChatProvider, Sendable {
    private let fast: any ChatProvider
    private let ladder: any ChatProvider

    package init(fast: any ChatProvider, ladder: any ChatProvider) {
        self.fast = fast
        self.ladder = ladder
    }

    package func stream(_ history: [Turn], tools: [ToolSpec])
        -> AsyncThrowingStream<ChatDelta, Error>
    {
        AsyncThrowingStream { continuation in
            let task = Task {
                var sawDelta = false
                do {
                    for try await delta in fast.stream(history, tools: tools) {
                        sawDelta = true
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch {
                    guard !sawDelta else {
                        continuation.finish(throwing: error)
                        return
                    }
                    await Self.relay(
                        ladder.stream(history, tools: tools), into: continuation)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    package func verify(_ key: String, provider: ProviderDescriptor) async throws {
        try await ladder.verify(key, provider: provider)
    }

    private static func relay(
        _ stream: AsyncThrowingStream<ChatDelta, Error>,
        into continuation: AsyncThrowingStream<ChatDelta, Error>.Continuation
    ) async {
        do {
            for try await delta in stream { continuation.yield(delta) }
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }
}
