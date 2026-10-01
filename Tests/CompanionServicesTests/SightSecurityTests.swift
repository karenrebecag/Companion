import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// Security review 16 (BLOCK, 2026-09-25): C1 un campo seguro sin etiqueta
// tomaba sus propios caracteres como subtítulo; C2 la puerta de clicks
// destructivos se saltaba con iconos sin etiqueta, "Move to Bin", otros
// idiomas y el "Sí" de un diálogo de borrar; H1 abrir una app dejaba el
// turno sin pin para cualquier app que saliera después.

@Test @MainActor func sightSecurityTests() async {
    testASecureFieldNeverReadsItsCaption()
    testAnUnlabeledControlAlwaysAsks()
    testDestructiveWordsBeyondSpanishAndEnglish()
    testAConfirmationInsideADestructiveDialogAsks()
    testFamiliesAreNotShared()
    await testTheDialogContextReachesTheGate()
    await testAfterOpeningTheTurnRepinsToTheOpenedApp()
}

@MainActor func testASecureFieldNeverReadsItsCaption() {
    var asked = false
    let label = AXScreen.label(
        title: "", description: "", placeholder: "", role: "AXTextField", secure: true,
        caption: { asked = true; return "hunter2" })
    expect(!asked, "C1: un campo seguro nunca lee a sus hijos")
    expectEq(label, "", "C1: sin subtítulo")
    let button = AXScreen.label(
        title: "", description: "", placeholder: "", role: "AXButton", secure: false,
        caption: { "Enviar" })
    expectEq(button, "Enviar", "C1: un botón sí toma su subtítulo")
}

@MainActor func testAnUnlabeledControlAlwaysAsks() {
    expectEq(HandsGate.clickVerdict(label: "", context: "", said: "dale"), .ask,
             "C2: sin etiqueta, hoja")
    expect(HandsGate.clickNeedsTicket(label: "  ", context: ""), "C2: sin etiqueta, pase")
}

@MainActor func testDestructiveWordsBeyondSpanishAndEnglish() {
    for label in ["Move to Bin", "Löschen", "Supprimer", "Excluir", "Cancella", "Kaufen",
                  "Acheter", "Senden", "Envoyer"] {
        expectEq(HandsGate.clickVerdict(label: label, context: "", said: "haz lo que dice"), .ask,
                 "C2: \(label) pide hoja")
    }
    expectEq(HandsGate.clickVerdict(label: "Allow", context: "", said: ""), .act, "Allow: directo")
}

@MainActor func testAConfirmationInsideADestructiveDialogAsks() {
    let dialog = "¿Eliminar este correo? No se puede deshacer."
    expectEq(HandsGate.clickVerdict(label: "Sí", context: dialog, said: "dale que sí"), .ask,
             "C2: el Sí de un diálogo de borrar pide hoja")
    expectEq(HandsGate.clickVerdict(label: "Sí", context: dialog, said: "sí, bórralo"), .act,
             "C2: pedido con la palabra, directo")
    expectEq(HandsGate.clickVerdict(label: "Cancelar", context: dialog, said: ""), .act,
             "C2: cancelar nunca es destructivo")
    expectEq(HandsGate.clickVerdict(label: "Permitir", context: "google.com quiere usar tu ubicación",
                                    said: ""), .act, "C2: el permiso de ubicación sigue directo")
}

@MainActor func testFamiliesAreNotShared() {
    expectEq(HandsGate.clickVerdict(label: "Publicar", context: "", said: "envíalo"), .ask,
             "M: enviar no autoriza publicar")
    expectEq(HandsGate.clickVerdict(label: "Suscribirse", context: "", said: "cómpralo"), .ask,
             "M: comprar no autoriza suscribirse")
}

@MainActor func testTheDialogContextReachesTheGate() async {
    let nodes = [
        ScanNode(role: "AXButton", subrole: "", label: "Nuevo", value: nil, secure: false),
        ScanNode(role: "AXStaticText", subrole: "", label: "", value: "¿Eliminar este correo?",
                 secure: false, group: 1),
        ScanNode(role: "AXButton", subrole: "", label: "Sí", value: nil, secure: false, group: 1),
    ]
    let scan = ScreenScan.build(
        ScreenWalk(nodes: nodes, partial: false, window: "Mail", generation: 1), app: "Mail")
    expect(scan.element(id: 2)?.context.contains("Eliminar") == true, "C2: el Sí lleva su diálogo")
    expectEq(scan.element(id: 1)?.context, "", "C2: fuera de un diálogo, sin contexto")

    let screen = FakeScreen(nodes)
    let hands = FakeHands(field: FocusedField(app: "Mail", pid: 7))
    let runner = ParentToolRunner(
        workspace: FakeWorkspaceOpener(),
        hands: ScreenHands(injector: hands, reader: hands, keys: hands, windows: hands,
                           trusted: { true }, target: { 7 }, bundleID: { _ in "com.apple.mail" },
                           screen: screen))
    _ = await runner.execute(name: "look", argumentsJSON: "{}")
    let yes = ToolCallRef(id: "c", name: "click", arguments: #"{"id":2}"#)
    expect(runner.approval(for: yes, said: "dale que sí") != nil, "C2: el runner pide la hoja")
    let unasked = await runner.execute(name: "click", argumentsJSON: #"{"id":2}"#)
    expect(unasked.output.hasPrefix("approval_required:"), "C2: sin hoja no se pulsa")
}

@MainActor func testAfterOpeningTheTurnRepinsToTheOpenedApp() async {
    let hands = FakeHands(field: FocusedField(app: "Safari", pid: 9))
    // Spoke in 7, opened Safari (9), typed there; then a notification app
    // (13) came to the front.
    let runner = handsRunner(hands, target: ScriptedTarget([7, 9, 9, 13]))
    runner.beginTurn()
    _ = await runner.execute(name: "open_app", argumentsJSON: #"{"name":"Safari"}"#)
    let first = await runner.execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
    expect(first.ok, "H1: la app abierta recibe el texto")
    let second = await runner.execute(name: "type_text", argumentsJSON: #"{"text":"otra"}"#)
    expect(second.output.hasPrefix("target_changed:"), "H1: una tercera app no hereda el turno")
    expectEq(hands.injected.count, 1, "H1: nada escrito en la tercera")
}
