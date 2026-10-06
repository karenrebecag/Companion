import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Wave 15f-1, the pure scanner behind the mouth's JSON guard.

@Test @MainActor func handoffInTextTests() {
    testThePureObjectBecomesAHandoff()
    testProseAroundTheObjectPassesThrough()
    testAnOpenCandidateIsHeldAcrossPieces()
    testBracesInsideStringsDoNotCloseTheObject()
    testAClosedObjectWithoutAGoalIsDropped()
    testAnUnclosedCandidateIsDroppedAtTheEnd()
    testALoneBraceAtTheEndIsProse()
    testNonCandidateBracesAreProse()
    testADoubledBraceNeverSpeaksTheObject()
    testEmptyAndUnicodeInput()
    testACardFenceKeepsItsData()
}

@MainActor func testThePureObjectBecomesAHandoff() {
    var scan = HandoffInText()
    let step = scan.feed(#"{"goal":"x","context":"y"}"#)
    expectEq(step.speakable, "", "scanner: nada hablable")
    expectEq(step.handoff, Handoff(goal: "x", context: "y"), "scanner: handoff")
    expectEq(step.handoffChars, 26, "scanner: tamaño del objeto")
    expectEq(scan.finish(), HandoffInText.Step(), "scanner: nada pendiente")
}

@MainActor func testProseAroundTheObjectPassesThrough() {
    var scan = HandoffInText()
    let step = scan.feed("Voy.\n {\"goal\": \"a\"} Listo")
    expectEq(step.speakable, "Voy.\n  Listo", "scanner: la prosa de antes y después pasa")
    expectEq(step.handoff?.goal, "a", "scanner: con goal")
}

@MainActor func testAnOpenCandidateIsHeldAcrossPieces() {
    var scan = HandoffInText()
    expectEq(scan.feed("Ok {").speakable, "Ok ", "scanner: la llave abierta espera")
    expectEq(scan.feed("  ").speakable, "", "scanner: blancos tras la llave esperan")
    let mid = scan.feed(#""goal": "b"#)
    expectEq(mid.speakable, "", "scanner: candidato retenido")
    expect(mid.handoff == nil, "scanner: aún sin cerrar")
    expectEq(scan.feed(#""}"#).handoff?.goal, "b", "scanner: al cerrar, handoff")
}

@MainActor func testBracesInsideStringsDoNotCloseTheObject() {
    var scan = HandoffInText()
    let step = scan.feed(#"{"goal":"usa } y \" {","context":"{x}"}"#)
    expectEq(step.handoff, Handoff(goal: #"usa } y " {"#, context: "{x}"),
             "scanner: llaves y comillas escapadas dentro de strings")
    var nested = HandoffInText()
    expectEq(nested.feed(#"{"goal":"n","meta":{"a":1}}"#).handoff?.goal, "n",
             "scanner: objetos anidados")
}

@MainActor func testAClosedObjectWithoutAGoalIsDropped() {
    var scan = HandoffInText()
    let step = scan.feed(#"Hola {"name":"x"} fin"#)
    expectEq(step.speakable, "Hola  fin", "scanner: JSON sin goal no se habla")
    expect(step.handoff == nil, "scanner: y no escala")
    expectEq(step.droppedChars, 12, "scanner: se cuenta")
    var blank = HandoffInText()
    expectEq(blank.feed(#"{"goal":"   "}"#).droppedChars, 14, "scanner: goal vacío = descartado")
    var broken = HandoffInText()
    expectEq(broken.feed(#"{"goal" x}"#).droppedChars, 10, "scanner: inválido = descartado")
}

@MainActor func testAnUnclosedCandidateIsDroppedAtTheEnd() {
    var scan = HandoffInText()
    _ = scan.feed(#"{"goal":"a"#)
    let end = scan.finish()
    expectEq(end.speakable, "", "scanner: truncado no se habla")
    expectEq(end.droppedChars, 10, "scanner: se cuenta al final")
    expectEq(scan.finish(), HandoffInText.Step(), "scanner: finish es idempotente")
}

@MainActor func testALoneBraceAtTheEndIsProse() {
    var scan = HandoffInText()
    expectEq(scan.feed("abre {").speakable, "abre ", "scanner: retenida")
    expectEq(scan.finish().speakable, "{", "scanner: sin comilla, al final es prosa")
}

@MainActor func testNonCandidateBracesAreProse() {
    var scan = HandoffInText()
    // Code review 2026-09-25 (LOW-1): the second brace of "{{" may open a
    // candidate, so it waits; at the end of the stream it is prose again.
    let fed = scan.feed("llaves { } y {x} y {{").speakable
    expectEq(fed + scan.finish().speakable, "llaves { } y {x} y {{",
             "scanner: llave sin comilla detrás es prosa")
}

@MainActor func testADoubledBraceNeverSpeaksTheObject() {
    var scan = HandoffInText()
    let step = scan.feed(#"Voy. {{"goal":"x"}}"#)
    let end = scan.finish()
    expectEq(step.handoff?.goal, "x", "LOW-1: el objeto interior es el candidato")
    expect(!(step.speakable + end.speakable).contains("goal"),
           "LOW-1: el objeto nunca se habla")
    expectEq(step.speakable + end.speakable, "Voy. {}", "LOW-1: la llave exterior es prosa")
}

@MainActor func testEmptyAndUnicodeInput() {
    var scan = HandoffInText()
    expectEq(scan.feed(""), HandoffInText.Step(), "scanner: vacío")
    let step = scan.feed(#"Sí ñandú {"goal":"añade ✓ 日本"}"#)
    expectEq(step.speakable, "Sí ñandú ", "scanner: unicode en prosa")
    expectEq(step.handoff?.goal, "añade ✓ 日本", "scanner: unicode en goal")
}

@MainActor func testACardFenceKeepsItsData() {
    var scan = HandoffInText()
    let pieces = ["Ventas:\n\n``", "`companion:chart\n{\"kind\":\"bar\",", "\"labels\":[\"Ene\"]}\n```\nListo"]
    let steps = pieces.map { scan.feed($0) } + [scan.finish()]
    expectEq(steps.map(\.display).joined(), pieces.joined(), "scanner: el hilo guarda la tarjeta entera")
    expectEq(steps.map(\.speakable).joined(), "Ventas:\n\n\nListo", "scanner: la voz no lee la tarjeta")
    expectEq(MarkdownSplitter.cardFences(pieces.joined()),
             "```companion:chart\n{\"kind\":\"bar\",\"labels\":[\"Ene\"]}\n```",
             "hilo: la tarjeta se guarda entera aparte de lo dicho")
    expectEq(MarkdownSplitter.proseWithoutCards(pieces.joined()).contains("companion"), false,
             "voz: lo dicho no arrastra el encabezado de la tarjeta")
    var plain = HandoffInText()
    expectEq(plain.feed(#"Ok {"goal":"x"}"#).handoff?.goal, "x", "scanner: fuera de un bloque sigue detectando")
}
