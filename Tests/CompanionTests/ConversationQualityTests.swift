import CompanionCore
import Foundation
import Testing

// Wave 16h-1 (spec 16h section 3): the transcripts of 2026-09-25 are the
// test bench. One filter in front of the voice and the island, spaced
// sentences, a short voice when a card carries the detail, no success line
// without proof, and compound requests that end with the answer.

/// The literals the spec quotes: what the voice read aloud on 2026-09-25.
private enum Leaked {
    static let json = #"{"goal":"busca restaurantes en Safari","context":"el usuario pidió comida"}"#
    static let jsonAfterSentence = #"Voy a buscarlo. {"goal": "abre Notas", "context": ""}"#
    static let instructionEs = "El especialista respondió «restaurantes»; la respuesta está en pantalla. "
        + "Acusa en una línea lo que dice — no añadas detalles que no te dieron, no releas el "
        + "resultado, y no digas que salió bien salvo que la respuesta lo diga."
    static let instructionEn = "The specialist answered «restaurants»; the reply is on screen. "
        + "Acknowledge in one line what it says — do not add details you were not given."
}

private func fixtureTurns(_ kind: String) throws -> [String] {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/transcripts-2026-09-25.txt")
    let content = try String(contentsOf: url, encoding: .utf8)
    return content.split(separator: "\n").compactMap { line in
        guard !line.hasPrefix("#") else { return nil }
        let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
        return parts.count == 2 && parts[0] == kind ? parts[1] : nil
    }
}

// MARK: - Criterion 6: zero leaks

@Test func testTheFourLeaksNeverPassTheSpeechFilter() {
    for leak in [Leaked.json, Leaked.instructionEs, Leaked.instructionEn] {
        expectEq(SpeechFilter.clean(leak), "", "fuga: nada de «\(leak.prefix(24))…» llega a la voz")
    }
    expectEq(SpeechFilter.clean(Leaked.jsonAfterSentence), "Voy a buscarlo.",
             "fuga: la frase previa se queda y el JSON no")
}

@Test func testTheFilterCatchesTheRealJobAnnouncements() {
    for language in [AppLanguage.es, .en] {
        let done = Escalation.jobDoneAnnouncement("abre Notas", language)
        expectEq(SpeechFilter.clean(done), "", "fuga: el aviso de cierre (\(language)) jamás se habla")
        let failed = Escalation.jobFailedAnnouncement("abre Notas", reason: "sin red", language)
        expect(!SpeechFilter.clean(failed).contains("salió bien")
            && !SpeechFilter.clean(failed).lowercased().contains("say it worked"),
               "fuga: el aviso de fallo (\(language)) no deja instrucciones")
        let queued = Escalation.queuedAnnouncement("abre Notas", language)
        expectEq(SpeechFilter.clean(queued), "", "fuga: el aviso de cola (\(language)) jamás se habla")
    }
}

@Test func testTheInstructionSplitAcrossCutsIsDroppedWholeAndProseSurvives() {
    var filter = SpeechFilter()
    expectEq(filter.admit("El especialista respondió «restaurantes»;"), "",
             "cortes: el primer trozo de la instrucción no se habla")
    expectEq(filter.admit("la respuesta está en pantalla."), "",
             "cortes: el resto de la misma frase tampoco")
    expectEq(filter.admit("Acusa en una línea lo que dice."), "", "cortes: ni la segunda frase")
    expectEq(filter.admit("Encontré tres opciones."), "Encontré tres opciones.",
             "cortes: lo que sigue de verdad se habla")
}

@Test func testInternalMarksNeverReachTheVoiceOrTheIsland() {
    expectEq(SpeechFilter.clean("Listo. <steer>no repitas nada</steer> Sigo aquí."), "Listo. Sigo aquí.",
             "marcas: el elemento interno sale entero, con su contenido")
    expectEq(SpeechFilter.clean("Mira. [tarjeta de mapa mostrada en pantalla] Son tres."), "Mira. Son tres.",
             "marcas: el marcador de memoria no se habla")
    expectEq(SpeechFilter.clean("Dime <how_to_reply>en 2 frases</how_to_reply> qué ves."), "Dime qué ves.",
             "marcas: how_to_reply tampoco")
}

@Test func testProseThatMentionsBracesOrQuotesIsNotMistakenForALeak() {
    for prose in [
        "Las llaves { } abren un bloque.", "El especialista es Ana y se ocupa de eso.",
        "Pon [1] junto al título.", "Tienes 3 tarjetas en pantalla.",
        "Una respuesta corta está bien.",
    ] {
        expectEq(SpeechFilter.clean(prose), prose, "sin falsos positivos: «\(prose)»")
    }
}

