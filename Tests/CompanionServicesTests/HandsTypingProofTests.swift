import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// type_text into a native app is verified by
// reading the focused element and comparing occurrences of the text before
// and after. When the first route (the AX selected-text attribute) does
// not land, the runner tries the pasteboard once before reporting
// `not_landed`. A field nobody can read keeps the older "not read back"
// line — the voice path still upgrades it from a later `read_focused`.

private func proofHandsRunner(
    _ hands: FakeHands, bundle: String = "com.apple.Notes",
    target: @escaping @Sendable () -> Int32? = { 7 }
) -> ParentToolRunner {
    ParentToolRunner(
        workspace: FakeWorkspaceOpener(),
        hands: ScreenHands(
            injector: hands, reader: hands, keys: hands, windows: hands,
            trusted: { true }, target: target, bundleID: { _ in bundle }))
}

@MainActor func testSetAcceptedAndLandedReportsTypedVerifiedWithNoPaste() async {
    let hands = FakeHands(
        field: FocusedField(app: "Notes", pid: 7),
        text: "")
    let runner = proofHandsRunner(hands)
    let out = await runner.execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
    expect(out.ok, "set ok: ok")
    expect(out.output.contains("(read back, matches)"),
           "set ok: la salida lleva la marca de verificado: \(out.output)")
    expect(out.verified, "set ok: el outcome va marcado verificado")
    expect(hands.pastes.isEmpty, "set ok: no hace falta pegar")
    expectEq(hands.injected.map(\.text), ["hola"], "set ok: el set entró")
    expectEq(hands.injected.map(\.pid), [7], "set ok: al pid de delante")
    expect(!out.output.contains("not_landed"),
           "set ok: nunca el código de no aterrizado: \(out.output)")
}

@MainActor func testSetIgnoredButPasteLandsIsVerifiedAfterOnePaste() async {
    let hands = FakeHands(
        field: FocusedField(app: "Notes", pid: 7),
        text: "")
    hands.ignoresSetText = true
    let runner = proofHandsRunner(hands)
    let out = await runner.execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
    expect(out.ok, "set ignorado, paste ok: ok")
    expect(out.output.contains("(read back, matches)"),
           "set ignorado, paste ok: verificado: \(out.output)")
    expect(out.verified, "set ignorado, paste ok: marcado verificado")
    expectEq(hands.pastes.count, 1, "set ignorado, paste ok: exactamente un paste")
    expectEq(hands.pastes.map(\.text), ["hola"], "set ignorado, paste ok: el texto del paste")
    expectEq(hands.pastes.map(\.pid), [7], "set ignorado, paste ok: al pid de delante")
}

@MainActor func testBothIgnoredReportsNotLandedWithoutATypedCount() async {
    let hands = FakeHands(
        field: FocusedField(app: "Notes", pid: 7),
        text: "")
    hands.ignoresSetText = true
    hands.ignoresPaste = true
    let runner = proofHandsRunner(hands)
    let out = await runner.execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
    expect(!out.ok, "ambos ignorados: falla")
    expect(out.output.hasPrefix("not_landed:"),
           "ambos ignorados: prefijo del código real: \(out.output)")
    expect(!out.output.contains("typed "),
           "ambos ignorados: nunca un conteo de tipeo: \(out.output)")
    expect(!out.verified, "ambos ignorados: el outcome no está verificado")
    expectEq(hands.pastes.count, 1, "ambos ignorados: el paste se intenta una vez")
}

@MainActor func testAFieldThatCannotBeReadStaysNotReadBack() async {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7), text: nil)
    let runner = proofHandsRunner(hands)
    let out = await runner.execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
    expect(out.ok, "sin base: sigue siendo ok")
    expect(out.output.contains("(not read back)"),
           "sin base: la salida lleva la marca vieja: \(out.output)")
    expect(!out.verified, "sin base: el outcome no está verificado")
    expect(hands.pastes.isEmpty, "sin base: no se intenta pegar")
    expectEq(out.typedBefore, nil, "sin base: el typedBefore queda nil")
}

