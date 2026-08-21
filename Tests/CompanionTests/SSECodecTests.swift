import CompanionCore
import Foundation
import Testing

@Test @MainActor func sseCodecTests() {
    testTalkDelta()
    testToolCallStreaming()
    testSSEHandoffDelegates()
    testToolSpecChatEncode()
}

@MainActor func testTalkDelta() {
    expect(SSECodec.delta(fromSSE: "data: [DONE]") == nil, "DONE no es delta")
    expect(SSECodec.delta(fromSSE: "event: ping") == nil, "línea ajena")
    let line = "data: {\"choices\":[{\"delta\":{\"content\":\"Hola\"}}]}"
    expectEq(SSECodec.delta(fromSSE: line), "Hola", "extrae content")

    expect(SSECodec.delta(fromSSE: "") == nil, "delta: vacío no es evento")
    expect(SSECodec.delta(fromSSE: "data:") == nil, "delta: payload vacío")
    expect(SSECodec.delta(fromSSE: "Data: {\"choices\":[{\"delta\":{\"content\":\"Hola\"}}]}") == nil,
           "delta: el prefijo data: es case-sensitive")
    expectEq(SSECodec.delta(fromSSE: "  data: {\"choices\":[{\"delta\":{\"content\":\"Hola\"}}]}  "),
             "Hola", "delta: recorta espacios alrededor")
    expectEq(SSECodec.delta(fromSSE: "data:{\"choices\":[{\"delta\":{\"content\":\"Hola\"}}]}"),
             "Hola", "delta: espacio tras data: es opcional")
    expect(SSECodec.delta(fromSSE: #"data: {"choices":[{"delta":{"content":""}}]}"#) == nil,
           "delta: content vacío no es delta")
    expect(SSECodec.delta(fromSSE: #"data: {"choices":[]}"#) == nil,
           "delta: sin choices")
    expect(SSECodec.delta(fromSSE: #"data: {"choices":[{"delta":{}}]}"#) == nil,
           "delta: sin content")
    expect(SSECodec.delta(fromSSE: #"data: {"choices":[{"delta":{"content":1}}]}"#) == nil,
           "delta: content no-string se ignora")
    expect(SSECodec.delta(fromSSE: "data: {no json") == nil,
           "delta: JSON roto no truena")
    expect(SSECodec.delta(fromSSE: "data: []") == nil,
           "delta: un array no es un chunk")
    expectEq(SSECodec.delta(fromSSE: #"data: {"choices":[{"delta":{"content":"ñoño 👋 \"x\""}}]}"#),
             "ñoño 👋 \"x\"", "delta: unicode y comillas viajan intactos")
}

@MainActor func testToolCallStreaming() {
    var b = ToolCallBuilder()
    expect(!b.started, "tool: arranca vacío")
    expectEq(b, ToolCallBuilder(), "tool: Equatable en vacío")
    b.feed(fromSSE: #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"delegate","arguments":""}}]}}]}"#)
    b.feed(fromSSE: #"data: {"choices":[{"delta":{"content":"ok"}}]}"#)
    b.feed(fromSSE: #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"goal\": \"lis"}}]}}]}"#)
    b.feed(fromSSE: #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"tar el escritorio\", \"context\": \"workdir ~\"}"}}]}}]}"#)
    b.feed(fromSSE: "data: [DONE]")
    expect(b.started, "tool: acumuló el call")
    expectEq(b.name, "delegate", "tool: nombre completo")
    let h = SSECodec.handoff(name: b.name, arguments: b.arguments)
    expectEq(h?.goal ?? "", "listar el escritorio",
             "tool: goal armado desde fragmentos")
    expectEq(h?.context ?? "", "workdir ~",
             "tool: context armado desde fragmentos")

    expect(SSECodec.toolDelta(fromSSE: "event: ping") == nil,
           "toolDelta: línea ajena")
    expect(SSECodec.toolDelta(fromSSE: "data: [DONE]") == nil,
           "toolDelta: DONE no es fragmento")
    expect(SSECodec.toolDelta(fromSSE: #"data: {"choices":[{"delta":{"tool_calls":[]}}]}"#) == nil,
           "toolDelta: tool_calls vacío")
    expect(SSECodec.toolDelta(fromSSE: #"data: {"choices":[{"delta":{}}]}"#) == nil,
           "toolDelta: delta sin tool_calls")
    let nameOnly = SSECodec.toolDelta(
        fromSSE: #"data: {"choices":[{"delta":{"tool_calls":[{"function":{"name":"delegate"}}]}}]}"#)
    expectEq(nameOnly?.name ?? "", "delegate", "toolDelta: nombre solo")
    expect(nameOnly?.arguments == nil, "toolDelta: arguments ausente queda nil")
    let argsOnly = SSECodec.toolDelta(
        fromSSE: #"data: {"choices":[{"delta":{"tool_calls":[{"function":{"arguments":"{"}}]}}]}"#)
    expect(argsOnly?.name == nil, "toolDelta: name ausente queda nil")
    expectEq(argsOnly?.arguments ?? "", "{", "toolDelta: arguments solo")

    var emptyName = ToolCallBuilder()
    emptyName.feed(fromSSE: #"data: {"choices":[{"delta":{"tool_calls":[{"function":{"name":"","arguments":""}}]}}]}"#)
    expect(!emptyName.started, "tool: name y arguments vacíos no arrancan")
}

@MainActor func testSSEHandoffDelegates() {
    let solo = SSECodec.handoff(name: "delegate",
                                arguments: #"{"goal": "leer notas"}"#)
    expectEq(solo?.goal ?? "", "leer notas", "handoff: alias con goal alcanza")
    expectEq(solo?.context ?? "", "", "handoff: context opcional queda vacío")
    expect(SSECodec.handoff(name: "delegate", arguments: #"{"goal": ""}"#) == nil,
           "handoff: goal vacío no delega")
    expect(SSECodec.handoff(name: "otra", arguments: #"{"goal": "x"}"#) == nil,
           "handoff: herramienta desconocida no delega")
    expect(SSECodec.handoff(name: "delegate", arguments: #"{"goal": "x"#) == nil,
           "handoff: JSON truncado no truena ni delega")
}

@MainActor func testToolSpecChatEncode() {
    expectEq(ToolSpec.delegate.name, "delegate", "spec: delegate se llama delegate")
    expectEq(ToolSpec.resolveApproval.name, "resolve_approval",
             "spec: approval se llama resolve_approval")
    expect(ToolSpec.delegate.description.contains("especialista"),
           "spec: descripción de delegate del original")
    expect(ToolSpec.delegate.description.contains("internet"),
           "spec: delegate menciona internet")
    expect(ToolSpec.resolveApproval.description.contains("permiso"),
           "spec: descripción de approval del original")

    let chat = json(ToolSpec.delegate.encodeChat())
    expectEq(chat["type"] as? String ?? "", "function", "chat: type function")
    expect(chat["name"] == nil, "chat: name vive dentro de function")
    let fn = chat["function"] as? [String: Any] ?? [:]
    expectEq(fn["name"] as? String ?? "", "delegate", "chat: function.name")
    expect((fn["description"] as? String ?? "").contains("archivos"),
           "chat: description viaja anidada")
    let params = fn["parameters"] as? [String: Any] ?? [:]
    expectEq(params["type"] as? String ?? "", "object", "chat: parameters.object")
    expectEq((params["required"] as? [String]) ?? [], ["goal"],
             "chat: required = goal")
    let props = params["properties"] as? [String: Any] ?? [:]
    let goal = props["goal"] as? [String: Any] ?? [:]
    expectEq(goal["type"] as? String ?? "", "string", "chat: goal es string")
    expectEq(goal["description"] as? String ?? "", "qué se necesita, una línea",
             "chat: wording de goal")
    let ctx = props["context"] as? [String: Any] ?? [:]
    expectEq(ctx["description"] as? String ?? "", "lo que el especialista debe saber",
             "chat: wording de context")

    let approvalChat = json(ToolSpec.resolveApproval.encodeChat())
    let afn = approvalChat["function"] as? [String: Any] ?? [:]
    expectEq(afn["name"] as? String ?? "", "resolve_approval",
             "chat: approval anidado")
    let aprops = ((afn["parameters"] as? [String: Any])?["properties"]) as? [String: Any] ?? [:]
    expectEq((aprops["approved"] as? [String: Any])?["type"] as? String ?? "",
             "boolean", "chat: approved es boolean")

    let custom = ToolSpec(
        name: "ping", description: "eco",
        properties: [ToolProperty(name: "n", type: "integer", description: "veces")],
        required: [])
    let encoded = json(custom.encodeChat())
    let cfn = encoded["function"] as? [String: Any] ?? [:]
    expectEq(cfn["name"] as? String ?? "", "ping", "chat: tool ad-hoc")
    expectEq(((cfn["parameters"] as? [String: Any])?["required"] as? [String]) ?? ["x"],
             [], "chat: required vacío viaja")
}

private func json(_ s: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: s.data(using: .utf8)!)) as? [String: Any] ?? [:]
}
