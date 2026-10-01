import CompanionCore
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func sseCodecTests() {
    testTalkDelta()
    testToolCallStreaming()
    testInterleavedToolCallsAssembleByIndex()
    testInventedIdIsStableWithinTheRound()
    testStrictEncoding()
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
    expectEq(b.calls.count, 1, "tool: una call")
    expectEq(b.calls.first?.name, "delegate", "tool: nombre completo")
    expectEq(b.calls.first?.id, "c1", "tool: el id del proveedor sobrevive")
    let h = SSECodec.handoff(name: b.calls[0].name, arguments: b.calls[0].arguments)
    expectEq(h?.goal ?? "", "listar el escritorio",
             "tool: goal armado desde fragmentos")
    expectEq(h?.context ?? "", "workdir ~",
             "tool: context armado desde fragmentos")

    expect(SSECodec.toolDeltas(fromSSE: "event: ping").isEmpty, "toolDeltas: línea ajena")
    expect(SSECodec.toolDeltas(fromSSE: "data: [DONE]").isEmpty, "toolDeltas: DONE no es fragmento")
    expect(SSECodec.toolDeltas(fromSSE: #"data: {"choices":[{"delta":{"tool_calls":[]}}]}"#).isEmpty,
           "toolDeltas: tool_calls vacío")
    expect(SSECodec.toolDeltas(fromSSE: #"data: {"choices":[{"delta":{}}]}"#).isEmpty,
           "toolDeltas: delta sin tool_calls")
    let nameOnly = SSECodec.toolDeltas(
        fromSSE: #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"delegate"}}]}}]}"#)
    expectEq(nameOnly.first?.name, "delegate", "toolDeltas: nombre solo")
    expect(nameOnly.first?.arguments == nil, "toolDeltas: arguments ausente queda nil")
    let argsOnly = SSECodec.toolDeltas(
        fromSSE: #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{"}}]}}]}"#)
    expect(argsOnly.first?.name == nil, "toolDeltas: name ausente queda nil")
    expectEq(argsOnly.first?.arguments, "{", "toolDeltas: arguments solo")
    // OpenAI: `index` es el único campo required; sin él el fragmento no
    // se puede coser y se descarta.
    expect(SSECodec.toolDeltas(
        fromSSE: #"data: {"choices":[{"delta":{"tool_calls":[{"function":{"name":"x"}}]}}]}"#).isEmpty,
           "toolDeltas: sin index no hay fragmento")

    var emptyName = ToolCallBuilder()
    emptyName.feed(fromSSE: #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"","arguments":""}}]}}]}"#)
    expect(!emptyName.started, "tool: name y arguments vacíos no arrancan")
}

/// El defecto de 10c-A: dos calls intercaladas (0,1,0,1) se fundían en
/// `"read_filewrite_file"`. Se cosen por `index`, no por posición.
@MainActor func testInterleavedToolCallsAssembleByIndex() {
    let one = SSECodec.toolDeltas(fromSSE: #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"a","function":{"name":"read_file","arguments":""}},{"index":1,"id":"b","function":{"name":"write_file","arguments":""}}]}}]}"#)
    expectEq(one.map(\.index), [0, 1], "índice: un chunk con dos fragmentos")
    var b = ToolCallBuilder()
    for line in [
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"a","function":{"name":"read_file","arguments":""}}]}}]}"#,
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":1,"id":"b","function":{"name":"write_file","arguments":""}}]}}]}"#,
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"path\":"}}]}}]}"#,
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":1,"function":{"arguments":"{\"path\":\"b\","}}]}}]}"#,
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"a\"}"}}]}}]}"#,
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":1,"function":{"arguments":"\"content\":\"x\"}"}}]}}]}"#,
    ] { b.feed(fromSSE: line) }
    expectEq(b.calls.map(\.name), ["read_file", "write_file"], "índice: dos calls, en orden")
    expectEq(b.calls.map(\.id), ["a", "b"], "índice: cada una con su id")
    expectEq(b.calls.map(\.arguments), [#"{"path":"a"}"#, #"{"path":"b","content":"x"}"#],
             "índice: los argumentos de cada una, enteros")
}