// MARK: - Criterion 7: spaced sentences

@Test func testSentencesGluedByAJoinGetTheirSpace() {
    expectEq(SpeechFilter.clean("Good afternoon.Keeping it short."), "Good afternoon. Keeping it short.",
             "espacio: afternoon.Keeping")
    expectEq(SpeechFilter.clean("Está en pantalla.No contiene nada."), "Está en pantalla. No contiene nada.",
             "espacio: pantalla.No")
    expectEq(SpeechFilter.clean("¿Listo?Sí, ya."), "¿Listo? Sí, ya.", "espacio: tras interrogación")
    expectEq(SpeechFilter.clean("Terminé.Ñandú corre."), "Terminé. Ñandú corre.", "espacio: mayúscula con tilde")
}

@Test func testDotsThatAreNotSentenceEndsAreLeftAlone() {
    for text in [
        "Entra a atomchat.io y mira.", "Abre https://example.com/Path.Name ahora.",
        "Son 3.200 pesos.", "Guárdalo como hola.pdf en tu Escritorio.", "Usa Node.js para eso.",
        "Vive en los E.U.A. desde entonces.", "Escribe a ana@atomchat.io hoy.",
        "Mira java.lang.String y sigue.", "La versión v2.Beta sale hoy.", "Dr. Smith llega tarde.",
    ] {
        expectEq(SpeechFilter.clean(text), text, "espacio: «\(text)» no se toca")
    }
}

@Test func testTheJoinBetweenRoundsInsertsTheSpaceOnlyAtASentenceEnd() {
    expectEq(SpeechFilter.joiner(after: "Good afternoon.", before: "Keeping it short."), " ",
             "unión: fin de frase + mayúscula")
    expectEq(SpeechFilter.joiner(after: "Entra a atomchat.", before: "io"), "", "unión: trozo de dominio")
    expectEq(SpeechFilter.joiner(after: "Cuesta 3.", before: "200"), "", "unión: decimal partido")
    expectEq(SpeechFilter.joiner(after: "Hola ", before: "Mundo"), "", "unión: ya hay espacio")
    expectEq(SpeechFilter.joiner(after: "", before: "Hola"), "", "unión: nada antes")
    expectEq(SpeechFilter.joiner(after: "Listo.", before: " Sigue"), "", "unión: el trozo trae su espacio")
}

// MARK: - Criterion 3: short voice

private let longAnswer = (1...120).map { "palabra\($0)" }.joined(separator: " ") + "."

@Test func testAHundredAndTwentyWordsWithACardAreSaidInTwentyFiveOrFewer() {
    let said = SpeechBudget.brief(longAnswer, hasCard: true)
    let count = said.split(separator: " ").count
    expect(count <= 25 && count > 0, "voz corta: \(count) palabras, no más de 25")
    expect(!said.hasSuffix("."), "voz corta: sin punto inventado tras un recorte")
}

@Test func testTwoSentencesAtMostWhenACardCarriesTheRest() {
    let said = SpeechBudget.brief("Encontré tres sitios. El primero abre a las ocho. El segundo cierra. Tercero.",
                                  hasCard: true)
    expectEq(said, "Encontré tres sitios. El primero abre a las ocho.", "voz corta: dos frases")
}

@Test func testWithoutACardTheAnswerIsNotCut() {
    expectEq(SpeechBudget.brief(longAnswer, hasCard: false), longAnswer, "sin tarjeta: se dice entera")
}

@Test func testTheBudgetCountsAcrossCutsOfTheSameTurn() {
    var budget = SpeechBudget()
    budget.cardShown = true
    expectEq(budget.admit("Encontré tres."), "Encontré tres.", "presupuesto: primera frase")
    expectEq(budget.admit("El primero abre."), "El primero abre.", "presupuesto: segunda frase")
    expectEq(budget.admit("El tercero cierra."), nil, "presupuesto: la tercera ya no")
}

@Test func testAClauseCutAndItsRestCountAsOneSentence() {
    var budget = SpeechBudget()
    budget.cardShown = true
    expectEq(budget.admit("Claro que sí,"), "Claro que sí,", "presupuesto: cláusula")
    expectEq(budget.admit("encontré tres."), "encontré tres.", "presupuesto: su resto es la misma frase")
    expectEq(budget.admit("Y otra más."), "Y otra más.", "presupuesto: aún cabe la segunda")
}

