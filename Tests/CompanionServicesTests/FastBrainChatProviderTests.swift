import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// Wave 15c-3 (TDD rows 9-10). The hold's brain, pinned to Cerebras while a fast
// provider is wired: a failure BEFORE the first delta falls back to today's
// ladder in the SAME turn; once a delta has reached the caller, nothing here
// retries — a second provider speaking would double the audio.

@Test @MainActor func fastBrainChatProviderTests() async {
    await testFastFailureBeforeAnyDeltaFallsBackToTheLadder()
    await testFastFailureAfterADeltaDoesNotRetry()
    await testFastSuccessNeverTouchesTheLadder()
}

/// Row 9: the fast brain throws before any delta — the ladder answers, same turn.
@MainActor func testFastFailureBeforeAnyDeltaFallsBackToTheLadder() async {
    let fast = ScriptedFastChat()
    fast.failWith = ChatError.noProvider
    let ladder = ScriptedFastChat()
    ladder.deltas = [.text("Hecho.")]
    let provider = FastBrainChatProvider(fast: fast, ladder: ladder)
    let deltas = try? await collect(provider)
    expectEq(deltas, [.text("Hecho.")], "fastBrain: la escalera contesta el mismo turno")
    expectEq(ladder.callCount, 1, "fastBrain: la escalera se llamó una vez")
}

/// Row 10: the fast brain yields a delta, THEN throws — no retry, the error reaches
/// the caller and the ladder is never touched (no duplicated audio).
@MainActor func testFastFailureAfterADeltaDoesNotRetry() async {
    let fast = ScriptedFastChat()
    fast.deltas = [.text("Hola")]
    fast.failWith = URLError(.networkConnectionLost)
    let ladder = ScriptedFastChat()
    ladder.deltas = [.text("NUNCA")]
    let provider = FastBrainChatProvider(fast: fast, ladder: ladder)
    var seen: [ChatDelta] = []
    var thrown: Error?
    do {
        for try await delta in provider.stream(
            [Turn(role: .user, content: "hola")], tools: []) {
            seen.append(delta)
        }
    } catch {
        thrown = error
    }
    expectEq(seen, [.text("Hola")], "fastBrain: el delta ya emitido queda")
    expect(thrown != nil, "fastBrain: el error llega al llamador, no se traga")
    expectEq(ladder.callCount, 0, "fastBrain: la escalera nunca se toca tras un delta")
}

@MainActor func testFastSuccessNeverTouchesTheLadder() async {
    let fast = ScriptedFastChat()
    fast.deltas = [.text("Abriendo Safari")]
    let ladder = ScriptedFastChat()
    ladder.deltas = [.text("NUNCA")]
    let provider = FastBrainChatProvider(fast: fast, ladder: ladder)
    let deltas = try? await collect(provider)
    expectEq(deltas, [.text("Abriendo Safari")], "fastBrain: el cerebro rápido responde directo")
    expectEq(ladder.callCount, 0, "fastBrain: sin fallo, la escalera nunca corre")
}

@MainActor private func collect(_ provider: FastBrainChatProvider) async throws -> [ChatDelta] {
    var out: [ChatDelta] = []
    for try await delta in provider.stream(
        [Turn(role: .user, content: "hola")], tools: []) {
        out.append(delta)
    }
    return out
}

private final class ScriptedFastChat: ChatProvider, @unchecked Sendable {
    var deltas: [ChatDelta] = []
    var failWith: Error?
    private(set) var callCount = 0

    func stream(_ history: [Turn], tools: [ToolSpec]) -> AsyncThrowingStream<ChatDelta, Error> {
        callCount += 1
        let deltas = self.deltas
        let failWith = self.failWith
        return AsyncThrowingStream { continuation in
            for delta in deltas { continuation.yield(delta) }
            if let failWith {
                continuation.finish(throwing: failWith)
            } else {
                continuation.finish()
            }
        }
    }

    func verify(_ key: String, provider: ProviderDescriptor) async throws {}
}