@MainActor func testTextAlreadyPresentIsNotMistakenForLanding() async {
    let hands = FakeHands(
        field: FocusedField(app: "Notes", pid: 7),
        text: "si")
    hands.ignoresSetText = true
    hands.ignoresPaste = true
    let runner = proofHandsRunner(hands)
    let out = await runner.execute(name: "type_text", argumentsJSON: #"{"text":"si"}"#)
    expect(!out.ok, "ya estaba: falla, no verifica")
    expect(out.output.hasPrefix("not_landed:"),
           "ya estaba: prefijo real: \(out.output)")
    expect(!out.verified, "ya estaba: sin verificación")
    expectEq(hands.pastes.count, 1, "ya estaba: el paste se intentó una vez")
}

@MainActor func testSecureFieldStillRefusesAndNeverInjectsOrPastes() async {
    let hands = FakeHands(
        field: FocusedField(app: "Notes", pid: 7, secure: true),
        text: "")
    let runner = proofHandsRunner(hands)
    let out = await runner.execute(name: "type_text", argumentsJSON: #"{"text":"secreto"}"#)
    expect(!out.ok, "seguro: rechazado")
    expect(out.output.hasPrefix("secure_field:"),
           "seguro: el código no cambia: \(out.output)")
    expect(hands.injected.isEmpty, "seguro: nada inyectado")
    expect(hands.pastes.isEmpty, "seguro: nada pegado")
}

@Test @MainActor func handsTypingProofTests() async {
    await testSetAcceptedAndLandedReportsTypedVerifiedWithNoPaste()
    await testSetIgnoredButPasteLandsIsVerifiedAfterOnePaste()
    await testBothIgnoredReportsNotLandedWithoutATypedCount()
    await testAFieldThatCannotBeReadStaysNotReadBack()
    await testTextAlreadyPresentIsNotMistakenForLanding()
    await testSecureFieldStillRefusesAndNeverInjectsOrPastes()
    await testAFirstRouteThatWasAlreadyAPasteIsNotPastedAgain()
    await testAValueThatShowsUpOnTheSecondReadIsVerifiedWithoutAPaste()
    await testAFieldThatStopsAnsweringAfterTypingIsNeverPasted()
    await testLongTextThatChangedTheFieldIsNeverPastedTwice()
    await testAFieldTheAppRewroteIsNeverPastedTwice()
    await testPasteFailuresKeepTheirCodes()
}

@MainActor func testAFirstRouteThatWasAlreadyAPasteIsNotPastedAgain() async {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7), text: "")
    // The injector fell back to the pasteboard on its own and the field
    // still shows nothing: a second paste would only repeat what failed.
    hands.injectResult = .injected(4, via: .paste)
    let out = await proofHandsRunner(hands).execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
    expect(out.output.hasPrefix("not_landed:"), "ya pegado: not_landed: \(out.output)")
    expect(hands.pastes.isEmpty, "ya pegado: no se pega de nuevo")
}

@MainActor func testAValueThatShowsUpOnTheSecondReadIsVerifiedWithoutAPaste() async {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7), text: "")
    hands.landsAfterReads = 1
    let out = await proofHandsRunner(hands).execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
    expect(out.verified, "tarde: la segunda lectura lo encuentra: \(out.output)")
    expect(hands.pastes.isEmpty, "tarde: no se pega lo que ya entro")
}

@MainActor func testAFieldThatStopsAnsweringAfterTypingIsNeverPasted() async {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7), text: "")
    hands.unreadableAfterReads = 1
    let out = await proofHandsRunner(hands).execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
    expect(out.ok && out.output.contains(TypedProof.unverifiedNote),
           "sin relectura: no verificado, nunca not_landed: \(out.output)")
    expect(hands.pastes.isEmpty, "sin relectura: no se pega a ciegas")
}

@MainActor func testLongTextThatChangedTheFieldIsNeverPastedTwice() async {
    // Longer than the clipped read: the proof cannot see it, but the field did change.
    let long = String(repeating: "palabra ", count: 90)
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7), text: "")
    let arguments = "{\"text\":\"\(long)\"}"
    let out = await proofHandsRunner(hands).execute(name: "type_text", argumentsJSON: arguments)
    expect(out.ok && out.output.contains(TypedProof.unverifiedNote),
           "largo: no verificado, no not_landed: \(out.output)")
    expect(hands.pastes.isEmpty, "largo: el campo cambio, no se pega otra vez")
}

@MainActor func testAFieldTheAppRewroteIsNeverPastedTwice() async {
    // The set landed but the app stored its own version, so the text never
    // matches; the field still changed, which is not "ignored".
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7), text: "")
    hands.rewritesSetTextTo = "Hola mundo."
    let out = await proofHandsRunner(hands).execute(name: "type_text", argumentsJSON: #"{"text":"hola  mundo!"}"#)
    expect(hands.pastes.isEmpty, "reescrito: el campo ya no es el de antes, no se pega: \(out.output)")
    expect(out.ok && out.output.contains(TypedProof.unverifiedNote), "reescrito: no verificado: \(out.output)")
}

@MainActor func testPasteFailuresKeepTheirCodes() async {
    let cases: [(InjectionResult, String)] = [
        (.failed(.needsAccessibility), "needs_accessibility:"),
        (.failed(.fieldGone), "target_changed:"),
        (.failed(.refused), "not_landed:"),
    ]
    for (result, prefix) in cases {
        let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7), text: "")
        hands.ignoresSetText = true
        hands.pasteResult = result
        let out = await proofHandsRunner(hands).execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
        expect(out.output.hasPrefix(prefix), "pegado \(result): \(prefix) \(out.output)")
    }
}