@Test func testBeforeACardIsShownTheBudgetOnlyCounts() {
    var budget = SpeechBudget()
    let long = (1...30).map { "w\($0)" }.joined(separator: " ") + "."
    expectEq(budget.admit(long), long, "presupuesto: sin tarjeta no recorta")
    budget.cardShown = true
    expectEq(budget.admit("Otra frase."), nil, "presupuesto: con tarjeta, lo ya dicho cuenta")
}

@Test func testEmptyAndBlankInputNeverCrashTheFilters() {
    expectEq(SpeechFilter.clean(""), "", "vacío: clean")
    expectEq(SpeechFilter.clean("  \n "), "", "blancos: clean")
    expectEq(SpeechBudget.brief("", hasCard: true), "", "vacío: brief")
    var budget = SpeechBudget()
    budget.cardShown = true
    expectEq(budget.admit(""), nil, "vacío: admit")
    expectEq(SpeechFilter.clean("Hola 👋 mundo 🌍."), "Hola 👋 mundo 🌍.", "emoji intacto")
    expectEq(SpeechFilter.clean("'; DROP TABLE x;--"), "'; DROP TABLE x;--", "metacaracteres SQL intactos")
}

// MARK: - Criterion 4: "done" only with proof

@Test func testTypeTextWithoutAReadBackNeverClaimsSuccess() {
    let outcome = ParentToolOutcome(ok: true, output: "typed 4 chars", tool: "type_text")
    let es = ParentToolCopy.status("type_text", outcome, .es)
    let en = ParentToolCopy.status("type_text", outcome, .en)
    expect(!es.contains("Escribí") && es.contains("Intenté"), "listo: es dice lo intentado («\(es)»)")
    expect(!en.contains("Typed") && en.contains("Tried"), "listo: en dice lo intentado («\(en)»)")
}

@Test func testTypeTextWithAReadBackMayClaimSuccess() {
    let outcome = ParentToolOutcome(ok: true, output: "typed 4 chars", tool: "type_text", verified: true)
    expectEq(ParentToolCopy.status("type_text", outcome, .es), "Escribí el texto.", "listo: con lectura, éxito es")
    expectEq(ParentToolCopy.status("type_text", outcome, .en), "Typed the text.", "listo: con lectura, éxito en")
}

@Test func testAFailedTypeTextKeepsItsFailureLine() {
    let outcome = ParentToolOutcome(ok: false, output: "refused", tool: "type_text")
    expect(ParentToolCopy.status("type_text", outcome, .es).hasPrefix("No pude escribir"),
           "listo: el fallo sigue igual")
}

// MARK: - Criterion 5: compound requests

private func plan(_ utterance: String, _ action: DecisionAction, args: [String: PlanValue] = [:]) -> Plan {
    Plan(utterance: utterance, action: action, args: args, confidence: 0.95,
         risk: .reversible, disposition: .act)
}

@Test func testTheThreeCompoundTurnsOfTodayHaveTwoStepsAndTheSecondReads() throws {
    let turns = try fixtureTurns("compound")
    expectEq(turns.count, 3, "compuesto: el fixture trae los 3 casos")
    for turn in turns {
        let steps = plan(turn, .openApp, args: ["app": .text("Notes")]).steps
        expectEq(steps.count, 2, "compuesto: «\(turn)» son dos pasos")
        expectEq(steps.first, .act(.openApp), "compuesto: el primero abre")
        expectEq(steps.last, .read, "compuesto: el segundo es leer")
    }
}

@Test func testASingleActionOrAPairOfActionsHasNoReadStep() {
    expectEq(plan("abre Notas", .openApp).steps, [.act(.openApp)], "simple: un paso")
    expectEq(plan("abre Notas y Safari", .openApp).steps, [.act(.openApp)], "dos aperturas: sin lectura")
    expectEq(plan("abre Notas y luego ciérrala", .openApp).steps, [.act(.openApp)], "abrir y cerrar: sin lectura")
    expectEq(plan("gracias por abrir Notas", .none).steps, [], "sin acción: sin pasos")
}

@Test func testACompoundPlanIsNeverAnsweredByTheRouterAlone() {
    let compound = plan("abre Notas y dime qué hay en la primera nota", .openApp, args: ["app": .text("Notes")])
    let step = DecisionRoute.step(for: compound, world: DecisionWorld(), canDelegate: true) { _ in true }
    expectEq(step, .passThrough(.compound), "compuesto: pasa al modelo, que sí puede leer")
    let simple = plan("abre Notas", .openApp, args: ["app": .text("Notes")])
    if case .execute = DecisionRoute.step(for: simple, world: DecisionWorld(), canDelegate: true, systemSupports: { _ in true }) {
    } else {
        expect(false, "simple: el router sigue actuando solo")
    }
}
