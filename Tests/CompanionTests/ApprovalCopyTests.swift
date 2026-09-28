import CompanionCore
import Foundation
import Testing

// Wave 19-1: la hoja habla humano. `ApprovalCopy` convierte la peticion
// cruda (tool id + JSON) en frase con sujeto, vista previa auditable y
// glifo — puro, sin ventana, en los dos idiomas del catalogo.

@Test @MainActor func approvalCopyToolTests() {
    let url = display("open_url", #"{"url":"https://upload.wikimedia.org/wikipedia/commons/e/e1/FullMoon2010.jpg"}"#)
    expectEq(url.lead, "Abrir", "19-1 url: el verbo")
    expectEq(url.subject, "upload.wikimedia.org", "19-1 url: el host es el sujeto, no la URL")
    expect(url.preview == nil,
           "19-1c url: con el host en el titulo, la URL entera era ruido (Karen); solo se muestra si NO parsea")
    expect(url.showsRemember, "19-1 url: recordable")
    expectEq(display("open_url", #"{"url":"https://upload.wikimedia.org/x"}"#, language: .en).lead,
             "Open", "19-1 url: en ingles tambien")
    expectEq(display("open_url", #"{"url":"no es una url"}"#).subject, "no es una url",
             "19-1 url: si no parsea, el texto tal cual — nunca esconder")

    let text = display("type_text", #"{"text":"hola mundo","app":"Notas"}"#)
    expectEq(text.lead, "Escribir en", "19-1 texto: el verbo")
    expectEq(text.subject, "Notas", "19-1 texto: la app es el sujeto")
    expectEq(text.preview, "hola mundo", "19-1 texto: COMPLETO, un corte esconderia lo que corre (15g M1)")
    let long = String(repeating: "a", count: 500)
    expectEq(display("type_text", #"{"text":"\#(long)"}"#).preview, long,
             "19-1 texto: largo sigue completo")
    expectEq(display("type_text", #"{"text":"x"}"#).subject, "el campo activo",
             "19-1 texto: sin app, el campo activo")

    let click = display("click", #"{"label":"Permitir","app":"Safari"}"#)
    expectEq(click.lead, "Pulsar", "19-1 click: el verbo")
    expectEq(click.subject, "Permitir", "19-1 click: el boton es el sujeto")
    expectEq(click.preview, "Safari", "19-1 click: la app en secundario")

    let shell = display("run_shell", #"{"command":"npm run build --workspace web"}"#)
    expectEq(shell.lead, "Ejecutar", "19-1 shell: el verbo")
    expectEq(shell.subject, "npm", "19-1 shell: la primera palabra es el sujeto")
    expectEq(shell.preview, "npm run build --workspace web", "19-1 shell: el comando entero auditable")
    let longCommand = "echo " + String(repeating: "a", count: 300)
    expectEq(display("run_shell", #"{"command":"\#(longCommand)"}"#).preview, longCommand,
             "19-1 shell: NUNCA se corta el preview — la cola tambien corre (review 19-1)")
    let longApp = String(repeating: "b", count: 200)
    let pushed = display("type_text", #"{"text":"x","app":"\#(longApp)"}"#)
    expect(pushed.subject.count <= 80 && pushed.subject.contains("…"),
           "19-1 sujeto: tapado a 80 con marca, nada empuja los botones fuera")
    let padded = "https://paypal.com." + String(repeating: "a", count: 70) + ".evil.net/x"
    expect(display("open_url", #"{"url":"\#(padded)"}"#).subject.hasSuffix("evil.net"),
           "19-1 host: el corte es por el medio — el dominio REAL queda visible al final")
    expect(!display("type_text", #"{"text":"x","app":"a\nb\nc"}"#).subject.contains("\n"),
           "19-1 sujeto: sin saltos de linea, un titulo es una linea")

    let write = display("write_file", #"{"path":"/Users/k/notas/ideas.md","content":"x"}"#)
    expectEq(write.lead, "Escribir el archivo", "19-1 archivo: el verbo")
    expectEq(write.subject, "ideas.md", "19-1 archivo: el nombre es el sujeto")
    expectEq(write.preview, "/Users/k/notas/ideas.md", "19-1 archivo: la ruta completa auditable")

    let key = display("press_key", #"{"key":"return","app":"Terminal","line":"rm -rf x"}"#)
    expectEq(key.subject, "return", "19-1 tecla: la tecla es el sujeto")
    expectEq(key.preview, "Terminal\nrm -rf x", "19-1 tecla: app y linea auditables")
}

@Test @MainActor func approvalCopyBridgeAndFallbackTests() {
    let bridge = display("bridge_session", #"{"client":"claude-code"}"#)
    expect(bridge.lead == nil, "19-1 puente: el cliente abre la frase")
    expectEq(bridge.subject, "claude-code", "19-1b puente: el nombre plano — la advertencia del detalle ya dice que es un dicho")
    expectEq(bridge.mark, .claude, "19-1b puente: un cliente claude-* lleva el logo de Claude")
    expectEq(display("bridge_session", #"{"client":"otro-shim"}"#).mark, .symbol("hand.raised"),
             "19-1b puente: cliente desconocido, glifo generico")
    expectEq(display("bridge_session", #"{"client":"claude-evil"}"#).mark, .symbol("hand.raised"),
             "19-1b puente: el logo es por allowlist exacta — un prefijo no viste a nadie de Claude")
    expectEq(display("bridge_session", #"{"client":"Claude Desktop"}"#).mark, .claude,
             "19-1b puente: los clientes Claude conocidos si llevan el logo")
    expectEq(display("open_url", #"{"url":"https://x.dev/a"}"#).mark, .symbol("link"),
             "19-1b marca: las tools conservan su glifo")
    expectEq(bridge.trail, BridgeCopy.sheetTitle(.es), "19-1 puente: la frase del catalogo")
    expect(bridge.preview == nil,
           "19-1c puente: sin caja de detalle — el titulo lo dice todo (Karen)")
    expect(!bridge.showsRemember, "19-1 puente: jamas se recuerda")
    expectEq(display("bridge_session", #"{"client":"a\nb<script>"}"#).subject, "abscript",
             "19-1 puente: sin saltos ni marcado, solo lo imprimible del nombre")
    expectEq(display("bridge_session", #"{"client":"Сlaude-code"}"#).subject, "laude-code",
             "19-1 puente: solo ASCII — un homoglifo cirilico no se disfraza de nadie")
    expectEq(display("bridge_session", "{}").subject, "El cliente",
             "19-1 puente: sin nombre, un generico")

    let unknown = display("tool_rara", #"{"query":"clima manana"}"#)
    expectEq(unknown.subject, "tool_rara",
             "19-1 fallback: el id SIEMPRE visible en el titulo — el hover no es camino de auditoria")
    expectEq(unknown.preview, "clima manana", "19-1 fallback: el dato interesante, completo, abajo")
    let longGoal = String(repeating: "g", count: 400)
    expectEq(display("tool_rara", #"{"goal":"\#(longGoal)"}"#).preview, longGoal,
             "19-1 fallback: el preview jamas se corta")
    let broken = display("tool_rara", "no json")
    expectEq(broken.subject, "tool_rara", "19-1 fallback: sin datos, el id")
    expect(broken.preview == nil, "19-1 fallback: sin datos no hay caja")
    expectEq(broken.title, "Permitir tool_rara", "19-1 fallback: el titulo se compone entero")
    expectEq(display("click", #"{"label":""}"#).subject, "click",
             "19-1 vacio: un label vacio cae al fallback, nunca un titulo trunco")
    expectEq(display("open_app", #"{"name":"Notas"}"#).title, "Abrir la app Notas", "19-1 app")
    expectEq(display("open_file", #"{"path":"/tmp/a/b.pdf"}"#).subject, "b.pdf", "19-1 archivo abrir")
    expectEq(display("edit_file", #"{"path":"/tmp/a/b.md"}"#).lead, "Editar el archivo", "19-1 editar")
    expectEq(display("write_file", #"{"path":"/"}"#).subject, "/",
             "19-1 archivo: una ruta sin nombre usa la ruta entera, nunca un sujeto vacio")
    expectEq(display("tool_rara", "no json", language: .en).lead, "Allow", "19-1 fallback en ingles")
    expectEq(display("type_text", #"{"text":"x"}"#, language: .en).subject, "the active field",
             "19-1 texto en ingles")
    expectEq(display("bridge_session", "{}", language: .en).trail, BridgeCopy.sheetTitle(.en),
             "19-1 puente en ingles")
    expectEq(display("open_url", #"{"url":"https://es.wikipedia.org/wiki/Luna"}"#).title,
             "Abrir es.wikipedia.org", "19-1 titulo: lead + sujeto")
}

@Test @MainActor func approvalCopyRememberedLabelTests() {
    expectEq(ApprovalCopy.toolLabel("open_url", language: .es), "abrir un enlace",
             "19-1 recordado: singular — la memoria es por patron, no un permiso general")
    expectEq(ApprovalCopy.toolLabel("run_shell", language: .en), "run a command",
             "19-1 recordado: en ingles tambien")
    expectEq(ApprovalCopy.toolLabel("tool_rara", language: .es), "tool_rara",
             "19-1 recordado: desconocida queda tal cual")
}

private func display(
    _ tool: String, _ inputJSON: String, language: AppLanguage = .es
) -> ApprovalDisplay {
    ApprovalCopy.display(
        for: ApprovalRequest(requestId: "t", toolName: tool, summary: "", inputJSON: inputJSON),
        language: language)
}
