import CompanionCore
import Foundation
import Testing

@Test @MainActor func agentStreamCodecTests() {
    testClaudeStreamTurn()
    testClaudeStreamParse()
    testControlRequestParse()
    testControlResponse()
    testToolUseStep()
    testThinkingStep()
}

@MainActor func testClaudeStreamTurn() {
    guard let line = AgentStreamCodec.userTurn("lista el escritorio") else {
        return expect(false, "turno: debía armarse")
    }
    expect(line.hasSuffix("\n"), "turno: NDJSON termina en salto de línea")
    let obj = decodeObject(line)
    expectEq(obj["type"] as? String ?? "", "user", "turno: type user")
    let msg = obj["message"] as? [String: Any] ?? [:]
    expectEq(msg["role"] as? String ?? "", "user", "turno: role user")
    let content = msg["content"] as? [[String: Any]] ?? []
    expectEq(content.first?["text"] as? String ?? "", "lista el escritorio",
             "turno: el texto viaja intacto")

    guard let quoted = AgentStreamCodec.userTurn(#"dijo "hola" y ñoño"#) else {
        return expect(false, "turno: unicode y comillas debían armarse")
    }
    let qContent = ((decodeObject(quoted)["message"] as? [String: Any])?["content"]
                    as? [[String: Any]]) ?? []
    expectEq(qContent.first?["text"] as? String ?? "", #"dijo "hola" y ñoño"#,
             "turno: comillas y unicode no se corrompen")

    guard let empty = AgentStreamCodec.userTurn("") else {
        return expect(false, "turno: texto vacío aún es un turno válido")
    }
    let eContent = ((decodeObject(empty)["message"] as? [String: Any])?["content"]
                    as? [[String: Any]]) ?? []
    expectEq(eContent.first?["text"] as? String ?? "missing", "",
             "turno: texto vacío viaja como string vacío")
}

