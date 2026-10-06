import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// An editable field with no text is still a field, not "no field". The
// reader used to return nil on an empty String, which made read_focused
// say no_focused_field right after a correct click and left type_text
// with no baseline to verify against. The line on the approval sheet
// for a command app is empty in the same case, so the sheet would
// advertise a Return whose context it could not show.

@Test @MainActor func handsReadFocusedTests() async {
    await testAnEmptyEditableFieldReadsAsEmptyField()
    await testNoFocusedFieldStillReturnsNoFocusedField()
    await testASecureFieldIsStillRefusedWithoutBeingRead()
    await testAFieldWithTextReadsTheTextAsBefore()
    await testAnEmptyCommandAppFieldApprovalSheetHasNoLine()
    await testACommandAppFieldWithTextStillShowsItsLine()
}

private func readRunner(
    _ hands: FakeHands, bundle: String = "com.apple.Notes"
) -> ParentToolRunner {
    handsRunner(hands, bundle: bundle)
}

@MainActor func testAnEmptyEditableFieldReadsAsEmptyField() async {
    let hands = FakeHands(
        field: FocusedField(app: "Notes", pid: 7),
        text: "")
    let runner = readRunner(hands)
    let out = await runner.execute(name: "read_focused", argumentsJSON: "{}")
    expect(out.ok, "campo vacio: ok")
    expectEq(out.output, "(empty field)", "campo vacio: dice que esta vacio: \(out.output)")
    expectEq(out.fieldPID, 7, "campo vacio: lleva el pid del campo")
    expectEq(hands.reads, 1, "campo vacio: el lector respondio una vez")
}

@MainActor func testNoFocusedFieldStillReturnsNoFocusedField() async {
    let hands = FakeHands(field: nil, text: "")
    let runner = readRunner(hands)
    let out = await runner.execute(name: "read_focused", argumentsJSON: "{}")
    expect(!out.ok, "sin campo: falla")
    expect(out.output.hasPrefix("no_focused_field:"),
           "sin campo: el codigo no cambia: \(out.output)")
    expectEq(hands.reads, 0, "sin campo: el lector no se llamo")
}

@MainActor func testASecureFieldIsStillRefusedWithoutBeingRead() async {
    let hands = FakeHands(
        field: FocusedField(app: "Notes", pid: 7, secure: true),
        text: "")
    let runner = readRunner(hands)
    let out = await runner.execute(name: "read_focused", argumentsJSON: "{}")
    expect(!out.ok, "seguro: rechazado")
    expect(out.output.hasPrefix("secure_field:"),
           "seguro: el codigo no cambia: \(out.output)")
    expectEq(hands.reads, 0, "seguro: el lector nunca leyo el contenido")
}

@MainActor func testAFieldWithTextReadsTheTextAsBefore() async {
    let hands = FakeHands(
        field: FocusedField(app: "Notes", pid: 7),
        text: "hola mundo")
    let runner = readRunner(hands)
    let out = await runner.execute(name: "read_focused", argumentsJSON: "{}")
    expect(out.ok, "con texto: ok")
    expectEq(out.output, "hola mundo", "con texto: el texto se lee tal cual: \(out.output)")
}

@MainActor func testAnEmptyCommandAppFieldApprovalSheetHasNoLine() async {
    let hands = FakeHands(
        field: FocusedField(app: "Terminal", pid: 7),
        text: "")
    let runner = readRunner(hands, bundle: "com.apple.Terminal")
    let call = ToolCallRef(id: "r1", name: "press_key", arguments: #"{"key":"return"}"#)
    guard let request = runner.approval(for: call, said: "dale enter") else {
        expect(false, "terminal con enter pedido: la hoja existe")
        return
    }
    // The runner reads the prompt line below the caret to show what Return
    // runs; an empty editable field has no line, so the sheet must not
    // advertise an empty one — the field being empty IS the context.
    expect(!request.inputJSON.contains("\"line\""),
           "terminal vacio: la hoja no lleva una linea vacia: \(request.inputJSON)")
}

@MainActor func testACommandAppFieldWithTextStillShowsItsLine() async {
    let hands = FakeHands(
        field: FocusedField(app: "Terminal", pid: 7),
        text: "ls -la")
    let runner = readRunner(hands, bundle: "com.apple.Terminal")
    let call = ToolCallRef(id: "r2", name: "press_key", arguments: #"{"key":"return"}"#)
    guard let request = runner.approval(for: call, said: "dale enter") else {
        expect(false, "terminal con texto: la hoja existe")
        return
    }
    expect(request.inputJSON.contains("\"line\"") && request.inputJSON.contains("ls -la"),
           "terminal con texto: la hoja muestra la linea: \(request.inputJSON)")
}
