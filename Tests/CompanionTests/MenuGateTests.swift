import CompanionCore
@testable import CompanionServices
import CompanionUI
import Foundation
import Testing

// Wave 20c D3 (F3): `menu` goes through the same destructive family and the
// same one-shot ticket as `click`. A menu path ending in Empty Trash, Delete,
// Send... never runs on the model's say-so, from chat, voice or the bridge.

@Test @MainActor func menuGateTests() async {
    testMenuClassifiesItsLastComponentWithClicksClassifier()
    await testADestructiveMenuRunsOnlyThroughTheGate()
    await testANavigationMenuRunsWithoutTheSheet()
    await testTheBridgeCannotRunADestructiveMenuWithoutTheSheet()
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
        let last = path.split(separator: ">").last.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        expect(HandsGate.menuNeedsTicket(path: path.split(separator: ">").map { $0.trimmingCharacters(in: .whitespaces) }),
               "menu destructivo: \(path)")
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
            .contains(path.split(separator: ">").last.map { String($0).trimmingCharacters(in: .whitespaces) } ?? "?") == true,
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
