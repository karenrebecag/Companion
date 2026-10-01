import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// Wave 10c 3A.4, capa 2: `misprint_repair`. La lista es la de json_repair,
// una heurística por test; lo "super broken" es nil, nunca un invento.
@Test @MainActor func toolArgumentsTests() {
    testValidJSONIsReturnedAsIs()
    testCodeFenceIsStripped()
    testTrailingCommaIsRepaired()
    testUnclosedObjectIsClosed()
    testSingleQuotesBecomeDouble()
    testUnquotedKeysAreQuoted()
    testPythonLiteralsAreTranslated()
    testMissingCommaBetweenPairsIsRepaired()
    testGarbageIsNil()
    testBracesInsideStringsDoNotCutTheObject()
}

private func str(_ obj: [String: Any]?, _ key: String) -> String? { obj?[key] as? String }

@MainActor func testValidJSONIsReturnedAsIs() {
    let obj = ToolArguments.parse(#"{"path":"a.md","n":1,"ok":true}"#)
    expectEq(str(obj, "path"), "a.md", "válido: tal cual")
    expectEq(obj?["n"] as? Int, 1, "válido: número")
    expectEq(obj?["ok"] as? Bool, true, "válido: bool")
    expect(ToolArguments.parse("{}")?.isEmpty == true, "válido: objeto vacío es objeto, no nil")
}

@MainActor func testCodeFenceIsStripped() {
    expectEq(str(ToolArguments.parse("```json\n{\"path\":\"a.md\"}\n```"), "path"), "a.md", "fence: json")
    expectEq(str(ToolArguments.parse("Here you go: {\"path\":\"a.md\"} hope it helps"), "path"), "a.md",
             "texto alrededor: se toma el objeto")
}

@MainActor func testTrailingCommaIsRepaired() {
    expectEq(str(ToolArguments.parse(#"{"path":"a.md",}"#), "path"), "a.md", "coma final: objeto")
    let arr = ToolArguments.parse(#"{"paths":["a","b",],}"#)?["paths"] as? [String]
    expectEq(arr, ["a", "b"], "coma final: array")
}

@MainActor func testUnclosedObjectIsClosed() {
    expectEq(str(ToolArguments.parse(#"{"path":"a.md""#), "path"), "a.md", "sin cerrar: llave")
    let nested = ToolArguments.parse(#"{"opts":{"depth":2"#)?["opts"] as? [String: Any]
    expectEq(nested?["depth"] as? Int, 2, "sin cerrar: anidado")
    expectEq(str(ToolArguments.parse(#"{"path":"a.md"#), "path"), "a.md", "sin cerrar: la cadena también")
}

@MainActor func testSingleQuotesBecomeDouble() {
    expectEq(str(ToolArguments.parse("{'path': 'a.md'}"), "path"), "a.md", "comillas simples")
    expectEq(str(ToolArguments.parse("{command: 'rm -rf x'}"), "command"), "rm -rf x",
             "comillas simples: también con clave sin comillas")
    expectEq(str(ToolArguments.parse(#"{"note":"it's fine"}"#), "note"), "it's fine",
             "un apóstrofo dentro de un JSON válido no se toca")
}

@MainActor func testUnquotedKeysAreQuoted() {
    let obj = ToolArguments.parse(#"{path: "a.md", depth: 2}"#)
    expectEq(str(obj, "path"), "a.md", "claves sin comillas: string")
    expectEq(obj?["depth"] as? Int, 2, "claves sin comillas: número")
}

@MainActor func testPythonLiteralsAreTranslated() {
    let obj = ToolArguments.parse(#"{"a": True, "b": False, "c": None, "d": NULL}"#)
    expectEq(obj?["a"] as? Bool, true, "python: True")
    expectEq(obj?["b"] as? Bool, false, "python: False")
    expect(obj?["c"] is NSNull, "python: None")
    expect(obj?["d"] is NSNull, "mayúsculas: NULL")
    expectEq(str(ToolArguments.parse(#"{"s":"None of it"}"#), "s"), "None of it",
             "python: dentro de una cadena no se toca")
}

@MainActor func testMissingCommaBetweenPairsIsRepaired() {
    let obj = ToolArguments.parse("{\"path\": \"a.md\"\n \"content\": \"x\"}")
    expectEq(str(obj, "path"), "a.md", "coma faltante: primer par")
    expectEq(str(obj, "content"), "x", "coma faltante: segundo par")
}

@MainActor func testGarbageIsNil() {
    expect(ToolArguments.parse("") == nil, "basura: vacío")
    expect(ToolArguments.parse("sure, reading the file now") == nil, "basura: prosa")
    expect(ToolArguments.parse("[1,2,3]") == nil, "basura: un array no es un objeto de argumentos")
    expect(ToolArguments.parse("{{{{") == nil, "basura: super broken → nil")
}

/// Code review 2026-09-05 (ALTO): el recorte por llaves y la coma faltante
/// no sabían de cadenas: `{"path": "notes on {formatting} here` perdía
/// "here" y devolvía un objeto MAL en vez de nil. Reparar es sintaxis
/// alrededor de las cadenas, nunca dentro.
@MainActor func testBracesInsideStringsDoNotCutTheObject() {
    expectEq(str(ToolArguments.parse(#"{"path": "notes on {formatting} here"#), "path"),
             "notes on {formatting} here", "llaves: la cadena entera, aunque no cierre")
    let two = ToolArguments.parse("{\"a\": \"say \\\"x\\\": 1\" \"b\": 2}")
    expectEq(str(two, "a"), "say \"x\": 1", "comilla escapada: el valor no se toca")
    expectEq(two?["b"] as? Int, 2, "comilla escapada: y la coma faltante se repara")
    expectEq(str(ToolArguments.parse(#"{"content": "x = {a: 1}", "path": "a.js",}"#), "content"),
             "x = {a: 1}", "llaves: código dentro de un valor sobrevive a la coma final")
    expectEq(str(ToolArguments.parse(#"{"content": "a, b, c}", "path": "p"}"#), "path"), "p",
             "llave dentro de cadena: el objeto real es el de fuera")
}
