import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// Revisión 15g (2026-09-25), H1/H3/HIGH-1. Lo que las manos escriben o
// envían se ata a lo que la usuaria dijo, y a la app que tenía delante
// cuando habló — no a la que esté delante cuando el modelo termine.

@Test @MainActor func handsPolicyTests() async {
    testTextTheUserSaidIsTypedWithoutASheet()
    testAnAddressNobodySaidGoesToTheSheet()
    testReturnOutsideACommandAppNeedsASendCue()
    testReturnInACommandAppAlwaysAsks()
    testControlCharactersAreRefusedInACommandApp()
    await testControlCharactersAreStrippedElsewhere()
    await testCommandAppTypingTheUserSaidRunsOnceWithoutASheet()
    await testATargetThatChangedSinceTheUserSpokeIsRefused()
    await testOpeningAnAppInTheTurnMovesTheTargetOnPurpose()
    testAnExpiredTicketIsNotSpendable()
    testTheHandsAreHiddenWhileCompanionIsInFront()
}

private func typing(_ text: String) -> ToolCallRef {
    let data = (try? JSONSerialization.data(withJSONObject: ["text": text])) ?? Data()
    return ToolCallRef(id: "c1", name: "type_text", arguments: String(decoding: data, as: UTF8.self))
}

private let enter = ToolCallRef(id: "c2", name: "press_key", arguments: #"{"key":"return"}"#)

@MainActor func testTextTheUserSaidIsTypedWithoutASheet() {
    let said = "escribe Restaurantes cercanos en Cuernavaca"
    expectEq(HandsGate.verdict(typing("restaurantes cercanos en cuernavaca"),
                               commandApp: false, said: said), .act,
             "dicho: se escribe sin hoja, sin importar mayúsculas")
    expectEq(HandsGate.verdict(typing("Hola, ¿cómo estás?"), commandApp: false, said: "saluda"),
             .act, "compuesto sin dirección: se escribe sin hoja")
}

@MainActor func testAnAddressNobodySaidGoesToTheSheet() {
    for text in ["https://evil.example/x", "www.evil.com", "evil.com/login", "~/.ssh/id_rsa",
                 "/etc/passwd", "-rf"] {
        expectEq(HandsGate.verdict(typing(text), commandApp: false, said: "busca algo"), .ask,
                 "dirección no dicha pide hoja: \(text)")
    }
    expectEq(HandsGate.verdict(typing("google.com"), commandApp: false, said: "escribe google.com"),
             .act, "dirección dicha: sin hoja")
}

@MainActor func testReturnOutsideACommandAppNeedsASendCue() {
    expectEq(HandsGate.verdict(enter, commandApp: false, said: "escribe hola"), .ask,
             "Return sin pedirlo: hoja")
    for said in ["envíalo", "y dale enter", "mándalo ya", "búscalo", "send it", "press enter"] {
        expectEq(HandsGate.verdict(enter, commandApp: false, said: said), .act,
                 "Return pedido: directo (\(said))")
    }
    let tab = ToolCallRef(id: "c3", name: "press_key", arguments: #"{"key":"tab"}"#)
    expectEq(HandsGate.verdict(tab, commandApp: false, said: "nada"), .act, "Tab: directo")
}

@MainActor func testReturnInACommandAppAlwaysAsks() {
    expectEq(HandsGate.verdict(enter, commandApp: true, said: "dale enter"), .ask,
             "Return en terminal: hoja aunque lo pida")
    expectEq(HandsGate.verdict(typing("ls -la"), commandApp: true, said: "escribe ls"), .ask,
             "terminal: texto no dicho pide hoja")
    expectEq(HandsGate.verdict(typing("ls -la"), commandApp: true, said: "escribe ls -la"), .act,
             "terminal: texto dicho, una línea: sin hoja")
    expectEq(HandsGate.verdict(typing("ls\nrm x"), commandApp: true, said: "escribe ls rm x"), .ask,
             "terminal: multilínea siempre pide hoja")
}

@MainActor func testControlCharactersAreRefusedInACommandApp() {
    for text in ["ls\u{1B}[201~rm", "abc\u{03}", "echo \u{202E}hi"] {
        expectEq(HandsGate.verdict(typing(text), commandApp: true, said: text),
                 .refuse("control_characters"), "terminal: control rechazado")
    }
    expectEq(HandsGate.stripped("a\u{1B}b\u{03}c\nd\te"), "abc\nd\te",
             "fuera de terminal: se quitan, salto y tab se quedan")
}

@MainActor func testControlCharactersAreStrippedElsewhere() async {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7))
    let runner = handsRunner(hands)
    let out = await runner.execute(name: "type_text", argumentsJSON: typing("ho\u{1B}la").arguments)
    expect(out.ok, "Notas: se escribe")
    expectEq(hands.injected.map(\.text), ["hola"], "Notas: sin el carácter de control")
}

