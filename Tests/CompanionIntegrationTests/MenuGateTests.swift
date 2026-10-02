import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionServicesTestSupport
import CompanionTestKit
import CompanionUI
import Foundation
import Testing

// Wave 20c D3 (F3): `menu` goes through the same destructive family and the
// same one-shot ticket as `click`. A menu path ending in Empty Trash, Delete,
// Send... never runs on the model's say-so, from chat, voice or the bridge.

@Test @MainActor func menuGateTests() async {
    testMenuClassifiesItsLastComponentWithClicksClassifier()
    testSigningOutAsksFromClickAndMenuButClosingDoesNot()
    testTheSheetForSigningOutNamesTheItem()
    await testADestructiveMenuRunsOnlyThroughTheGate()
    await testANavigationMenuRunsWithoutTheSheet()
    await testTheBridgeCannotRunADestructiveMenuWithoutTheSheet()
    testMenuPathParsing()
    await testAPartialNameForADestructiveItemNeverPressesWithoutApproval()
    await testTheSheetNamesTheResolvedItemAndPressesItOnce()
    await testABenignPartialNameStillRuns()
    await testATicketIsBoundToTheResolvedItem()
    testQuittingOrClosingFromTheMenuAsksUnlessTheUserSaidIt()
    await testTheBridgeCannotQuitAnAppThroughTheMenu()
    await testAPartialNameThatQuitsAsksAndPressesTheResolvedItemOnce()
    await testSayingItQuitsWithoutTheSheet()
    await testTheBridgeQuitsOnlyAfterTheSheet()
}

private func menuRunner(_ screen: FakeScreen, bundle: String = "com.apple.finder") -> ParentToolRunner {
    let hands = FakeHands(field: FocusedField(app: "Finder", pid: 7))
    return ParentToolRunner(
        workspace: FakeWorkspaceOpener(),
        hands: ScreenHands(
            injector: hands, reader: hands, keys: hands, windows: hands,
            trusted: { true }, target: { 7 }, bundleID: { _ in bundle }, screen: screen))
}