/// Sin `id` del proveedor (Ollama y algunos compatibles) se inventa uno y
/// es estable dentro de la ronda.
@MainActor func testInventedIdIsStableWithinTheRound() {
    var b = ToolCallBuilder()
    b.feed(fromSSE: #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"read_file","arguments":"{"}}]}}]}"#)
    let first = b.calls.first?.id ?? ""
    b.feed(fromSSE: #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"}"}}]}}]}"#)
    expect(!first.isEmpty, "id: se inventó uno")
    expectEq(b.calls.first?.id, first, "id: el mismo tras el siguiente fragmento")
    var other = ToolCallBuilder()
    other.feed(fromSSE: #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"name":"read_file","arguments":"{}"}}]}}]}"#)
    expect(other.calls.first?.id != first, "id: otra ronda, otro id")
}

/// `strict: true` (OpenAI): `additionalProperties: false`, todo `required`,
/// y lo opcional pasa a nullable. Solo cuando se pide; el resto igual.
@MainActor func testStrictEncoding() {
    let spec = NativeTool.findPlaces.spec
    let strict = json(spec.encodeChat(strict: true))
    let fn = strict["function"] as? [String: Any] ?? [:]
    expectEq(fn["strict"] as? Bool, true, "strict: function.strict")
    let params = fn["parameters"] as? [String: Any] ?? [:]
    expectEq(params["additionalProperties"] as? Bool, false, "strict: additionalProperties false")
    expectEq(Set((params["required"] as? [String]) ?? []), ["query", "near"], "strict: todo required")
    let props = params["properties"] as? [String: Any] ?? [:]
    expectEq((props["near"] as? [String: Any])?["type"] as? [String], ["string", "null"],
             "strict: lo opcional es nullable")
    expectEq((props["query"] as? [String: Any])?["type"] as? String, "string",
             "strict: lo requerido no cambia")
    let loose = json(spec.encodeChat())
    let lfn = loose["function"] as? [String: Any] ?? [:]
    expect(lfn["strict"] == nil, "sin strict: no viaja el campo")
    expectEq(((lfn["parameters"] as? [String: Any])?["required"] as? [String]) ?? [], ["query"],
             "sin strict: required como antes")
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
    expectEq(ToolSpec.delegate().name, "delegate", "spec: delegate se llama delegate")
    expectEq(ToolSpec.resolveApproval().name, "resolve_approval",
             "spec: approval se llama resolve_approval")
    expect(ToolSpec.delegate().description.contains("specialist"),
           "spec: la fuente inglesa nombra al especialista")
    expect(ToolSpec.delegate(.es).description.contains("especialista"),
           "spec: la traducción conserva el wording original")
    expect(ToolSpec.delegate().description.contains("internet"),
           "spec: delegate menciona internet")
    expect(ToolSpec.resolveApproval().description.contains("permission"),
           "spec: descripción de approval en la fuente")

    let chat = json(ToolSpec.delegate().encodeChat())
    expectEq(chat["type"] as? String ?? "", "function", "chat: type function")
    expect(chat["name"] == nil, "chat: name vive dentro de function")
    let fn = chat["function"] as? [String: Any] ?? [:]
    expectEq(fn["name"] as? String ?? "", "delegate", "chat: function.name")
    expect((fn["description"] as? String ?? "").contains("files"),
           "chat: description viaja anidada")
    let params = fn["parameters"] as? [String: Any] ?? [:]
    expectEq(params["type"] as? String ?? "", "object", "chat: parameters.object")
    expectEq((params["required"] as? [String]) ?? [], ["goal"],
             "chat: required = goal")
    let props = params["properties"] as? [String: Any] ?? [:]
    let goal = props["goal"] as? [String: Any] ?? [:]
    expectEq(goal["type"] as? String ?? "", "string", "chat: goal es string")
    expectEq(goal["description"] as? String ?? "", "what is needed, one line",
             "chat: wording de goal")
    let ctx = props["context"] as? [String: Any] ?? [:]
    expectEq(ctx["description"] as? String ?? "",
             "what the specialist should know",
             "chat: wording de context")

    let approvalChat = json(ToolSpec.resolveApproval().encodeChat())
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
