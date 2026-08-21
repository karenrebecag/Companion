import CompanionCore
import Testing

@Test @MainActor func escalationTests() {
    testExecutorPrompt()
    testJobPrompt()
    testPromptPreambulo()
    testHandoffRobustness()
}

@MainActor func testExecutorPrompt() {
    let p = Escalation.executorPrompt(
        Handoff(goal: "plan de migración", context: "repo en Swift"),
        original: "quiero migrar esto",
        workdir: "/tmp/work",
        desktop: "/tmp/Desktop")
    expect(p.contains("plan de migración"), "executor: lleva el objetivo")
    expect(p.contains("repo en Swift"), "executor: lleva el contexto")
    expect(p.contains("quiero migrar esto"), "executor: lleva la petición original")
    expect(p.contains("pantalla"), "executor: pide respuesta completa para pantalla")
    expect(p.contains("/tmp/work"), "executor: inyecta workdir")
    expect(p.contains("/tmp/Desktop"), "executor: inyecta desktop")

    let sinContexto = Escalation.executorPrompt(
        Handoff(goal: "leer notas", context: ""),
        original: "lee esto",
        workdir: "/w",
        desktop: "/d")
    expect(!sinContexto.contains("Contexto:"),
           "executor: sin contexto no hay línea vacía")
}

@MainActor func testJobPrompt() {
    let h = Handoff(goal: "renombrar capturas", context: "solo las png")
    let p = Escalation.jobPrompt(h, workdir: "/Users/me/proj", desktop: "/Users/me/Desktop")
    expect(p.contains("renombrar capturas"), "encargo: lleva el objetivo")
    expect(p.contains("solo las png"), "encargo: lleva el contexto")
    expect(p.contains("Carpeta de trabajo:"), "encargo: lleva el workdir")
    expect(p.contains("/Users/me/proj"), "encargo: inyecta workdir")
    expect(p.contains("/Users/me/Desktop"), "encargo: inyecta desktop")
    expect(!Escalation.executorRole.isEmpty
           && !p.contains(Escalation.executorRole),
           "encargo: el rol NO viaja por encargo — va una vez, en el system prompt")
    expect(Escalation.executorRole.contains("Companion (asistente de voz)"),
           "encargo: el rol conserva el wording original")

    let sinContexto = Escalation.jobPrompt(
        Handoff(goal: "leer notas", context: ""),
        workdir: "/w", desktop: "/d")
    expect(!sinContexto.contains("Contexto:"),
           "encargo: sin contexto no hay línea vacía")
}

@MainActor func testPromptPreambulo() {
    expectEq(Escalation.voicePreamble,
             "Responde en maximo 2 frases, en espanol, sin markdown. ",
             "preámbulo: wording original intacto")
    let first = Escalation.voiceTurnPrompt("hola", firstTurn: true)
    expect(first.hasPrefix(Escalation.voicePreamble),
           "preámbulo: el primer turno lleva la instrucción")
    expectEq(Escalation.voiceTurnPrompt("hola", firstTurn: false), "hola",
             "preámbulo: los turnos siguientes van limpios")
    expectEq(Escalation.voiceTurnPrompt("", firstTurn: true),
             Escalation.voicePreamble,
             "preámbulo: texto vacío en el primer turno es solo la instrucción")
    expectEq(Escalation.voiceTurnPrompt("", firstTurn: false), "",
             "preámbulo: texto vacío en turnos siguientes queda vacío")
}

@MainActor func testHandoffRobustness() {
    expect(Handoff.parse(toolName: "delegate", arguments: #"{"goal": ""}"#) == nil,
           "handoff: goal vacío no delega")
    expect(Handoff.parse(toolName: "delegate", arguments: #"{"goal": "x"#) == nil,
           "handoff: JSON truncado no truena ni delega")
    expect(Handoff.parse(toolName: "otra", arguments: #"{"goal": "x"}"#) == nil,
           "handoff: herramienta desconocida no delega")
    let solo = Handoff.parse(toolName: "delegate",
                             arguments: #"{"goal": "leer notas"}"#)
    expectEq(solo?.goal ?? "", "leer notas", "handoff: con goal alcanza")
    expectEq(solo?.context ?? "", "", "handoff: context opcional queda vacío")

    expect(Handoff.parse(toolName: "delegate", arguments: #"{"goal": "   "}"#) == nil,
           "handoff: goal solo espacios no delega")
    expect(Handoff.parse(toolName: "Delegate", arguments: #"{"goal": "x"}"#) == nil,
           "handoff: el nombre es exacto, no se adivina")
    expect(Handoff.parse(toolName: "delegate", arguments: "") == nil,
           "handoff: argumentos vacíos no delega")
    expect(Handoff.parse(toolName: "delegate", arguments: "[]") == nil,
           "handoff: un array no es un objeto de handoff")
    expect(Handoff.parse(toolName: "delegate", arguments: "null") == nil,
           "handoff: null no delega")
    expect(Handoff.parse(toolName: "delegate", arguments: #"{"goal": 1}"#) == nil,
           "handoff: goal que no es string no delega")
    expect(Handoff.parse(toolName: "", arguments: #"{"goal": "x"}"#) == nil,
           "handoff: toolName vacío no delega")

    let recortado = Handoff.parse(
        toolName: "delegate",
        arguments: #"{"goal": "  leer notas  ", "context": "  workdir ~  "}"#)
    expectEq(recortado?.goal ?? "", "leer notas", "handoff: recorta el goal")
    expectEq(recortado?.context ?? "", "workdir ~", "handoff: recorta el context")

    let nulo = Handoff.parse(
        toolName: "delegate",
        arguments: #"{"goal": "x", "context": null}"#)
    expectEq(nulo?.context ?? "missing", "",
             "handoff: context JSON null queda vacío, no truena")

    let especial = Handoff.parse(
        toolName: "delegate",
        arguments: #"{"goal": "a\"; DROP TABLE", "context": "ñoño"}"#)
    expectEq(especial?.goal ?? "", "a\"; DROP TABLE",
             "handoff: caracteres especiales viajan intactos")
    expectEq(especial?.context ?? "", "ñoño",
             "handoff: unicode en context viaja intacto")
}