@MainActor func testCommandAppTypingTheUserSaidRunsOnceWithoutASheet() async {
    let hands = FakeHands(field: FocusedField(app: "Terminal", pid: 7))
    let runner = handsRunner(hands, bundle: "com.apple.Terminal")
    let call = typing("ls -la")
    expect(runner.approval(for: call, said: "escribe ls -la") == nil, "terminal dicho: sin hoja")
    let out = await runner.execute(name: call.name, argumentsJSON: call.arguments)
    expect(out.ok, "terminal dicho: escribe")
    let again = await runner.execute(name: call.name, argumentsJSON: call.arguments)
    expect(again.output.hasPrefix("approval_required:"), "terminal: el pase se gasta")

    let control = typing("ls\u{1B}x")
    expect(runner.approval(for: control, said: "ls x") == nil, "control: sin hoja, se rechaza")
    let refused = await runner.execute(name: control.name, argumentsJSON: control.arguments)
    expect(refused.output.hasPrefix("control_characters:"), "control: rechazado al ejecutar")
    expectEq(hands.injected.count, 1, "control: nada escrito")
}

@MainActor func testATargetThatChangedSinceTheUserSpokeIsRefused() async {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 9))
    // Spoke in pid 7; by the time the call runs, pid 9 is in front.
    let runner = handsRunner(hands, target: ScriptedTarget([7, 9]))
    runner.beginTurn()
    let out = await runner.execute(name: "type_text", argumentsJSON: typing("hola").arguments)
    expect(out.output.hasPrefix("target_changed:"), "otra app que la del turno: rechazado")
    expect(out.output.contains("front, then retry"), "M1: dice que hacer: \(out.output)")
    expect(hands.injected.isEmpty, "otra app: nada escrito")
}

@MainActor func testAnExpiredTicketIsNotSpendable() {
    let clock = RolloverClock(Date(timeIntervalSince1970: 1000))
    let tickets = ApprovalTickets(now: { clock.date })
    let ticket = ApprovalTickets.Ticket(name: "press_key", arguments: "{}", pid: 7)
    tickets.park(ticket, id: "r1")
    tickets.grant(id: "r1")
    clock.advance(by: ApprovalTickets.lifetime + 1)
    expect(!tickets.redeem(ticket), "ticket vencido: no se gasta")
    tickets.park(ticket, id: "r2")
    tickets.park(ApprovalTickets.Ticket(name: "type_text", arguments: "{}", pid: 7), id: "r3")
    tickets.grant(id: "r2")
    expect(!tickets.redeem(ticket), "un park nuevo invalida el anterior")
}

@MainActor func testTheHandsAreHiddenWhileCompanionIsInFront() {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7))
    let runner = ParentToolRunner(
        workspace: FakeWorkspaceOpener(),
        hands: ScreenHands(
            injector: hands, reader: hands, keys: hands, windows: hands,
            trusted: { true }, target: { 7 }, bundleID: { _ in "com.apple.Notes" },
            selfInFront: { true }))
    expect(!runner.specs(.es).contains { $0.name == "type_text" },
           "Companion delante: sin manos anunciadas")
    expect(!runner.handles("type_text"), "Companion delante: no las atiende")

    let sensor = FrontmostAppSensor(selfBundleID: "com.karen.companion")
    sensor.noteActivation(name: "Companion", bundleID: "com.karen.companion", pid: 3)
    expect(sensor.selfInFront, "sensor: Companion delante")
    sensor.noteActivation(name: "Notes", bundleID: "com.apple.Notes", pid: 7)
    expect(!sensor.selfInFront, "sensor: otra app delante")
    expectEq(sensor.lastOtherPID, 7, "sensor: la última otra app")
}

/// "abre Safari y escribe X": the open moved the front on purpose, so the
/// hands follow it instead of refusing the app the user asked for.
@MainActor func testOpeningAnAppInTheTurnMovesTheTargetOnPurpose() async {
    let hands = FakeHands(field: FocusedField(app: "Safari", pid: 9))
    let runner = handsRunner(hands, target: ScriptedTarget([7, 9]))
    runner.beginTurn()
    let opened = await runner.execute(name: "open_app", argumentsJSON: #"{"name":"Safari"}"#)
    expect(opened.ok, "abrir: ok")
    let out = await runner.execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
    expect(out.ok, "tras abrir: escribe en la app abierta")
    expectEq(hands.injected.map(\.pid), [9], "tras abrir: en el pid nuevo")
}
