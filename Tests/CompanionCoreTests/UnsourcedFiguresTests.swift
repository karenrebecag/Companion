import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// QA 2026-10-18: a results page had headlines and no rate; the reply said
// "18.49 pesos" anyway. The guard is deterministic on purpose: a second model
// judging the first would invent its own figures.

@Test func aFigureNoSourceStatesIsFlagged() {
    let found = UnsourcedFigures.find(
        in: "El dólar está en 18.49 pesos.",
        sources: ["Dólar hoy: noticias y resultados de búsqueda del tipo de cambio"])
    expectEq(found, ["18.49"], "una cifra que ninguna fuente dice se marca")
}

@Test func theSameFigureInAnotherDecimalFormatIsSourced() {
    expectEq(UnsourcedFigures.find(in: "Son 18.49 pesos.", sources: ["1 USD = 18,49 MXN"]), [],
             "18,49 de la fuente y 18.49 de la respuesta son la misma cifra")
    expectEq(UnsourcedFigures.find(in: "Son 18,49 pesos.", sources: ["1 USD = 18.49 MXN"]), [],
             "y al reves")
    expectEq(UnsourcedFigures.find(in: "Cuestan 1234.5 pesos.", sources: ["Precio: 1,234.50 MXN"]), [],
             "los miles con coma y el decimal con punto se leen igual")
}

@Test func yearsDatesTimesAndSmallCountsAreNotFigures() {
    expectEq(UnsourcedFigures.find(
        in: "Desde 2026, al 19/10/2026 a las 10:30 hay 3 opciones y 10 tiendas.",
        sources: ["sin cifras"]), [],
        "un anio, una fecha, una hora y un conteo de diez o menos no se miden")
}

@Test func theUserWordsCountAsASource() {
    expectEq(UnsourcedFigures.find(in: "Sí, 18.49.", sources: ["sin cifras"]), ["18.49"],
             "sin las palabras de la usuaria la cifra es inventada")
    expectEq(UnsourcedFigures.find(in: "Sí, 18.49.", sources: ["sin cifras", "¿Está en 18.49?"]), [],
             "lo que la usuaria dijo tampoco se marca")
}

private func webTurn(tool: String, output: String) -> [Turn] {
    [Turn(role: .assistant, content: "", toolCalls: [ToolCallRef(id: "c1", name: tool, arguments: "{}")]),
     Turn(role: .tool, content: output, toolCallID: "c1")]
}

@Test func theCaveatAppearsOnlyForAnUnsourcedFigureAfterAWebRead() {
    let reply = "El dólar está en 18.49 pesos."
    expectEq(UnsourcedFigures.caveat(
        for: reply, turn: webTurn(tool: "web_search", output: "Noticias del día"),
        userWords: "dólar hoy", language: .es),
        "No encontré esa cifra en las fuentes.",
        "tras leer la web, una cifra sin fuente lleva la nota en español")
    expectEq(UnsourcedFigures.caveat(
        for: reply, turn: webTurn(tool: "read_file", output: "Noticias del día"),
        userWords: "dólar hoy", language: .es), nil,
        "sin herramienta web en el turno no hay gate")
    expectEq(UnsourcedFigures.readsWeb(tool: "browser_read"), true,
             "las herramientas de navegador traen contenido web")
    expectEq(UnsourcedFigures.readsWeb(tool: "read_file"), false,
             "leer un archivo local no es contenido web")
}

// QA 2026-10-19, build 606: the sources had 18.423900, 18.4930, 18,4361 and
// 18.4116; the reply said "≈ 18.42" and the app flagged it anyway.
private let dollarSources = [
    "Dólar hoy 18.423900 MXN", "Tipo de cambio 18.4930", "Cotización 18,4361",
    "XE: 1 USD = 18.44 239159 MXN", "Banco 18.4116",
]

@Test func aRoundedRateIsSourcedByTheFullRateInTheSources() {
    expectEq(UnsourcedFigures.find(
        in: "El dólar está a ≈ 18.42 pesos mexicanos.", sources: dollarSources), [],
        "18.42 es 18.4239 redondeado; el ≈ no exime la cifra")
}

@Test func aCommaDecimalMatchesAPointDecimalAfterRounding() {
    expectEq(UnsourcedFigures.find(in: "Son 18,44 pesos.", sources: ["1 USD = 18.4361 MXN"]), [],
             "la coma decimal de la respuesta redondea igual que el punto de la fuente")
}

@Test func aFigureNoSourceRoundsOrTruncatesToIsStillFlagged() {
    expectEq(UnsourcedFigures.find(in: "Son 18.47 pesos.", sources: dollarSources), ["18.47"],
             "ninguna fuente redondea ni trunca a 18.47, así que lleva la nota")
}

// Rounding and truncation are both accepted: writers round (18.4239 -> 18.42)
// and some truncate (18.46 -> 18.4). Accepting both means a harmless
// truncation never earns a false caveat; the cost is that a truncated
// figure can pass when it is really a rounding error, which is accepted.
@Test func aTruncatedFigureIsSourcedButAFigureOutsideBothRulesIsNot() {
    expectEq(UnsourcedFigures.find(in: "Son 18.4 pesos.", sources: ["18.46"]), [],
             "18.4 es 18.46 truncado")
    expectEq(UnsourcedFigures.find(in: "Son 18.3 pesos.", sources: ["18.46"]), ["18.3"],
             "18.3 no es 18.46 ni redondeado ni truncado")
}

@Test func anIntegerIsSourcedByTheWholePartOfASourceNumber() {
    expectEq(UnsourcedFigures.find(in: "Son 18 pesos.", sources: ["18.46"]), [],
             "18 es la parte entera de 18.46")
    expectEq(UnsourcedFigures.find(in: "Son 19 pesos.", sources: ["18.46"]), ["19"],
             "19 no sale de 18.46 por redondeo ni truncado")
}
