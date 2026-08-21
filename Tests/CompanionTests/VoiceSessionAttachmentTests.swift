import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

@Test @MainActor func voiceSessionAttachmentTests() async {
    await testPushSendsOneImageItem()
    await testPushWithoutSessionIsNoOp()
    await testPushNonImageIsNoOp()
    await testHangUpDuringEncodeDoesNotSend()
}

@MainActor func testPushSendsOneImageItem() async {
    VoiceAttachmentCodec.reset()
    VoiceAttachmentCodec.resolve = { ref in
        .imageDataURL("data:image/png;base64,QQ==")
    }
    defer { VoiceAttachmentCodec.reset() }
    let h = makeVoiceHarness()
    await h.session.start()
    await pumpUntil("push: listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .realtime
    }
    let before = h.transport.sent.count
    await h.session.push(attachment: AttachmentRef(
        name: "foto.png", path: "/tmp/foto.png", kind: .image))
    let added = Array(h.transport.sent.dropFirst(before))
    let items = added.filter { jsonType($0) == "conversation.item.create" }
    expectEq(items.count, 1, "push: un solo imageItem")
    let obj = jsonDict(items[0])
    let parts = ((obj["item"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
    expectEq(parts[0]["text"] as? String,
             VoiceAttachmentCopy.caption(name: "foto.png"),
             "push: caption con el nombre")
    expectEq(parts[1]["image_url"] as? String, "data:image/png;base64,QQ==",
             "push: viaja el base64")
    expectEq(obj["type"] as? String, "conversation.item.create",
             "push: no dispara respuesta, espera pregunta")
}

@MainActor func testPushWithoutSessionIsNoOp() async {
    VoiceAttachmentCodec.resolve = { _ in
        .imageDataURL("data:image/png;base64,QQ==")
    }
    defer { VoiceAttachmentCodec.reset() }
    let h = makeVoiceHarness()
    await h.session.push(attachment: AttachmentRef(
        name: "foto.png", path: "/tmp/foto.png", kind: .image))
    expect(!h.transport.sent.contains { jsonType($0) == "conversation.item.create" },
           "push: sin sesión no manda")
}

@MainActor func testPushNonImageIsNoOp() async {
    VoiceAttachmentCodec.resolve = { _ in
        .text("hola")
    }
    defer { VoiceAttachmentCodec.reset() }
    let h = makeVoiceHarness()
    await h.session.start()
    await pumpUntil("push-file: listening") { h.watch.latest.state == .listening }
    let before = h.transport.sent.count
    await h.session.push(attachment: AttachmentRef(
        name: "nota.md", path: "/tmp/nota.md", kind: .file))
    expectEq(h.transport.sent.count, before, "push: no-imagen no manda")
}

@MainActor func testHangUpDuringEncodeDoesNotSend() async {
    let gate = AsyncStream.makeStream(of: Bool.self)
    VoiceAttachmentCodec.resolve = { _ in
        for await _ in gate.stream { break }
        return .imageDataURL("data:image/png;base64,QQ==")
    }
    defer { VoiceAttachmentCodec.reset() }
    let h = makeVoiceHarness()
    await h.session.start()
    await pumpUntil("push-cancel: listening") { h.watch.latest.state == .listening }
    let before = h.transport.sent.count
    let push = Task { await h.session.push(attachment: AttachmentRef(
        name: "foto.png", path: "/tmp/foto.png", kind: .image)) }
    await h.session.hangUp()
    gate.continuation.yield(true)
    gate.continuation.finish()
    await push.value
    let added = Array(h.transport.sent.dropFirst(before))
    expect(!added.contains { jsonType($0) == "conversation.item.create" },
           "push: colgar a media codificación no manda")
}

private func jsonType(_ json: String) -> String? {
    jsonDict(json)["type"] as? String
}

private func jsonDict(_ json: String) -> [String: Any] {
    guard let data = json.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return obj
}
