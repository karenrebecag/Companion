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
    testOpenURLActsOnlyForASaidHost()
    testHandsRiseWhenDestructiveOrInATerminal()
    testShellBridgeAndUnknownAreCritical()
    testAppToolsNeedConfirmation()
}

private func band(
    _ tool: String, _ arguments: [String: Any] = [:], _ facts: ActionFacts = ActionFacts()
) -> ActionBand {
    ActionBand.classify(toolName: tool, arguments: arguments, facts: facts)
}

func testReadsAndLocalHandsJustAct() {
    for tool in ["look", "see", "read_focused", "list_apps", "read_skill", "find_places",
                 "list_directory", "read_file", "web_fetch", "web_search", "sheet_read",
                 "open_app", "open_file", "focus_window", "scroll", "click", "type_text",
                 "press_key", "menu"] {
        expectEq(band(tool), .act, "hacer: \(tool)")
    }
}

func testNewFilesActAndOverwritesAreCritical() {
    let new = ["path": "/Users/k/work/Brief.pdf"]
    expectEq(band("create_document", new, ActionFacts(pathExists: false, inWorkZone: true)), .act, "documento nuevo")
    expectEq(band("create_document", new, ActionFacts(pathExists: false)), .critical, "documento fuera de la zona")
    for hidden in [".ssh/x.pdf", "a/.b/x.pdf", "../x.pdf"] {
        expectEq(band("create_document", ["path": hidden], ActionFacts(pathExists: false, inWorkZone: true)), .critical,
                 "documento en ruta oculta: \(hidden)")
    }
    expectEq(band("create_document", new, ActionFacts(pathExists: true, inWorkZone: true)), .critical, "documento que pisa")
    expectEq(band("create_document", [:], ActionFacts(pathExists: false)), .critical, "sin ruta: sube")
    let file = ["path": "/Users/k/work/a.txt"]
    expectEq(band("write_file", file, ActionFacts(pathExists: false, inWorkZone: true)), .act, "archivo nuevo en la zona")
    expectEq(band("write_file", file, ActionFacts(pathExists: true, inWorkZone: true)), .critical, "archivo que pisa")
    expectEq(band("write_file", file, ActionFacts(pathExists: false, inWorkZone: false)), .critical, "fuera de la zona")
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

func testOpenURLActsOnlyForASaidHost() {
    expectEq(band("open_url", [:], ActionFacts(hostSaid: true)), .act, "host dicho")
    expectEq(band("open_url", [:], ActionFacts(hostSaid: false)), .confirm, "host que la usuaria no dijo")
    expectEq(band("open_url"), .confirm, "sin hechos: pide")
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

func testAppToolsNeedConfirmation() {
    expectEq(band("app:slack_v2:slack_v2-send-message"), .confirm, "un conector actúa fuera")
}
