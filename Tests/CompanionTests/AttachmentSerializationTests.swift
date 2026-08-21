import CompanionCore
import CompanionServices
import Foundation
import Testing

@Test @MainActor func attachmentSerializationTests() {
    testImageTurnSendsParts()
    testTextOnlyTurnStaysString()
    testBinaryStaysNumberedString()
    testWithoutResolverStaysNumberedText()
    testRealtimeImageItemShape()
}

@MainActor func testImageTurnSendsParts() {
    let transport = ScriptedTransport()
    transport.stub(.openAI, ScriptedReply(lines: [SSEFixtures.hello, SSEFixtures.done]))
    let img = AttachmentRef(name: "a.png", path: "/tmp/a.png", kind: .image)
    let doc = AttachmentRef(name: "n.txt", path: "/tmp/n.txt", kind: .file)
    _ = collectChat(
        makeSerializingClient(transport: transport, resolve: fakeResolve),
        history: [Turn(role: .user, content: "mira", attachments: [img, doc])])
    let content = lastContent(transport)
    let parts = content as? [[String: Any]] ?? []
    expect(parts.count >= 2, "multimodal: content es array de partes")
    expectEq(parts.first?["type"] as? String, "text", "multimodal: el texto va primero")
    expectEq(parts.first?["text"] as? String, Turn.numbered("mira", [img, doc]),
             "multimodal: Turn.numbered sigue en la parte de texto")
    let image = parts.first { $0["type"] as? String == "image_url" }
    let url = (image?["image_url"] as? [String: Any])?["url"] as? String
    expectEq(url, "data:image/png;base64,abc", "multimodal: image_url viaja")
    let inline = parts.contains {
        ($0["text"] as? String)?.contains("Contenido de n.txt") == true
    }
    expect(inline, "multimodal: el texto legible se inlinea")
}

@MainActor func testTextOnlyTurnStaysString() {
    let transport = ScriptedTransport()
    transport.stub(.openAI, ScriptedReply(lines: [SSEFixtures.hello, SSEFixtures.done]))
    let doc = AttachmentRef(name: "n.txt", path: "/tmp/n.txt", kind: .file)
    _ = collectChat(
        makeSerializingClient(transport: transport, resolve: fakeResolve),
        history: [Turn(role: .user, content: "lee", attachments: [doc])])
    let content = lastContent(transport)
    expect(content is String, "sin imagen: content sigue siendo String")
    let text = content as? String ?? ""
    expect(text.contains(Turn.numbered("lee", [doc])), "sin imagen: etiquetas")
    expect(text.contains("Contenido de n.txt"), "sin imagen: el txt viaja inline")
}

@MainActor func testBinaryStaysNumberedString() {
    let transport = ScriptedTransport()
    transport.stub(.openAI, ScriptedReply(lines: [SSEFixtures.hello, SSEFixtures.done]))
    let pdf = AttachmentRef(name: "a.pdf", path: "/tmp/a.pdf", kind: .file)
    _ = collectChat(
        makeSerializingClient(transport: transport, resolve: fakeResolve),
        history: [Turn(role: .user, content: "adjunto", attachments: [pdf])])
    let content = lastContent(transport)
    expectEq(content as? String, Turn.numbered("adjunto", [pdf]),
             "binario: solo las etiquetas, sin parts")
}

@MainActor func testWithoutResolverStaysNumberedText() {
    let transport = ScriptedTransport()
    transport.stub(.openAI, ScriptedReply(lines: [SSEFixtures.hello, SSEFixtures.done]))
    let img = AttachmentRef(name: "a.png", path: "/tmp/a.png", kind: .image)
    _ = collectChat(
        makeChatClient(transport: transport),
        history: [Turn(role: .user, content: "mira", attachments: [img])])
    let content = lastContent(transport)
    expectEq(content as? String, Turn.numbered("mira", [img]),
             "sin resolver: no inventa image_url")
}

@MainActor func testRealtimeImageItemShape() {
    let raw = RealtimeCodec.imageItem(
        dataURL: "data:image/png;base64,abc", caption: "mira esto")
    let obj = json(raw)
    expectEq(obj["type"] as? String, "conversation.item.create",
             "imageItem: entra como item, no como seed")
    let item = obj["item"] as? [String: Any] ?? [:]
    expectEq(item["role"] as? String, "user", "imageItem: rol user")
    let parts = item["content"] as? [[String: Any]] ?? []
    expectEq(parts.count, 2, "imageItem: caption + imagen")
    expectEq(parts[0]["type"] as? String, "input_text", "imageItem: caption es texto")
    expectEq(parts[0]["text"] as? String, "mira esto", "imageItem: caption")
    expectEq(parts[1]["type"] as? String, "input_image", "imageItem: input_image")
    expectEq(parts[1]["image_url"] as? String, "data:image/png;base64,abc",
             "imageItem: data URL cruda, no envuelta")
}

private func fakeResolve(_ ref: AttachmentRef) -> AttachmentPayload? {
    switch AttachmentPolicy.delivery(for: ref) {
    case .imageDataURL: return .imageDataURL("data:image/png;base64,abc")
    case .inlineText: return .text("hola archivo")
    case .pathOnly: return .path(ref.path)
    }
}

private func makeSerializingClient(
    transport: ScriptedTransport,
    resolve: @escaping @Sendable (AttachmentRef) -> AttachmentPayload?
) -> ChatProviderClient {
    ChatProviderClient(
        secrets: TestSecretStore([.openAI: "sk-test", .groq: "gsk-test"]),
        probe: TestProbe(available: ["openai", "groq"]),
        transport: transport,
        ownerFirstName: "Karen",
        resolveAttachment: resolve)
}

private func lastContent(_ transport: ScriptedTransport) -> Any? {
    guard let req = transport.requests.first else {
        expect(false, "serializacion: no hubo request")
        return nil
    }
    let messages = (chatBody(req)["messages"] as? [[String: Any]]) ?? []
    return messages.last?["content"]
}

private func json(_ s: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: s.data(using: .utf8)!)) as? [String: Any] ?? [:]
}
