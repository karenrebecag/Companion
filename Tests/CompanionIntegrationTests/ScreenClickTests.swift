import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionServicesTestSupport
import CompanionTestKit
import CompanionUI
import Foundation
import Testing

// Wave 16a-2 (spec §5 filas 2-5). Mirar y pulsar: un id vale solo para el
// último `look` de esa app; "Permitir" va directo, "Eliminar" pide la hoja
// salvo que la usuaria lo pidiera; nunca en otra app que la del turno.

@Test @MainActor func screenClickTests() async {
    await testLookReturnsTheNumberedWindow()
    await testClickPressesTheElementFromTheLastLook()
    await testAStaleIdIsRefused()
    await testClickWithoutALookAsksToLookFirst()
    testADestructiveClickNeedsTheWordOrTheSheet()
    await testADestructiveClickRunsOnlyThroughTheGate()
    await testLookAndClickFollowTheTurnPin()
    await testScrollAndMenuReachTheAdapter()
    testTheSightToolsAreOfferedOnlyWithAScreenAdapter()
}

private let allowSheet = [
    ScanNode(role: "AXStaticText", subrole: "", label: "", value: "google.com quiere tu ubicación",
             secure: false),
    ScanNode(role: "AXButton", subrole: "", label: "Permitir", value: nil, secure: false),
    ScanNode(role: "AXButton", subrole: "", label: "Eliminar", value: nil, secure: false),
]

private func sightRunner(
    _ screen: FakeScreen, target: ScriptedTarget = ScriptedTarget([7]),
    bundle: String = "com.apple.Safari"
) -> ParentToolRunner {
    let hands = FakeHands(field: FocusedField(app: "Safari", pid: 7))
    return ParentToolRunner(
        workspace: FakeWorkspaceOpener(),
        hands: ScreenHands(
            injector: hands, reader: hands, keys: hands, windows: hands,
            trusted: { true }, target: { target.next() }, bundleID: { _ in bundle },
            screen: screen))
}

