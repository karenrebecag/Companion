@testable import CompanionCore
import Foundation
import Testing

// 16q-3a: the action, the request, the tool field and what never gets printed.

private func version(_ tool: String, _ args: String) -> ActionVersion {
    ActionVersion(toolName: tool, argumentsJSON: args)
}

private func app(_ json: String, tool: String = "app:slack:slack-send-message") -> ProposedAction? {
    ProposedAction.app(toolName: tool, label: "Send Message · Slack", group: .crearYCambiar, argumentsJSON: json)
}

private func mcp(_ tool: String, _ json: String = #"{"path":"a.txt"}"#) -> ProposedAction {
    ProposedAction.mcp(ApprovalRequest(requestId: "r", toolName: tool, summary: "s", inputJSON: json))
}

// MARK: - The tool field

@Test func mcpToolIsSanitisedAndCappedButHashedRaw() {
    let long = "server/" + String(repeating: "t", count: 493)
    let action = mcp(long)
    expectEq(long.count, 500, "fixture: 500 caracteres")
    expectEq(action.tool, "<tool: 500 chars>", "16q-3a tool: un nombre de 500 no viaja, mutacion: guardar el crudo")
    expectEq(action.label, "<tool: 500 chars>", "16q-3a tool: la etiqueta MCP es ese mismo nombre")
    expectEq(action.version, version(long, #"{"path":"a.txt"}"#), "16q-3a tool: la version usa el nombre crudo")
    expect(action.version != version("<tool: 500 chars>", #"{"path":"a.txt"}"#), "16q-3a tool: y no el placeholder")
    let other = mcp("server/" + String(repeating: "t", count: 492) + "u")
    expectEq(other.tool, action.tool, "fixture: dos nombres largos se ven igual")
    expect(other.version != action.version, "16q-3a tool: pero son versiones distintas")
}

@Test func mcpToolStripsBidiAndZeroWidth() {
    let action = mcp("file\u{202E}sys\u{200B}/wri\u{2066}te\u{FEFF}_file")
    expectEq(action.tool, "filesys/write_file", "16q-3a tool: bidi y ancho cero fuera")
    expectEq(action.label, "filesys/write_file", "16q-3a tool: tambien en la etiqueta")
    expectEq(action.version, version("file\u{202E}sys\u{200B}/wri\u{2066}te\u{FEFF}_file", #"{"path":"a.txt"}"#),
             "16q-3a tool: la version conserva lo que llego")
    expect(action.version != version("filesys/write_file", #"{"path":"a.txt"}"#),
           "16q-3a tool: dos nombres que se ven igual no comparten version")
}

@Test func toolCapCountsGraphemesAndScalars() {
    let t80 = "s/" + String(repeating: "x", count: 78)
    expectEq(mcp(t80).tool, t80, "16q-3a tool: 80 exactos pasan")
    expectEq(mcp(t80 + "x").tool, "<tool: 81 chars>", "16q-3a tool: 81 colapsan")
    let zalgo = "s/" + String(repeating: "a" + String(repeating: "\u{0301}", count: 15), count: 30)
    expectEq(mcp(zalgo).tool, "<tool: 32 chars>", "16q-3a tool: 32 grafemas pero 482 escalares, colapsa por escalares")
    let emoji = String(repeating: "\u{1F600}", count: 80)
    expectEq(mcp(emoji).tool, emoji, "16q-3a tool: 80 emoji pasan")
}

@Test func appToolIsSanitisedAndCappedToo() {
    let long = "app:slack:" + String(repeating: "t", count: 490)
    let action = app("{}", tool: long)
    expectEq(action?.tool, "<tool: 500 chars>", "16q-3a tool: la tool app tambien")
    expectEq(action?.version, version(long, "{}"), "16q-3a tool: y su version es la cruda")
    expectEq(app("{}", tool: "app:slack:se\u{200B}nd")?.tool, "app:slack:send", "16q-3a tool: app sin ancho cero")
}

// MARK: - Constructors

@Test func publicInitsCannotBypassTheSanitising() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/CompanionCore/Decision/ActionJudging.swift"),
                            encoding: .utf8)
    expect(!source.contains("public init(values:"), "16q-3a init: ActionSummary no se construye desde fuera")
    expect(!source.contains("public init(kind:"), "16q-3a init: ProposedAction tampoco")
    expect(source.contains("init(values: [String: Value], isComplete"), "16q-3a init: el interno existe")
}

// MARK: - UserWords, ProposedAction, ActionJudgeRequest

@Test func userWordsSanitisesCapsAndRejectsEmpty() {
    expect(UserWords(heard: "") == nil, "16q-3a palabras: vacio no se juzga")
    expect(UserWords(heard: "  \n\t ") == nil, "16q-3a palabras: solo blancos tampoco")
    expect(UserWords(heard: "\u{200B}\u{202E}") == nil, "16q-3a palabras: vacio tras sanear")
    expectEq(UserWords(heard: String(repeating: "a", count: 5000))?.text.count, 1000, "16q-3a palabras: tope de 1000")
    expectEq(UserWords(heard: "hola\u{200B} mundo")?.text, "hola mundo", "16q-3a palabras: saneadas")
}

@Test func proposedActionMapsGroupsAndSkipsReads() {
    let make = { (group: AppAction.Group) in
        ProposedAction.app(toolName: "app:slack:slack-send-message", label: "Send Message · Slack",
                           group: group, argumentsJSON: #"{"channel":"x"}"#)
    }
    expect(make(.leer) == nil, "16q-3a accion: una lectura no se juzga")
    expectEq(make(.crearYCambiar)?.effect, .change, "16q-3a accion: crear y cambiar es change")
    expectEq(make(.borrar)?.effect, .delete, "16q-3a accion: borrar es delete")
    expectEq(make(.borrar)?.kind, .app, "16q-3a accion: kind app")
    let long = String(repeating: "L", count: 200)
    let labelled = ProposedAction.app(toolName: "t", label: long, group: .borrar, argumentsJSON: "{}")
    expectEq(labelled?.label.count, 80, "16q-3a accion: etiqueta de 80 como mucho")
}

@Test func proposedActionForMCPIsUnknownEffectAndKeepsNoSummaryText() {
    let request = ApprovalRequest(requestId: "r1", toolName: "filesystem/write_file",
                                  summary: "Write a file for a third party", inputJSON: #"{"path":"notes.txt"}"#)
    let action = ProposedAction.mcp(request)
    expectEq(action.kind, .mcp, "16q-3a mcp: kind")
    expectEq(action.effect, .unknown, "16q-3a mcp: efecto unknown (D7)")
    expectEq(action.tool, "filesystem/write_file", "16q-3a mcp: nombre de la hoja")
    expectEq(action.arguments.values["path"], .text("notes.txt"), "16q-3a mcp: argumentos resumidos")
    expectEq(action.version, ActionVersion(toolName: "filesystem/write_file", argumentsJSON: #"{"path":"notes.txt"}"#),
             "16q-3a mcp: misma version que vera la hoja")
    expect(!action.label.contains("third party"), "16q-3a mcp: el resumen de un tercero no viaja")
}

@Test func judgeRequestIsNilForEmptyOrOversizedBatches() {
    guard let words = UserWords(heard: "hola"),
          let action = ProposedAction.app(toolName: "t", label: "l", group: .borrar, argumentsJSON: "{}")
    else {
        Issue.record("fixtures")
        return
    }
    expect(ActionJudgeRequest(words: words, actions: [], pipeline: .classic) == nil, "16q-3a lote: vacio es nil")
    let eight = Array(repeating: action, count: 8)
    expect(ActionJudgeRequest(words: words, actions: eight, pipeline: .realtime) != nil, "16q-3a lote: 8 caben")
    let nine = Array(repeating: action, count: 9)
    expect(ActionJudgeRequest(words: words, actions: nine, pipeline: .realtime) == nil, "16q-3a lote: 9 no caben")
}

// MARK: - Redaction

@Test func judgeTypesRedactTheirDescription() {
    let secret = "zanahoria"
    let words = UserWords(heard: "mándale \(secret) a Ana")
    let action = ProposedAction.app(
        toolName: "app:gmail:gmail-send-email", label: "Send Email · \(secret)",
        group: .crearYCambiar, argumentsJSON: #"{"to":"\#(secret)@x.com"}"#)
    guard let words, let action, let request = ActionJudgeRequest(words: words, actions: [action], pipeline: .classic) else {
        Issue.record("16q-3a redaccion: los fixtures debian construirse")
        return
    }
    let renders: [String] = [
        "\(words)", "\(action)", "\(action.arguments)", "\(action.version)", "\(request)",
        String(reflecting: words), String(reflecting: action), String(reflecting: request),
        String(reflecting: action.arguments), String(reflecting: action.version),
    ]
    for text in renders {
        expect(!text.contains(secret), "16q-3a redaccion: \(text) no filtra el texto")
        expect(!text.contains("gmail"), "16q-3a redaccion: ni el nombre de la tool (D8)")
    }
    expectEq("\(words)", "<user words: \(words.text.count) chars>", "16q-3a redaccion: forma fija")
}

private let dumpSecret = "zanahoria"

private func dumpFixtures() -> (words: UserWords, action: ProposedAction, request: ActionJudgeRequest)? {
    guard let words = UserWords(heard: "mándale \(dumpSecret) a Ana"),
          let action = ProposedAction.app(
              toolName: "app:gmail:gmail-send-email", label: "Send Email · \(dumpSecret)",
              group: .crearYCambiar, argumentsJSON: #"{"to":"\#(dumpSecret)@x.com"}"#),
          let request = ActionJudgeRequest(words: words, actions: [action], pipeline: .classic)
    else {
        Issue.record("16q-3a redaccion: los fixtures debian construirse")
        return nil
    }
    return (words, action, request)
}

/// `dump` reads the mirror, not the description: a type that redacts one and
/// reflects the other still prints its contents there. And a mirror whose
/// subject is not the type itself (`Mirror(reflecting: text)`) is a reflection
/// of the secret, whatever `dump` happens to print for it today.
private func expectRedactedMirror<T>(_ value: T, _ name: String) {
    var dumped = ""
    dump(value, to: &dumped)
    expect(!dumped.contains(dumpSecret), "16q-3a redaccion: dump de \(name) no filtra el texto")
    expect(!dumped.contains("gmail"), "16q-3a redaccion: dump de \(name) no filtra la tool")
    let mirror = Mirror(reflecting: value)
    expect(mirror.children.isEmpty, "16q-3a redaccion: \(name) no expone hijos")
    expect(mirror.subjectType == T.self, "16q-3a redaccion: el espejo de \(name) es de si mismo, no de un campo suyo")
}

@Test func userWordsRedactWhatDumpReads() {
    guard let fixtures = dumpFixtures() else { return }
    expectRedactedMirror(fixtures.words, "UserWords")
}

@Test func proposedActionRedactsWhatDumpReads() {
    guard let fixtures = dumpFixtures() else { return }
    expectRedactedMirror(fixtures.action, "ProposedAction")
}

@Test func actionSummaryRedactsWhatDumpReads() {
    guard let fixtures = dumpFixtures() else { return }
    expectRedactedMirror(fixtures.action.arguments, "ActionSummary")
}

@Test func actionVersionRedactsWhatDumpReads() {
    guard let fixtures = dumpFixtures() else { return }
    var dumped = ""
    dump(fixtures.action.version, to: &dumped)
    expect(!dumped.contains(fixtures.action.version.hex), "16q-3a redaccion: dump no filtra el digest")
    expectRedactedMirror(fixtures.action.version, "ActionVersion")
}

@Test func judgeRequestRedactsWhatDumpReads() {
    guard let fixtures = dumpFixtures() else { return }
    expectRedactedMirror(fixtures.request, "ActionJudgeRequest")
}
