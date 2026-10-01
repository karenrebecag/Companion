import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Wave 16h-1, review round: what the filter must NOT swallow, state across
// cuts, spacing before openers, an honest budget, and the wider compound rule.

private func plan(_ utterance: String, _ action: DecisionAction) -> Plan {
    Plan(utterance: utterance, action: action, args: [:], confidence: 0.95,
         risk: .reversible, disposition: .act)
}

// MARK: - M1: a quoted marker never silences an effect

@Test func testASentenceThatAnnouncesAnEffectSurvivesAQuotedMarker() {
    for text in [
        "Envié tu mensaje a Ana: 'no repitas nada'.",
        "Anoté «nunca digas que salió bien» en tu nota.",
        "Guardé el archivo que dice acusa en una línea lo que pasó.",
        "I sent Ana the message: say it worked unless it fails.",
    ] {
        expectEq(SpeechFilter.clean(text), text, "efecto: «\(text)» se sigue diciendo")
    }
}

@Test func testTheInstructionIsStillDroppedWhenItOpensTheSentence() {
    expectEq(SpeechFilter.clean("Acusa en una línea lo que dice."), "", "instrucción al inicio: fuera")
    expectEq(SpeechFilter.clean("«Notas» quedó en cola detrás del encargo de ahora."), "",
             "instrucción con la meta citada al inicio: fuera")
}

@Test func testADroppedFragmentEatsAtMostTheNextSentence() {
    var filter = SpeechFilter()
    expectEq(filter.admit("Acusa en una línea"), "", "arrastre: el fragmento se cae")
    expectEq(filter.admit("Primero pan. Luego leche. Después huevos."), "Luego leche. Después huevos.",
             "arrastre: solo la oración inmediata, no el resto")
    expectEq(filter.admit("Otra cosa. Y otra."), "Otra cosa. Y otra.", "arrastre: el estado se limpia")
}

@Test func testAListAfterADroppedFragmentIsKept() {
    var filter = SpeechFilter()
    expectEq(filter.admit("Acusa en una línea"), "", "lista: el fragmento se cae")
    expectEq(filter.admit("1. Pan 2. Leche"), "1. Pan 2. Leche", "lista: un marcador de lista no es continuación")
}

@Test func testALongSentenceAfterADroppedFragmentIsNotSwallowed() {
    var filter = SpeechFilter()
    _ = filter.admit("Acusa en una línea")
    let long = String(repeating: "palabra ", count: 40) + "final."
    expectEq(filter.admit(long), long.trimmingCharacters(in: .whitespaces), "tope: lo largo no es continuación")
}

// MARK: - M2: <tag> state across cuts

@Test func testAnInternalElementOpenInOneCutAndClosedInAnotherIsNeverSpoken() {
    var filter = SpeechFilter()
    expectEq(filter.admit("Listo. <steer>no repitas nada de"), "Listo.", "marca: lo previo se habla")
    expectEq(filter.admit("lo anterior y sigue por aquí."), "", "marca: el interior no se habla")
    expectEq(filter.admit("ahora</steer> Sigo aquí."), "Sigo aquí.", "marca: tras el cierre se habla")
}

@Test func testAnElementThatNeverClosesStopsSwallowingAtTheCap() {
    var filter = SpeechFilter()
    _ = filter.admit("<steer>")
    var last = ""
    for _ in 0..<12 { last = filter.admit(String(repeating: "hola ", count: 40) + "fin.") }
    expect(!last.isEmpty, "tope: un tag sin cierre no calla el turno para siempre")
}

// MARK: - M3: space before any opener

@Test func testASpaceGoesBeforeOpenersAndEllipsis() {
    expectEq(SpeechFilter.clean("Bien...Luego vamos."), "Bien... Luego vamos.", "apertura: puntos suspensivos")
    expectEq(SpeechFilter.clean("Hola.¿Qué tal?"), "Hola. ¿Qué tal?", "apertura: ¿")
    expectEq(SpeechFilter.clean("Listo.¡Vamos!"), "Listo. ¡Vamos!", "apertura: ¡")
    expectEq(SpeechFilter.clean("Dijo.«Hola» y se fue."), "Dijo. «Hola» y se fue.", "apertura: «")
    expectEq(SpeechFilter.clean("Dijo.\"Hola\" ya."), "Dijo. \"Hola\" ya.", "apertura: comillas")
}

@Test func testTheJoinerAlsoUnderstandsOpeners() {
    expectEq(SpeechFilter.joiner(after: "Bien.", before: "¿Qué?"), " ", "unión: ¿")
    expectEq(SpeechFilter.joiner(after: "Bien...", before: "Luego"), " ", "unión: puntos suspensivos")
    expectEq(SpeechFilter.joiner(after: "Dijo.", before: "«Hola»"), " ", "unión: «")
    expectEq(SpeechFilter.joiner(after: "Cuesta 3.", before: "200"), "", "unión: los dígitos siguen fuera")
}

// MARK: - M4: an honest budget

@Test func testTheBudgetCountsEverySentenceOfACut() {
    var budget = SpeechBudget()
    budget.cardShown = true
    expectEq(budget.admit("Uno dos. Tres cuatro. Cinco seis."), "Uno dos. Tres cuatro.",
             "presupuesto: tres frases en un corte son tres")
    expectEq(budget.admit("Siete."), nil, "presupuesto: ya no cabe otra")
}

@Test func testATrimmedSentenceStopsAtItsLastClauseNotMidPhrase() {
    var budget = SpeechBudget()
    budget.cardShown = true
    let filler = (1...30).map { "relleno\($0)" }.joined(separator: " ")
    expectEq(budget.admit("Encontré tres sitios cerca de aquí, \(filler)."), "Encontré tres sitios cerca de aquí.",
             "recorte: en la última cláusula completa")
}

@Test func testATrimmedSentenceWithNoClauseAddsNoInventedPeriod() {
    let said = SpeechBudget.brief((1...120).map { "palabra\($0)" }.joined(separator: " ") + ".", hasCard: true)
    expect(said.split(separator: " ").count <= 25 && !said.hasSuffix("."),
           "recorte: sin cláusula, palabras justas y sin punto inventado")
}

// MARK: - L1: a read in any clause

@Test func testAReadInTheFirstClauseIsCompoundToo() {
    expect(plan("dime qué hora es y abre Safari", .openApp).steps.contains(.read),
           "compuesto: la lectura va primero")
}

@Test func testALooseLeadIsNotAReadRequest() {
    expectEq(plan("abre Spotify y cual quieras", .openApp).steps, [.act(.openApp)], "falso positivo: «cual quieras»")
    expectEq(plan("abre Notas y what ever", .openApp).steps, [.act(.openApp)], "falso positivo: «what ever»")
    expect(plan("abre Notas y cuál es la primera", .openApp).steps.contains(.read), "«cuál es» sí lee")
    expect(plan("open Notes and what's in the first one", .openApp).steps.contains(.read), "«what's» sí lee")
}
