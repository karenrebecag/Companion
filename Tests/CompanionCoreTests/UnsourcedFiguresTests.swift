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

@Test func theCaveatAppearsOnlyForAnUnsourcedFigureAfterAWebRead() {
    let reply = "El dólar está en 18.49 pesos."
    expectEq(UnsourcedFigures.caveat(
        for: reply, turnTools: ["web_search", "read_url"], sources: ["Noticias del día"],
        userWords: "dólar hoy", language: .es),
        "No encontré esa cifra en las fuentes.",
        "tras leer la web, una cifra sin fuente lleva la nota en español")
    expectEq(UnsourcedFigures.caveat(
        for: reply, turnTools: ["read_file"], sources: ["Noticias del día"],
        userWords: "dólar hoy", language: .es), nil,
        "sin herramienta web en el turno no hay gate")
    expectEq(UnsourcedFigures.readsWeb(tool: "browser_read"), true,
             "las herramientas de navegador traen contenido web")
    expectEq(UnsourcedFigures.readsWeb(tool: "read_file"), false,
             "leer un archivo local no es contenido web")
}