@MainActor func testClaudeStreamParse() {
    expect(AgentStreamCodec.parse("no es json") == AgentStreamEvent.ignored,
           "parse: basura se ignora")
    expect(AgentStreamCodec.parse("") == AgentStreamEvent.ignored,
           "parse: línea vacía se ignora")
    expect(AgentStreamCodec.parse(#"{"type":"system","subtype":"hook_started"}"#)
           == AgentStreamEvent.ignored,
           "parse: los hooks del usuario son ruido")
    expect(AgentStreamCodec.parse(#"{"type":"assistant","message":{}}"#)
           == AgentStreamEvent.ignored,
           "parse: los parciales no cierran el turno")
    expect(AgentStreamCodec.parse(
        #"{"type":"system","subtype":"init","session_id":"abc-123"}"#)
           == AgentStreamEvent.initialized(sessionId: "abc-123"),
           "parse: init trae el session_id durable")
    expect(AgentStreamCodec.parse(
        #"{"type":"result","result":"Listo.","is_error":false}"#)
           == AgentStreamEvent.result(text: "Listo.", isError: false),
           "parse: result cierra el turno con el texto final")
    expect(AgentStreamCodec.parse(#"{"type":"result"}"#)
           == AgentStreamEvent.result(text: "", isError: true),
           "parse: result sin campos se trata como error, no como éxito")

    expect(AgentStreamCodec.parse(
        #"{"type":"system","subtype":"init","session_id":""}"#)
           == AgentStreamEvent.ignored,
           "parse: session_id vacío no inicializa")
    expect(AgentStreamCodec.parse(#"{"type":"system","subtype":"init"}"#)
           == AgentStreamEvent.ignored,
           "parse: init sin session_id se ignora")
    expect(AgentStreamCodec.parse(#"{"type":"foo"}"#) == AgentStreamEvent.ignored,
           "parse: type desconocido se ignora")
    expect(AgentStreamCodec.parse("[]") == AgentStreamEvent.ignored,
           "parse: un array no es un evento")
    expect(AgentStreamCodec.parse(
        #"{"type":"result","result":"boom","is_error":true}"#)
           == AgentStreamEvent.result(text: "boom", isError: true),
           "parse: result de error conserva el texto")
    expect(AgentStreamCodec.parse(
        #"{"type":"result","result":"Listo.","is_error":0}"#)
           == AgentStreamEvent.result(text: "Listo.", isError: true),
           "parse: is_error numérico no se lee como éxito")
}

@MainActor func testControlRequestParse() {
    let line = #"{"type":"control_request","request_id":"r-1","request":{"subtype":"can_use_tool","tool_name":"Bash","input":{"command":"touch /tmp/x","description":"crear x"},"description":"crear x","blocked_path":"/tmp/x"}}"#
    guard case AgentStreamEvent.approval(let a) = AgentStreamCodec.parse(line) else {
        return expect(false, "control: debía parsear el can_use_tool")
    }
    expectEq(a.requestId, "r-1", "control: request_id")
    expectEq(a.toolName, "Bash", "control: tool")
    expectEq(a.summary, "touch /tmp/x", "control: la voz lee el comando")
    let echoed = decodeObject(a.inputJSON)
    expectEq(echoed["command"] as? String ?? "", "touch /tmp/x",
             "control: el input viaja íntegro para el eco de updatedInput")

    let sinComando = #"{"type":"control_request","request_id":"r-2","request":{"subtype":"can_use_tool","tool_name":"WebFetch","input":{"url":"https://x"},"description":"leer una página"}}"#
    guard case AgentStreamEvent.approval(let b) = AgentStreamCodec.parse(sinComando) else {
        return expect(false, "control: tools sin command también parsean")
    }
    expectEq(b.summary, "leer una página",
             "control: sin command, la voz lee la descripción")

    expect(AgentStreamCodec.parse(
        #"{"type":"control_request","request_id":"r-3","request":{"subtype":"otra_cosa"}}"#)
           == AgentStreamEvent.ignored,
           "control: subtypes desconocidos se ignoran")

    expect(AgentStreamCodec.parse(
        #"{"type":"control_request","request":{"subtype":"can_use_tool"}}"#)
           == AgentStreamEvent.ignored,
           "control: sin request_id se ignora")

    expect(AgentStreamCodec.parse(
        #"{"type":"control_request","request_id":"","request":{"subtype":"can_use_tool"}}"#)
           == AgentStreamEvent.ignored,
           "control: request_id vacío se ignora")

    let sinNada = #"{"type":"control_request","request_id":"r-4","request":{"subtype":"can_use_tool"}}"#
    guard case AgentStreamEvent.approval(let c) = AgentStreamCodec.parse(sinNada) else {
        return expect(false, "control: can_use_tool mínimo aún es un permiso")
    }
    expectEq(c.toolName, "?", "control: tool ausente queda como ?")
    expectEq(c.summary, "?", "control: sin command ni description, la voz lee el tool")
}

@MainActor func testControlResponse() {
    let allow = AgentStreamCodec.controlResponse(
        requestId: "r-1", allow: true,
        inputJSON: #"{"command":"touch /tmp/x"}"#, message: "") ?? ""
    expect(allow.hasSuffix("\n"), "response: NDJSON con salto de línea")
    let obj = decodeObject(allow)
    let resp = obj["response"] as? [String: Any] ?? [:]
    expectEq(resp["request_id"] as? String ?? "", "r-1", "response: correlaciona por id")
    expectEq(obj["type"] as? String ?? "", "control_response", "response: type")
    let inner = resp["response"] as? [String: Any] ?? [:]
    expectEq(inner["behavior"] as? String ?? "", "allow", "response: allow")
    let echoed = inner["updatedInput"] as? [String: Any] ?? [:]
    expectEq(echoed["command"] as? String ?? "", "touch /tmp/x",
             "response: el allow ecoa el input original")

    let deny = AgentStreamCodec.controlResponse(
        requestId: "r-1", allow: false,
        inputJSON: "{}", message: "no autorizado") ?? ""
    let dObj = decodeObject(deny)
    let dInner = ((dObj["response"] as? [String: Any])?["response"]) as? [String: Any] ?? [:]
    expectEq(dInner["behavior"] as? String ?? "", "deny", "response: deny")
    expectEq(dInner["message"] as? String ?? "", "no autorizado",
             "response: el deny lleva el motivo que leerá el especialista")
    expect(dInner["updatedInput"] == nil, "response: el deny no ecoa input")

    let broken = AgentStreamCodec.controlResponse(
        requestId: "r-9", allow: true,
        inputJSON: "no-json", message: "") ?? ""
    let bInner = ((decodeObject(broken)["response"] as? [String: Any])?["response"])
        as? [String: Any] ?? [:]
    let bInput = bInner["updatedInput"] as? [String: Any]
    expect(bInput != nil && bInput?.isEmpty == true,
           "response: input JSON roto ecoa objeto vacío, no truena")
}

@MainActor func testToolUseStep() {
    let line = """
    {"type":"assistant","message":{"content":[{"type":"tool_use","name":"WebSearch","input":{"query":"precio del dólar hoy"}}]}}
    """
    let event = AgentStreamCodec.parse(line)
    expectEq(event,
             AgentStreamEvent.toolUse(name: "WebSearch", detail: "precio del dólar hoy"),
             "toolUse: el bloque del stream se captura con su detalle")

    expectEq(AgentStreamCodec.stepLabel("WebSearch", "precio del dólar"),
             "buscando en internet: precio del dólar",
             "step: el nombre técnico se vuelve verbo")
    expectEq(AgentStreamCodec.stepLabel("Bash", ""), "corriendo",
             "step: sin detalle queda el verbo solo")
    expectEq(AgentStreamCodec.stepLabel("WebFetch", "x"), "leyendo la web: x",
             "step: WebFetch")
    expectEq(AgentStreamCodec.stepLabel("Read", "a.md"), "leyendo: a.md", "step: Read")
    expectEq(AgentStreamCodec.stepLabel("Write", ""), "editando", "step: Write")
    expectEq(AgentStreamCodec.stepLabel("Edit", ""), "editando", "step: Edit")
    expectEq(AgentStreamCodec.stepLabel("NotebookEdit", ""), "editando",
             "step: NotebookEdit")
    expectEq(AgentStreamCodec.stepLabel("Grep", "foo"), "buscando en el código: foo",
             "step: Grep")
    expectEq(AgentStreamCodec.stepLabel("Glob", ""), "buscando en el código",
             "step: Glob")
    expectEq(AgentStreamCodec.stepLabel("Task", ""), "delegando", "step: Task")
    expectEq(AgentStreamCodec.stepLabel("Agent", ""), "delegando", "step: Agent")
    expectEq(AgentStreamCodec.stepLabel("TodoWrite", ""), "organizando el plan",
             "step: TodoWrite")
    expectEq(AgentStreamCodec.stepLabel("FooBar", "z"), "foobar: z",
             "step: tool desconocido se lee en minúsculas")

    let plain = AgentStreamCodec.parse(
        """
        {"type":"assistant","message":{"content":[{"type":"text","text":"hola"}]}}
        """)
    expect(plain == AgentStreamEvent.ignored,
           "toolUse: el texto del asistente no es un paso")

    expectEq(AgentStreamCodec.toolDetail(fromInputJSON: #"{"query":"café"}"#),
             "café", "detail: query si no hay command")
    expectEq(AgentStreamCodec.toolDetail(
                fromInputJSON: #"{"command":"ls","query":"no"}"#),
             "ls", "detail: command gana a query")
    expectEq(AgentStreamCodec.toolDetail(fromInputJSON: #"{"command":""}"#),
             "", "detail: command vacío no cuenta")
    expectEq(AgentStreamCodec.toolDetail(fromInputJSON: "no-json"), "",
             "detail: JSON roto queda vacío")
    expectEq(AgentStreamCodec.toolDetail(fromInputJSON: "[]"), "",
             "detail: array no es input")
    let long = String(repeating: "a", count: 61)
    expectEq(AgentStreamCodec.toolDetail(fromInputJSON: #"{"url":"\#(long)"}"#),
             String(long.prefix(60)), "detail: tope 60 caracteres")
}

@MainActor func testThinkingStep() {
    let event = AgentStreamCodec.parse("""
    {"type":"assistant","message":{"content":[{"type":"thinking","thinking":"\\nReintentando el acceso al repositorio.\\nSegunda línea."}]}}
    """)
    expectEq(event,
             AgentStreamEvent.thought("Reintentando el acceso al repositorio."),
             "thinking: primera línea con sustancia, sin el salto inicial")

    let both = AgentStreamCodec.parse("""
    {"type":"assistant","message":{"content":[{"type":"thinking","thinking":"pienso"},{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}
    """)
    expectEq(both, AgentStreamEvent.toolUse(name: "Bash", detail: "ls"),
             "thinking: tool_use manda sobre thought en el mismo mensaje")

    expect(AgentStreamCodec.parse(
        #"{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"\n  \n"}]}}"#)
           == AgentStreamEvent.ignored,
           "thinking: solo whitespace no es un paso")

    let long = String(repeating: "b", count: 81)
    let clipped = AgentStreamCodec.parse(
        #"{"type":"assistant","message":{"content":[{"type":"thinking","thinking":"\#(long)"}]}}"#)
    expectEq(clipped, AgentStreamEvent.thought(String(long.prefix(80))),
             "thinking: tope 80 caracteres")
}

private func decodeObject(_ s: String) -> [String: Any] {
    guard let data = s.data(using: .utf8) else { return [:] }
    do {
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    } catch {
        return [:]
    }
}
