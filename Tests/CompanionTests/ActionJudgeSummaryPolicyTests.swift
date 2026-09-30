@testable import CompanionCore
import Foundation
import Testing

// 16q-3a, round 2: a summary marked complete must not hide a destination.
// Every rule is tested on both sides, so neither a loosened nor a tightened
// rule can pass: incomplete, and still complete.

private func summary(_ json: String) -> ActionSummary { ActionSummary.make(argumentsJSON: json) }

private func expectIncomplete(_ json: String, _ why: String) {
    expect(!summary(json).isComplete, "16q-3a politica: \(why) es incompleto")
}

private func expectComplete(_ json: String, _ why: String) {
    expect(summary(json).isComplete, "16q-3a politica: \(why) sigue completo")
}

private func quoted(_ text: String) -> String { "\"\(text)\"" }

// MARK: - Objects

@Test func aNestedObjectAtAnyKeyMakesTheSummaryIncomplete() {
    expectIncomplete(#"{"o":{"a":1}}"#, "un objeto")
    expectIncomplete(#"{"o":{}}"#, "un objeto vacio")
    expectIncomplete(#"{"a":"x","m":"y","z":{"to":"evil@x.test"}}"#, "un objeto en la ultima clave")
    expectIncomplete(#"{"a":{"to":"evil@x.test"},"z":"y"}"#, "un objeto en la primera clave")
    expectEq(summary(#"{"o":{"a":1,"b":2}}"#).values["o"], .text("<object: 2 keys>"),
             "16q-3a politica: el marcador de objeto se conserva")
    expectComplete(#"{"a":"x","b":null,"c":true,"d":3,"e":[]}"#, "sin objetos")
}

// MARK: - Lists

@Test func aListThatIsCutOrNotPlainShortTextsMakesTheSummaryIncomplete() {
    expectIncomplete(#"{"to":["a","b","c","d","e","f"]}"#, "una lista cortada")
    expectIncomplete(#"{"to":["a",1]}"#, "un item que no es texto")
    expectIncomplete(#"{"to":["a",null]}"#, "un item null")
    expectIncomplete(#"{"to":["a",["b"]]}"#, "un item que es lista")
    expectIncomplete("{\"to\":[\"a\",\"\(String(repeating: "u", count: 81))\"]}", "un item sobre el tope")
    expectIncomplete("{\"to\":[\"\(String(repeating: "hola ", count: 20))\"]}", "un item de prosa sobre el tope")
    expectComplete(#"{"to":["a","b","c","d","e"]}"#, "5 items exactos")
    expectComplete(#"{"to":["a"]}"#, "un item")
    expectComplete(#"{"to":[]}"#, "una lista vacia")
    expectComplete("{\"to\":[\"\(String(repeating: "u", count: 80))\"]}", "un item de 80")
}

// MARK: - Numbers

@Test func aNumberADoubleWouldRoundMakesTheSummaryIncomplete() {
    let rounded = [
        "9007199254740993", "18446744073709551617", "12345678901234567890", "-9007199254740993",
        "1.00000000000000000001", "0.1000000000000000055511151231257827", "123456789012345678e1",
    ]
    for number in rounded { expectIncomplete("{\"id\":\(number)}", "el numero \(number), que un Double redondea") }
    let exact = [
        "9007199254740992", "3", "-1.5e2", "0.10", "1E5", "1e+5", "-0", "0", "0.5", "1.0", "100", "1e-5", "1E-05",
        "0.000", "2.50", "-7",
    ]
    for number in exact { expectComplete("{\"n\":\(number)}", "el numero \(number), que un Double guarda exacto") }
    expectEq(summary(#"{"n":1e+5}"#).values["n"], .number(100_000), "16q-3a politica: el valor mostrado es el del lexema")
}

// MARK: - Keys

@Test func aShownKeyThatDiffersFromTheRawKeyMakesTheSummaryIncomplete() {
    expectIncomplete("{\"to\u{200B}\":\"a\"}", "una clave con ancho cero")
    expectIncomplete("{\"t\u{202E}o\":\"a\"}", "una clave con bidi")
    expectIncomplete(#"{"to\u0001":"a"}"#, "una clave con control")
    expectIncomplete("{\"\(String(repeating: "k", count: 41))\":\"a\"}", "una clave de 41 que se corta a 40")
    expectIncomplete("{\"\u{FEFF}to\":\"a\"}", "una clave con BOM al inicio")
    expectComplete("{\"\(String(repeating: "k", count: 40))\":\"a\"}", "una clave de 40")
    expectComplete("{\"destino_é😀\":\"a\"}", "una clave con acento y emoji")
    expectComplete("{\"to\":\"a\",\"cc\":\"b\"}", "claves limpias")
}

// MARK: - Text

@Test func aLongTextWithoutWhitespaceIsATokenAndMakesTheSummaryIncomplete() {
    let url = "https://evil.example/" + String(repeating: "a", count: 80)
    expectIncomplete("{\"url\":\"\(url)\"}", "una URL larga")
    expectIncomplete("{\"k\":\"\(String(repeating: "x", count: 81))\"}", "81 letras seguidas")
    expectIncomplete("{\"k\":\"\(String(repeating: "\u{1F600}", count: 81))\"}", "81 emoji seguidos")
    let zalgo = String(repeating: "a" + String(repeating: "\u{0301}", count: 15), count: 80)
    expectIncomplete("{\"k\":\"\(zalgo)\"}", "un texto que rebasa el tope de escalares")
    expectEq(summary("{\"k\":\"\(url)\"}").values["k"], .text("<text: \(url.count) chars>"),
             "16q-3a politica: el marcador de longitud se conserva")
    expectComplete("{\"k\":\"\(String(repeating: "x", count: 80))\"}", "80 letras seguidas")
}

@Test func aLongTextWithWhitespaceIsProseAndStaysComplete() {
    let prose = String(repeating: "hola ", count: 30)
    let cases: [(String, String)] = [
        (prose, "prosa con espacios"),
        (String(repeating: "hola\\n", count: 30), "prosa con saltos de linea"),
        (String(repeating: "hola\\t", count: 30), "prosa con tabuladores"),
        (String(repeating: "x", count: 80) + " y", "81 caracteres con un espacio"),
    ]
    for (text, why) in cases {
        let s = summary("{\"body\":\(quoted(text))}")
        expect(s.isComplete, "16q-3a politica: \(why) sigue completo")
        guard case .text(let shown)? = s.values["body"] else {
            Issue.record("16q-3a politica: \(why) debia viajar como texto")
            continue
        }
        expect(shown.hasPrefix("<text: "), "16q-3a politica: \(why) viaja como longitud, no como cuerpo")
    }
    expectEq(summary("{\"body\":\"\(prose)\"}").values["body"], .text("<text: 150 chars>"),
             "16q-3a politica: D2, el cuerpo viaja solo como longitud")
}

// MARK: - Through the local rules

@Test func everyIncompleteReasonFailsClosedThroughTheLocalRules() {
    let incomplete = [
        #"{"o":{"a":1}}"#, #"{"to":["a","b","c","d","e","f"]}"#, #"{"to":["a",1]}"#, #"{"id":9007199254740993}"#,
        "{\"to\u{200B}\":\"a\"}", "{\"u\":\"\(String(repeating: "x", count: 100))\"}",
    ]
    for json in incomplete {
        let action = ProposedAction.app(toolName: "app:slack:slack-send-message", label: "Send",
                                        group: .crearYCambiar, argumentsJSON: json)
        expectEq(action.flatMap(ActionJudgeLocalRules.verdict(for:)), .failed(.invalid),
                 "16q-3a politica: \(json.prefix(30)) sale failed(invalid) sin preguntar al modelo")
    }
    let prose = ProposedAction.app(toolName: "app:slack:slack-send-message", label: "Send",
                                   group: .crearYCambiar, argumentsJSON: "{\"body\":\"\(String(repeating: "hola ", count: 30))\"}")
    expect(prose.map { ActionJudgeLocalRules.verdict(for: $0) == nil } == true,
           "16q-3a politica: la prosa si se le pregunta al modelo")
}
