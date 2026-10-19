import CompanionCore
import CompanionCoreTestSupport
import CompanionServices
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// Karen 2026-10-19: the product must not require OpenAI. Cerebras answers the
// typed chat whenever its key exists. gpt-oss is text-only and takes neither
// `strict` nor a temperature.

@Test @MainActor func cerebrasChatTests() {
    testCerebrasIsTheTypedChatDefaultWhenItsKeyExists()
    testCerebrasRequestOmitsStrictAndTemperature()
    testAnImageNeverGoesToGptOss()
    testAnImageWithOnlyGptOssConfiguredAsksForAVisionKey()
}

@MainActor func testCerebrasIsTheTypedChatDefaultWhenItsKeyExists() {
    let transport = ScriptedTransport()
    transport.stub(.cerebras, ScriptedReply(lines: [SSEFixtures.hello, SSEFixtures.done]))
    transport.stub(.openAI, ScriptedReply(lines: [SSEFixtures.hello, SSEFixtures.done]))
    let deltas = collectChat(makeChatClient(
        keys: [.cerebras: "csk-test", .openAI: "sk-test"],
        available: ["cerebras", "openai"],
        transport: transport))
    expectEq(deltas, [.text("Hola")], "cerebras: contesta el chat escrito")
    expectEq(chatHosts(transport), ["api.cerebras.ai"],
             "cerebras: se pide antes que OpenAI")
}

@MainActor func testCerebrasRequestOmitsStrictAndTemperature() {
    let transport = ScriptedTransport()
    transport.stub(.cerebras, ScriptedReply(lines: [SSEFixtures.hello, SSEFixtures.done]))
    // A descriptor with the default temperature, so the gate under test is the
    // model's, not the catalog row's own nil.
    let hot = ProviderDescriptor(
        id: "cerebras", name: "Cerebras",
        baseURL: URL(string: "https://api.cerebras.ai/v1")!,
        model: "gpt-oss-120b", secretKey: .cerebras)
    let spec = ToolSpec(name: "web_search", description: "search", properties: [], required: [])
    _ = collectChat(
        makeChatClient(
            keys: [.cerebras: "csk-test"], available: ["cerebras"],
            transport: transport, catalog: [hot]),
        tools: [spec])
    guard let req = transport.requests.first else {
        expect(false, "cerebras: no hubo request")
        return
    }
    let body = chatBody(req)
    expect(body["temperature"] == nil, "cerebras: gpt-oss no recibe temperature")
    let tools = body["tools"] as? [[String: Any]] ?? []
    expectEq(tools.count, 1, "cerebras: la tool viaja")
    let function = tools.first?["function"] as? [String: Any] ?? [:]
    expect(function["strict"] == nil, "cerebras: sin strict en la tool")
    let parameters = function["parameters"] as? [String: Any] ?? [:]
    expect(parameters["additionalProperties"] == nil,
           "cerebras: el modo estricto de OpenAI no se activa en su esquema")
}

@MainActor func testAnImageNeverGoesToGptOss() {
    let transport = ScriptedTransport()
    transport.stub(.cerebras, ScriptedReply(lines: [SSEFixtures.hello, SSEFixtures.done]))
    transport.stub(.openAI, ScriptedReply(lines: [SSEFixtures.hello, SSEFixtures.done]))
    let img = AttachmentRef(name: "a.png", path: "/tmp/a.png", kind: .image)
    // The image sits in an earlier turn: it still rides the history window.
    let history = [
        Turn(role: .user, content: "mira", attachments: [img]),
        Turn(role: .assistant, content: "listo"),
        Turn(role: .user, content: "y ahora?"),
    ]
    _ = collectChat(
        makeChatClient(
            keys: [.cerebras: "csk-test", .openAI: "sk-test"],
            available: ["cerebras", "openai"],
            transport: transport),
        history: history)
    expectEq(chatHosts(transport), ["api.openai.com"],
             "imagen: gpt-oss no la recibe; el turno pasa a OpenAI")
}

@MainActor func testAnImageWithOnlyGptOssConfiguredAsksForAVisionKey() {
    let transport = ScriptedTransport()
    transport.stub(.cerebras, ScriptedReply(lines: [SSEFixtures.hello, SSEFixtures.done]))
    let img = AttachmentRef(name: "a.png", path: "/tmp/a.png", kind: .image)
    expectChatError(
        makeChatClient(
            keys: [.cerebras: "csk-test"], available: ["cerebras"], transport: transport),
        .imageUnsupported, "imagen: sin proveedor con visión",
        history: [Turn(role: .user, content: "mira", attachments: [img])])
    expectEq(transport.requests.count, 0, "imagen: ninguna petición a gpt-oss")
}
