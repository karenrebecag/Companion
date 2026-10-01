import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// Code review 2026-09-25 (HIGH-A). The language gate dropped ANY confident
// English sentence once the conversation was in Spanish, so English the
// reply was quoting — an error message, a build line, a translation — was
// cut out whole. The drop is now narrowed to reasoning leaks, checked with
// the real system recognizer.

@Test @MainActor func mouthQuoteTests() {
    testAQuotedErrorAfterAColonIsSpoken()
    testAShortEnglishBuildLineIsSpoken()
    testATranslationIsSpoken()
    testALeadInFromAnEarlierCutOrSentenceQuotes()
    testTheReasoningLeakStillDrops()
    testTheUserReasoningOpenerDrops()
}

private func spanishGate(heard: String = "abre la terminal por favor") -> MouthLanguageGate {
    MouthLanguageGate(language: .es, recognizer: NaturalLanguageRecognizer(), heard: heard)
}

@MainActor func testAQuotedErrorAfterAColonIsSpoken() {
    var gate = spanishGate(heard: "qué dice el error de la terminal")
    let quoted = "Dice: Cannot find module react in this project."
    expectEq(gate.admit(quoted), quoted, "HIGH-A: el error citado tras 'Dice:' se dice")
    expectEq(gate.dropped, [], "HIGH-A: nada descartado")
}

@MainActor func testAShortEnglishBuildLineIsSpoken() {
    var gate = spanishGate(heard: "cómo terminó la compilación del proyecto")
    _ = gate.admit("Terminó bien la compilación del proyecto.")
    let line = "Build succeeded with zero warnings."
    expectEq(gate.admit(line), line, "HIGH-A: una línea corta en inglés sin apertura de razonamiento se dice")
    expectEq(gate.dropped, [], "HIGH-A: nada descartado")
}

@MainActor func testATranslationIsSpoken() {
    var gate = spanishGate(heard: "cómo se dice buenos días en inglés")
    let answer = "Se dice así: Good morning, how are you today?"
    expectEq(gate.admit(answer), answer, "HIGH-A: la traducción se dice")
    expectEq(gate.dropped, [], "HIGH-A: nada descartado")
}

@MainActor func testALeadInFromAnEarlierCutOrSentenceQuotes() {
    var colon = spanishGate(heard: "qué error salió en la terminal")
    _ = colon.admit("La terminal muestra este mensaje:")
    let error = "Cannot find the module named react anywhere in this project."
    expectEq(colon.admit(error), error, "HIGH-A: los dos puntos al final del corte anterior citan")

    var keyword = spanishGate(heard: "qué error salió en la terminal")
    let reply = "Te leo el error de la terminal. Cannot find the module named react anywhere in this project."
    expectEq(keyword.admit(reply), reply, "HIGH-A: una frase previa con 'error' cita la siguiente")

    var quotes = spanishGate()
    let marked = "El mensaje es «Cannot find the module named react anywhere in this project»."
    expectEq(quotes.admit(marked), marked, "HIGH-A: entre comillas se dice")
    expectEq(colon.dropped + keyword.dropped + quotes.dropped, [], "HIGH-A: nada descartado")
}

@MainActor func testTheReasoningLeakStillDrops() {
    var gate = spanishGate()
    expectEq(gate.admit("Listo. We need to answer why not opening terminal first. Ya está."),
             "Listo. Ya está.", "HIGH-A: el razonamiento sigue saliendo")
    expectEq(gate.dropped, ["We need to answer why not opening terminal first."],
             "HIGH-A: la fuga queda registrada")
    var apostrophe = spanishGate()
    _ = apostrophe.admit("Listo, ya abrí la terminal.")
    expect(apostrophe.admit("Actually, we don't need to open anything else here.") == nil,
           "HIGH-A: un apóstrofo no es una comilla; la fuga sale igual")
}

@MainActor func testTheUserReasoningOpenerDrops() {
    var gate = spanishGate(heard: "qué hora es ahora mismo")
    _ = gate.admit("Son las tres de la tarde.")
    expect(gate.admit("The user asked for the time.") == nil,
           "HIGH-A: 'The user…' dentro de una respuesta en español sale")
    expectEq(gate.dropped, ["The user asked for the time."], "HIGH-A: registrada")
}
