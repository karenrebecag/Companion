import CompanionCore
@testable import CompanionServices
import CompanionUI
import Foundation
import Testing

// Wave 20c D5 (M3). A click ticket is the user's yes to ONE control of ONE
// look. Ids expire on the next look, so the ticket has to expire with them:
// bound to node + label + scan generation, never to the bare id number.

private func nodes(_ second: String) -> [ScanNode] {
    [
        ScanNode(role: "AXStaticText", subrole: "", label: "", value: "google.com quiere tu ubicación",
                 secure: false),
        ScanNode(role: "AXButton", subrole: "", label: "Permitir", value: nil, secure: false),
        ScanNode(role: "AXButton", subrole: "", label: second, value: nil, secure: false),
    ]
}

private func runner(_ screen: FakeScreen) -> ParentToolRunner {
    let hands = FakeHands(field: FocusedField(app: "Safari", pid: 7))
    return ParentToolRunner(
        workspace: FakeWorkspaceOpener(),
        hands: ScreenHands(
            injector: hands, reader: hands, keys: hands, windows: hands,
            trusted: { true }, target: { 7 }, bundleID: { _ in "com.apple.Safari" }, screen: screen))
}

private let clickTwo = ToolCallRef(id: "c", name: "click", arguments: #"{"id":2}"#)

@Test @MainActor func clickTicketBindingTests() async {
    await testTicketParkedAtOneScanIsRefusedAfterANewScanRenumbers()
    await testTicketParkedAtOneScanIsRefusedAfterANewScanOfTheSameControl()
    await testTicketStillWorksWithinTheScanItWasParkedFor()
}

@MainActor func testTicketParkedAtOneScanIsRefusedAfterANewScanRenumbers() async {
    let screen = FakeScreen(nodes("Eliminar"))
    let runner = runner(screen)
    _ = await runner.execute(name: "look", argumentsJSON: "{}")
    let request = runner.approval(for: clickTwo, said: "haz lo que dice")
    expect(request != nil, "M3: Eliminar pide la hoja")
    if let request { runner.granted(request) }
    // The window changed: id 2 is now a different destructive control.
    screen.nodes = nodes("Enviar")
    _ = await runner.execute(name: "look", argumentsJSON: "{}")
    let outcome = await runner.execute(name: "click", argumentsJSON: #"{"id":2}"#)
    expect(outcome.output.hasPrefix("approval_required:"), "M3: el ticket de Eliminar no pulsa Enviar")
    expectEq(screen.clicks.count, 0, "M3: nada pulsado")
}

@MainActor func testTicketParkedAtOneScanIsRefusedAfterANewScanOfTheSameControl() async {
    let screen = FakeScreen(nodes("Eliminar"))
    let runner = runner(screen)
    _ = await runner.execute(name: "look", argumentsJSON: "{}")
    if let request = runner.approval(for: clickTwo, said: "haz lo que dice") { runner.granted(request) }
    _ = await runner.execute(name: "look", argumentsJSON: "{}")
    let outcome = await runner.execute(name: "click", argumentsJSON: #"{"id":2}"#)
    expect(outcome.output.hasPrefix("approval_required:"), "M3: un look nuevo expira el ticket")
    expectEq(screen.clicks.count, 0, "M3: falla cerrado")
}

@MainActor func testTicketStillWorksWithinTheScanItWasParkedFor() async {
    let screen = FakeScreen(nodes("Eliminar"))
    let runner = runner(screen)
    _ = await runner.execute(name: "look", argumentsJSON: "{}")
    if let request = runner.approval(for: clickTwo, said: "haz lo que dice") { runner.granted(request) }
    let outcome = await runner.execute(name: "click", argumentsJSON: #"{"id":2}"#)
    expect(outcome.ok, "M3: mismo scan, mismo control: pulsa")
    expectEq(screen.clicks.count, 1, "M3: una pulsacion")
}
