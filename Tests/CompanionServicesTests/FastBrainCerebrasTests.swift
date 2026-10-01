import CompanionCore
import CompanionCoreTestSupport
import CompanionServices
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// Wave 15c-7 (spec §11). The hold's first fast brain capped gpt-oss-120b at
// 8k tokens per minute and the hold burned it in two turns: the pinned client
// retried the 429 with backoff — turns of 9 s and 24 s measured live.
// Cerebras serves the same model at 500k/min; the fast brain never waits.
// 15e-3: Cerebras is now the only fast brain.

@Test @MainActor func fastBrainCerebrasTests() {
    testCerebrasDescriptorServesGptOss()
    testCerebrasStaysOutOfTheTypedChatCatalog()
    testCerebrasOutranksOpenAIForTheBrain()
    testTheHoldBrainIsCerebrasThenOpenAIMiniNeverGroq()
    testAFastBrainNeverBacksOffOnA429()
    testASingleAttemptClientStillRetriesNothingOnSuccess()
}

@MainActor func testCerebrasDescriptorServesGptOss() {
    let cerebras = ProviderDescriptor.cerebras
    expectEq(cerebras.id, "cerebras", "cerebras: id")
    expectEq(cerebras.model, "gpt-oss-120b", "cerebras: gpt-oss-120b")
    expectEq(cerebras.baseURL.absoluteString, "https://api.cerebras.ai/v1",
             "cerebras: base openai-compatible")
    expectEq(cerebras.secretKey, .cerebras, "cerebras: CEREBRAS_API_KEY")
    expectEq(cerebras.reasoningEffort, "low", "cerebras: reasoning_effort low")
    expect(cerebras.temperature == nil, "cerebras: sin temperature para gpt-oss")
    expectEq(SecretKey.cerebras.rawValue, "CEREBRAS_API_KEY", "cerebras: nombre de la clave")
}

/// Spec §11: the typed chat does not change in this wave.
@MainActor func testCerebrasStaysOutOfTheTypedChatCatalog() {
    expect(!ProviderDescriptor.catalog.contains { $0.id == "cerebras" },
           "cerebras: no entra al catálogo del chat escrito")
}

@MainActor func testCerebrasOutranksOpenAIForTheBrain() {
    let stack = VoiceStackResolver.resolve(
        secrets: [.openAI: true, .cerebras: true],
        appleSpeech: true,
        localModel: nil)
    expectEq(stack.brain, VoiceRole(id: "gpt-oss-120b", provider: "cerebras"),
             "cerebras+openai: el cerebro es Cerebras")
    expect(stack.hasFastBrain, "cerebras: cuenta como cerebro rápido")
    expectEq(stack.mouth, VoiceRole(id: "gpt-4o-mini-tts", provider: "openai"),
             "cerebras: la boca sigue OpenAI")
}

/// 15e-3 (spec §4 row 6): the fast client asks Cerebras only; when it fails
/// the ladder answers with OpenAI's gpt-4o-mini, and no rung is ever Groq.
@MainActor func testTheHoldBrainIsCerebrasThenOpenAIMiniNeverGroq() {
    expectEq(HoldBrainCatalog.fast, [ProviderDescriptor.cerebras],
             "hold: el catálogo rápido es solo Cerebras")
    let ladder = HoldBrainCatalog.ladder(
        [ProviderDescriptor.cerebras] + ProviderDescriptor.catalog)
    expectEq(ladder.map(\.id), ["openai", "openrouter", "ollama"],
             "hold: la escalera salta Cerebras y no tiene Groq")
    expectEq(ladder.first?.model, "gpt-4o-mini", "hold: la escalera cae a gpt-4o-mini")
    expect(!ladder.contains { $0.id == "groq" || $0.baseURL.host == "api.groq.com" },
           "hold: ningún peldaño es Groq")
    expectEq(ProviderDescriptor.catalog.first { $0.id == "openai" }?.model, "gpt-4o",
             "hold: el chat escrito conserva gpt-4o")
}

/// The live bug: a 429 on the fast provider slept 1 s, 2 s before moving on.
/// With `maxAttempts: 1` the next provider is asked at once and no sleep runs.
@MainActor func testAFastBrainNeverBacksOffOnA429() {
    let transport = ScriptedTransport()
    transport.stub(.cerebras, ScriptedReply(status: 429))
    transport.stub(.openRouter, ScriptedReply(lines: [SSEFixtures.fallback, SSEFixtures.done]))
    let slept = SleepLog()
    let client = ChatProviderClient(
        secrets: TestSecretStore([.cerebras: "csk-test", .openRouter: "or-test"]),
        probe: TestProbe(available: ["cerebras", "openrouter"]),
        transport: transport,
        catalog: [.cerebras, .openRouter],
        sleep: { seconds in slept.record(seconds) },
        maxAttempts: 1)
    let deltas = collectChat(client)
    expectEq(deltas, [.text("Desde el respaldo")], "429: el respaldo contesta el mismo turno")
    expectEq(chatHosts(transport), ["api.cerebras.ai", "openrouter.ai"],
             "429: un solo intento a Cerebras, luego el respaldo")
    expectEq(slept.count, 0, "429: el cerebro rápido nunca espera")
}

@MainActor func testASingleAttemptClientStillRetriesNothingOnSuccess() {
    let transport = ScriptedTransport()
    transport.stub(.cerebras, ScriptedReply(lines: [SSEFixtures.hello, SSEFixtures.done]))
    let client = ChatProviderClient(
        secrets: TestSecretStore([.cerebras: "csk-test"]),
        probe: TestProbe(available: ["cerebras"]),
        transport: transport,
        catalog: [.cerebras],
        maxAttempts: 1)
    expectEq(collectChat(client), [.text("Hola")], "cerebras: contesta")
    expectEq(chatHosts(transport), ["api.cerebras.ai"], "cerebras: una sola petición")
}

final class SleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    func record(_ seconds: TimeInterval) {
        lock.lock()
        _count += 1
        lock.unlock()
    }
}