private func click(_ id: Int) -> ToolCallRef {
    ToolCallRef(id: "c", name: "click", arguments: #"{"id":\#(id)}"#)
}

@MainActor func testLookReturnsTheNumberedWindow() async {
    let runner = sightRunner(FakeScreen(allowSheet))
    let out = await runner.execute(name: "look", argumentsJSON: "{}")
    expect(out.ok, "look: ok")
    expect(out.output.contains(#"[1] button "Permitir""#), "look: el botón con su id")
    expect(out.output.contains("google.com quiere tu ubicación"), "look: el texto")
}

@MainActor func testClickPressesTheElementFromTheLastLook() async {
    let screen = FakeScreen(allowSheet)
    let runner = sightRunner(screen)
    _ = await runner.execute(name: "look", argumentsJSON: "{}")
    let out = await runner.execute(name: "click", argumentsJSON: #"{"id":1}"#)
    expect(out.ok, "click: ok")
    expectEq(screen.clicks.map(\.node), [1], "click: el nodo del id 1")
    expectEq(screen.clicks.map(\.pid), [7], "click: al pid del turno")
    expect(out.output.contains("Permitir"), "click: el modelo sabe qué pulsó")
    let asString = await runner.execute(name: "click", argumentsJSON: #"{"id":"1"}"#)
    expect(asString.ok, "click: un id como texto también vale")
}

@MainActor func testAStaleIdIsRefused() async {
    let screen = FakeScreen(allowSheet)
    let runner = sightRunner(screen)
    _ = await runner.execute(name: "look", argumentsJSON: "{}")
    _ = screen.walk(pid: 7) // the window changed under us: a newer walk exists
    let out = await runner.execute(name: "click", argumentsJSON: #"{"id":1}"#)
    expect(out.output.hasPrefix("stale_id:"), "id viejo: rechazado")
    expect(screen.clicks.isEmpty, "id viejo: nada pulsado")
    let unknown = await runner.execute(name: "click", argumentsJSON: #"{"id":42}"#)
    expect(unknown.output.hasPrefix("stale_id:") || unknown.output.hasPrefix("unknown_id:"),
           "id inexistente: rechazado")
}

@MainActor func testClickWithoutALookAsksToLookFirst() async {
    let screen = FakeScreen(allowSheet)
    let out = await sightRunner(screen).execute(name: "click", argumentsJSON: #"{"id":1}"#)
    expect(out.output.hasPrefix("look_first:"), "sin look: pide mirar")
    expect(screen.clicks.isEmpty, "sin look: nada pulsado")
}

@MainActor func testADestructiveClickNeedsTheWordOrTheSheet() {
    func verdict(_ label: String, _ said: String) -> HandsVerdict {
        HandsGate.clickVerdict(label: label, context: "", said: said)
    }
    expectEq(verdict("Permitir", "acepta el permiso"), .act, "Permitir: directo")
    expectEq(verdict("Allow", "dale"), .act, "Allow: directo")
    expectEq(verdict("Eliminar", "haz lo que dice ahí"), .ask, "Eliminar no pedido: hoja")
    expectEq(verdict("Eliminar", "borra este correo"), .act,
             "Eliminar pedido con otra palabra de borrar: directo")
    expectEq(verdict("Comprar ahora", "dale al botón"), .ask, "Comprar no pedido: hoja")
    expectEq(verdict("Buy now", "buy it"), .act, "Buy pedido: directo")
    expectEq(verdict("Enviar", "envíalo"), .act, "Enviar pedido: directo")
    expectEq(verdict("Página siguiente", "siguiente"), .act, "Página no es pagar")
}

@MainActor func testADestructiveClickRunsOnlyThroughTheGate() async {
    let screen = FakeScreen(allowSheet)
    let runner = sightRunner(screen)
    _ = await runner.execute(name: "look", argumentsJSON: "{}")
    let request = runner.approval(for: click(2), said: "haz lo que dice")
    expectEq(request?.toolName, "click", "Eliminar: hoja")
    expect(request.map { ChatCopy.approvalDetail(tool: $0.toolName, inputJSON: $0.inputJSON) }?
        .contains("Eliminar") == true, "hoja: nombra el botón")
    let unasked = await runner.execute(name: "click", argumentsJSON: #"{"id":2}"#)
    expect(unasked.output.hasPrefix("approval_required:"), "sin la hoja: no se pulsa")
    expect(runner.approval(for: click(2), said: "bórralo") == nil, "pedido: sin hoja")
    let asked = await runner.execute(name: "click", argumentsJSON: #"{"id":2}"#)
    expect(asked.ok, "pedido: pulsa")
    expect(runner.approval(for: click(1), said: "nada") == nil, "Permitir: sin hoja")
}

@MainActor func testLookAndClickFollowTheTurnPin() async {
    let screen = FakeScreen(allowSheet)
    let runner = sightRunner(screen, target: ScriptedTarget([7, 9]))
    runner.beginTurn()
    let out = await runner.execute(name: "look", argumentsJSON: "{}")
    expect(out.output.hasPrefix("target_changed:"), "otra app que la del turno: no mira")
}

@MainActor func testScrollAndMenuReachTheAdapter() async {
    let screen = FakeScreen(allowSheet)
    let runner = sightRunner(screen)
    _ = await runner.execute(name: "look", argumentsJSON: "{}")
    let down = await runner.execute(name: "scroll", argumentsJSON: #"{"direction":"down"}"#)
    expect(down.ok, "scroll: ok")
    expectEq(screen.scrolls.map(\.direction), [.down], "scroll: hacia abajo")
    let bad = await runner.execute(name: "scroll", argumentsJSON: #"{"direction":"sideways"}"#)
    expect(bad.output.hasPrefix("invalid_args:"), "scroll: dirección desconocida")
    let menu = await runner.execute(name: "menu", argumentsJSON: #"{"path":"Archivo > Exportar como PDF…"}"#)
    expect(menu.ok, "menú: ok")
    expectEq(screen.menus, [["Archivo", "Exportar como PDF…"]], "menú: la ruta partida")
}

@MainActor func testTheSightToolsAreOfferedOnlyWithAScreenAdapter() {
    let names = sightRunner(FakeScreen([])).specs(.es).map(\.name)
    for tool in ["look", "click", "scroll", "menu"] {
        expect(names.contains(tool), "con adaptador: \(tool)")
    }
    let without = handsRunner(FakeHands()).specs(.es).map(\.name)
    expect(!without.contains("look"), "sin adaptador: sin look")
}