private func menuCall(_ path: String) -> ToolCallRef {
    ToolCallRef(id: "m", name: "menu", arguments: #"{"path":"\#(path)"}"#)
}

private let destructivePaths = [
    "Finder > Vaciar papelera", "Archivo > Mover a la papelera", "File > Move to Trash",
    "Edit > Delete", "Mensaje > Enviar", "Message > Send", "Archivo > Eliminar…",
]

@MainActor func testMenuClassifiesItsLastComponentWithClicksClassifier() {
    for path in destructivePaths {
        let parts = HandsGate.menuPath(["path": path])
        let last = parts.last ?? ""
        expect(HandsGate.menuNeedsTicket(path: parts), "menu destructivo: \(path)")
        // Same words as a click on that label: the two cannot drift apart.
        expectEq(HandsGate.menuNeedsTicket(path: [last]),
                 HandsGate.clickNeedsTicket(label: last, context: ""), "misma familia que click: \(last)")
    }
    expect(!HandsGate.menuNeedsTicket(path: ["View", "Sort By", "Name"]), "navegación: sin ticket")
    expect(!HandsGate.menuNeedsTicket(path: ["Window", "Zoom"]), "Zoom: sin ticket")
    expect(!HandsGate.menuNeedsTicket(path: ["Trash", "Open"]), "solo el ítem final cuenta")
    expect(!HandsGate.menuNeedsTicket(path: []), "ruta vacía: nada que pedir")
    expectEq(HandsGate.menuVerdict(path: ["Finder", "Vaciar papelera"], said: "abre el menú"), .ask,
             "no pedido: hoja")
    expectEq(HandsGate.menuVerdict(path: ["Finder", "Vaciar papelera"], said: "vacía la papelera"), .act,
             "pedido con palabra de la familia: directo")
    expectEq(HandsGate.menuVerdict(path: ["Finder", "Vaciar papelera"], said: "envíalo"), .ask,
             "otra familia no autoriza")
}

@MainActor func testADestructiveMenuRunsOnlyThroughTheGate() async {
    for path in destructivePaths {
        let screen = FakeScreen([])
        let runner = menuRunner(screen)
        let arguments = #"{"path":"\#(path)"}"#
        let request = runner.approval(for: menuCall(path), said: "")
        expectEq(request?.toolName, "menu", "hoja para \(path)")
        expect(request.map { ChatCopy.approvalDetail(tool: $0.toolName, inputJSON: $0.inputJSON) }?
            .contains(HandsGate.menuPath(["path": path]).last ?? "?") == true,
               "la hoja nombra el ítem: \(path)")
        let unasked = await runner.execute(name: "menu", argumentsJSON: arguments)
        expect(unasked.output.hasPrefix("approval_required:"), "sin el clic: no corre \(path)")
        expect(screen.menus.isEmpty, "sin el clic: el menú no se invoca \(path)")
        if let request { runner.granted(request) }
        let approved = await runner.execute(name: "menu", argumentsJSON: arguments)
        expect(approved.ok, "con el clic: corre \(path)")
        expectEq(screen.menus.count, 1, "con el clic: una invocación \(path)")
        let again = await runner.execute(name: "menu", argumentsJSON: arguments)
        expect(again.output.hasPrefix("approval_required:"), "el ticket es de un solo uso \(path)")
    }
}

@MainActor func testANavigationMenuRunsWithoutTheSheet() async {
    let screen = FakeScreen([])
    let runner = menuRunner(screen)
    for path in ["View > Sort By > Name", "Window > Zoom", "Archivo > Exportar como PDF…"] {
        expect(runner.approval(for: menuCall(path), said: "") == nil, "sin hoja: \(path)")
        let out = await runner.execute(name: "menu", argumentsJSON: #"{"path":"\#(path)"}"#)
        expect(out.ok, "corre: \(path)")
    }
    expectEq(screen.menus.count, 3, "las tres invocadas")
}

@MainActor func testTheBridgeCannotRunADestructiveMenuWithoutTheSheet() async {
    let arguments = #"{"path":"Finder > Vaciar papelera"}"#
    let line = #"{"id":2,"method":"call","params":{"name":"menu","arguments":\#(arguments)}}"#
    let hello = #"{"id":1,"method":"hello","params":{"token":"tok","client":"claude-code","protocol":1}}"#

    let deniedScreen = FakeScreen([])
    let denying = ScriptedApprovals(answer: true)
    denying.setAnswer(false, forTool: "menu")
    let denied = BridgeSession(
        tools: menuRunner(deniedScreen), guard: ParentToolGuard(approvals: denying),
        token: { "tok" }, language: { .en }, accessibility: { true })
    _ = await denied.handle(line: hello)
    let refused = await denied.handle(line: line)
    expect(refused.reply.contains("denied_by_user"), "puente: el no de la hoja frena el menú")
    expect(deniedScreen.menus.isEmpty, "puente: sin el clic no se invoca")
    expect(denying.requests.contains { $0.toolName == "menu" }, "puente: la hoja se pidió")

    let okScreen = FakeScreen([])
    let approving = ScriptedApprovals(answer: true)
    let approved = BridgeSession(
        tools: menuRunner(okScreen), guard: ParentToolGuard(approvals: approving),
        token: { "tok" }, language: { .en }, accessibility: { true })
    _ = await approved.handle(line: hello)
    let done = await approved.handle(line: line)
    expect(done.reply.contains(#""ok":true"#), "puente: con el clic corre")
    expectEq(okScreen.menus.count, 1, "puente: una invocación")
}

private let signOutLabels = [
    "Cerrar sesión", "cerrar sesion", "Log Out", "Log out", "Logout", "Sign Out", "Sign out", "Signout",
    "Cierra la sesión", "Cierro la sesión", "Cerrar mi sesión", "Cerrar tu sesión", "Cerrar su sesión",
    "Cierre de sesión", "Log off", "Logoff", "Sign off", "Log Off…",
]
private let closingLabels = [
    "Cerrar", "Cerrar ventana", "Cerrar pestaña", "Cerrar todas las pestañas", "Close", "Close Window",
    "Close Tab", "Salir", "Cerrar sesiones abiertas",
]
private let notSignOutLabels = closingLabels + [
    "Sesión nueva", "Nueva sesión", "Desconectar", "Sesión", "Sesiones abiertas",
]

// Wave 20c F3 criterion 4: signing out is destructive from any surface, so
// the family lives in the shared classifier and click and menu agree on it.
@MainActor func testSigningOutAsksFromClickAndMenuButClosingDoesNot() {
    for label in signOutLabels {
        expect(HandsGate.menuNeedsTicket(path: ["Cuenta", label]), "menu pide hoja: \(label)")
        expect(HandsGate.clickNeedsTicket(label: label, context: ""), "click pide hoja: \(label)")
        expectEq(HandsGate.menuVerdict(path: [label], said: ""), .ask, "menu sin pedirlo: \(label)")
        expectEq(HandsGate.clickVerdict(label: label, context: "", said: ""), .ask, "click sin pedirlo: \(label)")
        expectEq(HandsGate.menuVerdict(path: [label], said: "cierra la sesión"), .act,
                 "pedido con la frase: \(label)")
        expectEq(HandsGate.menuVerdict(path: [label], said: "cierra la ventana"), .ask,
                 "cerrar otra cosa no autoriza: \(label)")
    }
    for label in notSignOutLabels {
        expect(!HandsGate.clickNeedsTicket(label: label, context: ""), "click sin hoja: \(label)")
    }
    for label in notSignOutLabels where !closingLabels.contains(label) {
        expect(!HandsGate.menuNeedsTicket(path: ["Archivo", label]), "menu sin hoja: \(label)")
    }
    // Closing labels part ways on purpose (D4): see the quit/close test below.
    for label in signOutLabels + notSignOutLabels where !closingLabels.contains(label) {
        expectEq(HandsGate.menuNeedsTicket(path: [label]),
                 HandsGate.clickNeedsTicket(label: label, context: ""), "misma familia: \(label)")
    }
}

@MainActor func testTheSheetForSigningOutNamesTheItem() {
    for label in signOutLabels {
        let runner = menuRunner(FakeScreen([]))
        let request = runner.approval(for: menuCall("Cuenta > \(label)"), said: "")
        expectEq(request?.toolName, "menu", "hoja para \(label)")
        expect(request.map { ChatCopy.approvalDetail(tool: $0.toolName, inputJSON: $0.inputJSON) }?
            .contains(label) == true, "la hoja nombra el ítem: \(label)")
    }
}

@MainActor func testMenuPathParsing() {
    expectEq(HandsGate.menuPath([:]), [], "sin argumento")
    expectEq(HandsGate.menuPath(["path": ""]), [], "vacía")
    expectEq(HandsGate.menuPath(["path": " > > "]), [], "solo separadores")
    expectEq(HandsGate.menuPath(["path": 7]), [], "tipo inválido")
    expectEq(HandsGate.menuPath(["path": "Archivo"]), ["Archivo"], "un componente")
    expectEq(HandsGate.menuPath(["path": "Archivo > Exportar >"]), ["Archivo", "Exportar"], "separador final")
    expectEq(HandsGate.menuPath(["path": "  Edición>Pegar  "]), ["Edición", "Pegar"], "espacios y sin espacios")
    expectEq(HandsGate.menuPath(["path": "Ver > 😀 ; DROP"]), ["Ver", "😀 ; DROP"], "unicode y metacaracteres")
}

private let fuzzyDestructive: [(query: String, item: String)] = [
    ("Finder > Empty", "Empty Trash…"), ("File > Move", "Move to Trash"),
    ("Cuenta > Sesión", "Cerrar sesión"), ("Cuenta > Sesion", "Cerrar sesión"),
    ("Mensaje > Env", "Enviar"), ("Tienda > Pag", "Pagar"),
    ("Cuenta > Log", "Log Out…"), ("Cuenta > Sign", "Sign Out…"),
]

// H-1: the item pressed is the item classified, not the string the model typed.
@MainActor func testAPartialNameForADestructiveItemNeverPressesWithoutApproval() async {
    for (query, item) in fuzzyDestructive {
        let screen = FakeScreen([])
        screen.menuTitles = [item]
        let runner = menuRunner(screen)
        let arguments = #"{"path":"\#(query)"}"#
        let out = await runner.execute(name: "menu", argumentsJSON: arguments)
        expect(out.output.hasPrefix("approval_required:"), "sin hoja no corre: \(query) -> \(item)")
        expect(screen.menus.isEmpty, "el ítem destructivo no se presiona: \(query) -> \(item)")
    }
}

@MainActor func testTheSheetNamesTheResolvedItemAndPressesItOnce() async {
    for (query, item) in fuzzyDestructive {
        let screen = FakeScreen([])
        screen.menuTitles = [item]
        let runner = menuRunner(screen)
        let request = runner.approval(for: menuCall(query), said: "")
        expectEq(request?.toolName, "menu", "hoja para la ruta parcial: \(query)")
        expect(request.map { ChatCopy.approvalDetail(tool: $0.toolName, inputJSON: $0.inputJSON) }?
            .contains(item) == true, "la hoja nombra lo que se presionaría: \(item)")
        if let request { runner.granted(request) }
        let approved = await runner.execute(name: "menu", argumentsJSON: #"{"path":"\#(query)"}"#)
        expect(approved.ok, "aprobado corre: \(query)")
        expectEq(screen.pressedTitles, [item], "presiona exactamente lo aprobado: \(query)")
    }
    let exact = FakeScreen([])
    exact.menuTitles = ["Empty Trash…", "Empty"]
    let runner = menuRunner(exact)
    let request = runner.approval(for: menuCall("Finder > Empty Trash…"), said: "")
    expectEq(request?.toolName, "menu", "nombre exacto: hoja")
    if let request { runner.granted(request) }
    _ = await runner.execute(name: "menu", argumentsJSON: #"{"path":"Finder > Empty Trash…"}"#)
    expectEq(exact.pressedTitles, ["Empty Trash…"], "nombre exacto: una vez")
}

@MainActor func testABenignPartialNameStillRuns() async {
    let screen = FakeScreen([])
    screen.menuTitles = ["Sort By", "Group By"]
    let runner = menuRunner(screen)
    expect(runner.approval(for: menuCall("View > Sort"), said: "") == nil, "sin hoja")
    let out = await runner.execute(name: "menu", argumentsJSON: #"{"path":"View > Sort"}"#)
    expect(out.ok, "corre")
    expectEq(screen.pressedTitles, ["Sort By"], "presiona el ítem resuelto")
}

@MainActor func testATicketIsBoundToTheResolvedItem() async {
    let screen = FakeScreen([])
    screen.menuTitles = ["Empty Trash…"]
    let runner = menuRunner(screen)
    let request = runner.approval(for: menuCall("Finder > Empty"), said: "")
    if let request { runner.granted(request) }
    // The menu changed between the sheet and the press.
    screen.menuTitles = ["Empty Cache and Delete History…"]
    let swapped = await runner.execute(name: "menu", argumentsJSON: #"{"path":"Finder > Empty"}"#)
    expect(swapped.output.hasPrefix("approval_required:"), "otro ítem resuelto: el ticket no vale")
    expect(screen.menus.isEmpty, "otro ítem resuelto: no se presiona")
}

// Brief manos-escribir-en-notas, D4 (signed 2026-10-02): quitting an app or
// closing its window or tab loses unsaved work, and `menu` pressed it with no
// sheet because "cerrar"/"close" are cancel words for a dialog's buttons.
// The new family is the menu bar's only: a click on "Cerrar" still backs out.
private let quitOrCloseItems = [
    "Salir de Notas", "Quit Notes", "Cerrar", "Cerrar ventana", "Close Window", "Cerrar pestaña",
    "Close Tab", "Cerrar todo", "Close All", "Forzar salida…", "Force Quit…", "Salir", "Close",
    "Cerrar todas las pestañas", "Cerrar sesiones abiertas",
    // A Mac or an app in another language shows these titles.
    "Notizen beenden", "Fenster schließen", "Quitter Notes", "Fermer la fenêtre", "Sair do Notas",
    "Fechar janela", "Esci da Note", "Chiudi finestra",
]

@MainActor func testQuittingOrClosingFromTheMenuAsksUnlessTheUserSaidIt() {
    for item in quitOrCloseItems {
        expect(HandsGate.menuNeedsTicket(path: ["Archivo", item]), "menu pide hoja: \(item)")
        expectEq(HandsGate.menuVerdict(path: ["Notas", item], said: ""), .ask, "sin palabras (puente): \(item)")
        expectEq(HandsGate.menuVerdict(path: ["Notas", item], said: "abre Notas y escribe hola"), .ask,
                 "no lo pidió: \(item)")
        expectEq(HandsGate.menuVerdict(path: ["Notas", item], said: "cierra la sesión"), .ask,
                 "cerrar sesión no autoriza cerrar ni salir: \(item)")
        expectEq(HandsGate.menuVerdict(path: ["Notas", item], said: "bórralo"), .ask,
                 "otra familia no autoriza: \(item)")
        expect(!HandsGate.clickNeedsTicket(label: item, context: ""), "en un diálogo sigue siendo cancelar: \(item)")
    }
    for said in ["cierra Notas", "salir de Notas", "quit Notes", "close the window", "ciérrala"] {
        expectEq(HandsGate.menuVerdict(path: ["Notas", "Salir de Notas"], said: said), .act, "lo dijo: \(said)")
    }
    // "sal" is also salt: a shopping list must not clear quitting.
    expectEq(HandsGate.menuVerdict(path: ["Notas", "Salir de Notas"], said: "agrega sal a la lista"), .ask,
             "sal de cocina no autoriza salir")
    // The model's partial name is judged by the title the adapter would press.
    expectEq(HandsGate.menuVerdict(path: ["Notas", "Sa"], resolved: "Salir de Notas", said: ""), .ask,
             "parcial resuelto a salir: hoja")
    expectEq(HandsGate.menuVerdict(path: ["Notas", "Sa"], resolved: "Salir de Notas", said: "cierra Notas"), .act,
             "parcial resuelto, y lo dijo: directo")
    expectEq(HandsGate.menuVerdict(path: ["Archivo", "Eliminar"], said: "cierra Notas"), .ask,
             "cerrar no autoriza borrar")
    for path in [["Visualización", "Salir de pantalla completa"], ["View", "Exit Full Screen"],
                 ["Archivo", "Nueva nota"], ["File", "New Note"]] {
        expect(!HandsGate.menuNeedsTicket(path: path), "no cierra nada: \(path.joined(separator: " > "))")
    }
}

@MainActor func testTheBridgeCannotQuitAnAppThroughTheMenu() async {
    let screen = FakeScreen([])
    let runner = menuRunner(screen)
    let request = runner.approval(for: menuCall("Notas > Salir de Notas"), said: "")
    expectEq(request?.toolName, "menu", "salir: hoja con said vacío")
    let unasked = await runner.execute(name: "menu", argumentsJSON: #"{"path":"Notas > Salir de Notas"}"#)
    expect(unasked.output.hasPrefix("approval_required:"), "salir: sin el clic no corre")
    expect(!unasked.output.contains("deletes, pays or sends"), "salir: el motivo no habla de borrar")
    expect(screen.menus.isEmpty, "salir: el menú no se invoca")
}

@MainActor func testAPartialNameThatQuitsAsksAndPressesTheResolvedItemOnce() async {
    let screen = FakeScreen([])
    screen.menuTitles = ["Salir de Notas"]
    let runner = menuRunner(screen)
    let request = runner.approval(for: menuCall("Notas > Sa"), said: "")
    expectEq(request?.toolName, "menu", "parcial: hoja")
    expect(request.map { ChatCopy.approvalDetail(tool: $0.toolName, inputJSON: $0.inputJSON) }?
        .contains("Salir de Notas") == true, "parcial: la hoja nombra el ítem resuelto")
    let unasked = await runner.execute(name: "menu", argumentsJSON: #"{"path":"Notas > Sa"}"#)
    expect(unasked.output.hasPrefix("approval_required:"), "parcial: sin el clic no corre")
    expect(screen.menus.isEmpty, "parcial: no se presiona")
    if let request { runner.granted(request) }
    screen.menuTitles = ["Salir y mantener ventanas"]
    let swapped = await runner.execute(name: "menu", argumentsJSON: #"{"path":"Notas > Sa"}"#)
    expect(swapped.output.hasPrefix("approval_required:"), "otro ítem resuelto: el ticket no vale")
    screen.menuTitles = ["Salir de Notas"]
    _ = await runner.execute(name: "menu", argumentsJSON: #"{"path":"Notas > Sa"}"#)
    expectEq(screen.pressedTitles, ["Salir de Notas"], "con el clic: el ítem resuelto, una vez")
    let again = await runner.execute(name: "menu", argumentsJSON: #"{"path":"Notas > Sa"}"#)
    expect(again.output.hasPrefix("approval_required:"), "el ticket es de un solo uso")

    let benign = FakeScreen([])
    benign.menuTitles = ["Nueva nota"]
    expect(menuRunner(benign).approval(for: menuCall("Archivo > Nueva"), said: "") == nil,
           "parcial a Nueva nota: sin hoja")
}

@MainActor func testSayingItQuitsWithoutTheSheet() async {
    let screen = FakeScreen([])
    let runner = menuRunner(screen)
    expect(runner.approval(for: menuCall("Notas > Salir de Notas"), said: "cierra Notas") == nil,
           "lo dijo: sin hoja")
    let out = await runner.execute(name: "menu", argumentsJSON: #"{"path":"Notas > Salir de Notas"}"#)
    expect(out.ok, "lo dijo: corre")
    expectEq(screen.menus.count, 1, "lo dijo: una invocación")
}

@MainActor func testTheBridgeQuitsOnlyAfterTheSheet() async {
    let arguments = #"{"path":"Notas > Salir de Notas"}"#
    let line = #"{"id":2,"method":"call","params":{"name":"menu","arguments":\#(arguments)}}"#
    let hello = #"{"id":1,"method":"hello","params":{"token":"tok","client":"claude-code","protocol":1}}"#
    let deniedScreen = FakeScreen([])
    let denying = ScriptedApprovals(answer: true)
    denying.setAnswer(false, forTool: "menu")
    let denied = BridgeSession(
        tools: menuRunner(deniedScreen), guard: ParentToolGuard(approvals: denying),
        token: { "tok" }, language: { .en }, accessibility: { true })
    _ = await denied.handle(line: hello)
    let refused = await denied.handle(line: line)
    expect(refused.reply.contains("denied_by_user"), "puente: el no de la hoja frena salir")
    expect(deniedScreen.menus.isEmpty, "puente: sin el clic no sale")

    let okScreen = FakeScreen([])
    let approved = BridgeSession(
        tools: menuRunner(okScreen), guard: ParentToolGuard(approvals: ScriptedApprovals(answer: true)),
        token: { "tok" }, language: { .en }, accessibility: { true })
    _ = await approved.handle(line: hello)
    let done = await approved.handle(line: line)
    expect(done.reply.contains(#""ok":true"#), "puente: con el clic sale")
    expectEq(okScreen.menus.count, 1, "puente: una invocación")
}
