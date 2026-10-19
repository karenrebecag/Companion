import CompanionCore
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

private func spec(_ name: String, app: Bool = false) -> ToolSpec {
    ToolSpec(name: name, description: name, properties: [], required: [], isConnectedApp: app)
}

private func toolNames(_ request: URLRequest) -> [String] {
    let tools = chatBody(request)["tools"] as? [[String: Any]] ?? []
    return tools.compactMap { ($0["function"] as? [String: Any])?["name"] as? String }
}

// 2026-10-16: 139 tools reached OpenAI (cap 128) and the turn died on a 400.
@Test @MainActor func overTheCapTheCoreSurvivesAndAppsGiveWay() {
    let core = (0..<39).map { spec("core\($0)") }
    let apps = (0..<100).map { spec("app\($0)", app: true) }
    let transport = ScriptedTransport()
    transport.stub(.cerebras, ScriptedReply(lines: [SSEFixtures.hello, SSEFixtures.done]))
    // Apps listed first on purpose: the cut must not depend on position.
    _ = collectChat(makeChatClient(transport: transport), tools: apps + core)
    let sent = transport.requests.first.map(toolNames) ?? []
    expectEq(sent.count, ProviderDescriptor.cerebras.maxTools, "tools: se manda el tope del proveedor")
    expect(core.allSatisfy { sent.contains($0.name) }, "tools: el nucleo entero sobrevive")
    expect(sent.contains("app0") && !sent.contains("app99"), "tools: las apps se cortan por la cola")
}

@Test func underTheCapNothingChanges() {
    let tools = [spec("a"), spec("b", app: true), spec("c")]
    expectEq(ToolBudget.fit(tools, cap: 128), tools, "tools: bajo el tope no se toca ni el orden")
}

// OpenRouter's default ceiling (16k) was refused on a low balance.
@Test @MainActor func openRouterAsksForABoundedReplyAndRetriesWithWhatItCanAfford() {
    let transport = ScriptedTransport()
    let body = #"{"error":{"message":"This request requires more credits, or fewer max_tokens. "#
        + #"You requested up to 4096 tokens, but can only afford 1500."}}"#
    transport.enqueue(ScriptedReply(status: 402, lines: [body]))
    transport.enqueue(ScriptedReply(lines: [SSEFixtures.hello, SSEFixtures.done]))
    let client = makeChatClient(
        keys: [.openRouter: "or-test"], available: ["openrouter"], transport: transport)
    let deltas = collectChat(client)
    expectEq(deltas, [.text("Hola")], "402: el reintento contesta")
    let sent = transport.requests.map { chatBody($0)["max_tokens"] as? Int }
    expectEq(sent, [4_096, 1_500], "402: primero el tope de chat, luego lo que alcanza")
}
