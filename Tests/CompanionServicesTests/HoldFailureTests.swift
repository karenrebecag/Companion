import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Code review 2026-09-24 (alto). A hold turn that failed after an earlier
// reply "recovered" into `.listening` with a hot mic and no key held: the
// hold branch of `speechFinished` never cleared `inConversation`, so the
// next failure took the hands-free recover path. A hold fails to rest with
// its IO stopped; and the hands-free recover retries once, not forever.

@Test @MainActor func holdFailureTests() async {
    testTheRecoverLoopRetriesOnceThenFails()
    testARecoverThatArmedCanRecoverAgain()
}

private func step(_ m: inout TurnMachine, _ event: TurnEvent) -> [TurnEffect] {
    m.handle(event, at: 0)
}

/// One whole hold: press, arm, release with speech, reply, spoken.
private func completedHold(_ m: inout TurnMachine) {
    _ = step(&m, .holdPressed(preferRealtime: false))
    _ = step(&m, .classicListenArmed)
    _ = step(&m, .holdReleased(hasSpeech: true))
    _ = step(&m, .firstSentence)
    _ = step(&m, .replyCompleted)
    _ = step(&m, .speechFinished)
}

@MainActor func testTheRecoverLoopRetriesOnceThenFails() {
    var m = TurnMachine(snapshot: TurnSnapshot(
        state: .listening, pipeline: .classic, inConversation: true))
    let first = step(&m, .voiceStartFailed(.micUnavailable))
    expectEq(m.snapshot.state, .listening, "bucle: el primer fallo reintenta")
    expect(first.contains(.requestClassicListen), "bucle: pide escuchar otra vez")
    let second = step(&m, .voiceStartFailed(.micUnavailable))
    expectEq(m.snapshot.state, .error, "bucle: el segundo fallo seguido se rinde")
    expect(!second.contains(.requestClassicListen), "bucle: sin otro reintento")
}

@MainActor func testARecoverThatArmedCanRecoverAgain() {
    var m = TurnMachine(snapshot: TurnSnapshot(
        state: .listening, pipeline: .classic, inConversation: true))
    _ = step(&m, .voiceStartFailed(.micUnavailable))
    _ = step(&m, .classicListenArmed)
    _ = step(&m, .voiceStartFailed(.micUnavailable))
    expectEq(m.snapshot.state, .listening, "bucle: un reintento que sí armó cuenta de cero")
}

/// The chat fails only on its second call.
private final class SecondCallFailsChat: ChatProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    var callCount: Int { lock.withLock { calls } }

    func stream(_ history: [Turn], tools: [ToolSpec]) -> AsyncThrowingStream<ChatDelta, Error> {
        let call = lock.withLock { () -> Int in
            calls += 1
            return calls
        }
        return AsyncThrowingStream { continuation in
            if call == 1 {
                continuation.yield(.text("Listo."))
                continuation.finish()
            } else {
                continuation.finish(throwing: ChatError.timeout)
            }
        }
    }

    func verify(_ key: String, provider: ProviderDescriptor) async throws {}
}
