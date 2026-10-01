@testable import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// 16q-3a, round 2: the strict JSON reader, table-driven. The summary, the
// version and the verdict parser all trust this one reader, so every row
// asserts the decoded value, not just "it parsed".

private func parse(_ text: String) -> JSONValue? { JSONValue.parse(Data(text.utf8)) }

private func parse(bytes: [UInt8]) -> JSONValue? { JSONValue.parse(Data(bytes)) }

private func nested(_ open: String, _ close: String, levels: Int, core: String = "") -> String {
    String(repeating: open, count: levels) + core + String(repeating: close, count: levels)
}

private func checkTable(_ rows: [(input: String, expected: JSONValue?)], _ what: String) {
    for row in rows {
        expectEq(parse(row.input), row.expected, "16q-3a lector: \(what) \(row.input.debugDescription)")
    }
}

// MARK: - Escapes

@Test func readerDecodesEveryEscape() {
    let rows: [(input: String, expected: JSONValue?)] = [
        (#""\u0041""#, .string("A")),
        (#""\u00e9""#, .string("é")),
        (#""\u00E9""#, .string("é")),
        (#""\ud83d\ude00""#, .string("😀")),
        (#""\uD83D\uDE00""#, .string("😀")),
        (#""\b""#, .string("\u{08}")),
        (#""\f""#, .string("\u{0C}")),
        (#""\r""#, .string("\r")),
        (#""\n""#, .string("\n")),
        (#""\t""#, .string("\t")),
        (#""\/""#, .string("/")),
        (#""\\""#, .string("\\")),
        (#""\"""#, .string("\"")),
        (#""\u0000""#, .string("\u{0}")),
        (#""a\u0041b""#, .string("aAb")),
        (#""😀é""#, .string("😀é")),
    ]
    checkTable(rows, "escape")
}

@Test func readerRejectsBrokenEscapes() {
    let rows: [(input: String, expected: JSONValue?)] = [
        (#""\ud83d\n""#, nil),
        (#""\ud83dA""#, nil),
        (#""\ud83d\u0041""#, nil),
        (#""\ud83d\ud83d""#, nil),
        (#""\ud83d\nDE00""#, nil),
        (#""\ud83dxxDE00""#, nil),
        (#""\ud83d""#, nil),
        (#""\ude00""#, nil),
        (#""\ude00\ud83d""#, nil),
        (#""\u12"#, nil),
        (#""\u12""#, nil),
        (#""\u"#, nil),
        (#""\"#, nil),
        (#""\uZZZZ""#, nil),
        (#""\q""#, nil),
        (#""\U0041""#, nil),
    ]
    checkTable(rows, "escape roto")
}

// MARK: - Control characters

@Test func readerRefusesRawControlsInsideStrings() {
    for byte in [UInt8(0x00), 0x01, 0x09, 0x0A, 0x1F] {
        expect(parse(bytes: [0x22, byte, 0x22]) == nil, "16q-3a lector: el byte \(byte) crudo en un texto se rechaza")
    }
    expectEq(parse(bytes: [0x22, 0x20, 0x22]), .string(" "), "16q-3a lector: 0x20 es un espacio y se acepta")
    expectEq(parse(bytes: [0x22, 0x7F, 0x22]), .string("\u{7F}"), "16q-3a lector: 0x7F no es un control de JSON")
    expect(parse(bytes: [0x7B, 0x22, 0x00, 0x22, 0x3A, 0x31, 0x7D]) == nil, "16q-3a lector: tampoco en una clave")
}

// MARK: - Numbers

@Test func readerRejectsMalformedNumbers() {
    let rows: [(input: String, expected: JSONValue?)] = [
        (#"{"a":1.}"#, nil), (#"{"a":+1}"#, nil), (#"{"a":1e}"#, nil), (#"{"a":1e+}"#, nil), (#"{"a":-}"#, nil),
        (#"{"a":.5}"#, nil), (#"{"a":01}"#, nil), (#"{"a":--1}"#, nil), (#"{"a":1.5.2}"#, nil),
        (#"{"a":0x10}"#, nil), (#"{"a":1e999}"#, nil), (#"{"a":-1e999}"#, nil),
    ]
    checkTable(rows, "numero")
}

@Test func readerKeepsTheLexemeOfEveryValidNumber() {
    let rows: [(input: String, expected: JSONValue?)] = [
        ("1E5", .number("1E5", 100_000)),
        ("1e+5", .number("1e+5", 100_000)),
        ("1e-2", .number("1e-2", 0.01)),
        ("-0", .number("-0", -0.0)),
        ("0", .number("0", 0)),
        ("0.5", .number("0.5", 0.5)),
        ("-1.5e2", .number("-1.5e2", -150)),
        ("9007199254740993", .number("9007199254740993", 9_007_199_254_740_992)),
    ]
    checkTable(rows, "numero valido")
}

// MARK: - Whitespace and empty containers

@Test func readerAcceptsOnlyTheFourJSONWhitespaceBytes() {
    let expected = JSONValue.object(["a": .number("1", 1)])
    expectEq(parse("\t{\r\"a\"\t:\r1\t}\r"), expected, "16q-3a lector: tab y CR entre tokens")
    expectEq(parse(" \n{ \"a\" : 1 }\n "), expected, "16q-3a lector: espacio y LF")
    for byte in [UInt8(0x0B), 0x0C, 0x00, 0xA0] {
        let bytes = Array("{\"a\":".utf8) + [byte] + Array("1}".utf8)
        expect(parse(bytes: bytes) == nil, "16q-3a lector: el byte \(byte) no es espacio en blanco de JSON")
    }
    expect(parse(bytes: [0x0B] + Array("{}".utf8)) == nil, "16q-3a lector: VT antes del documento")
    expect(parse(bytes: Array("{}".utf8) + [0x0B]) == nil, "16q-3a lector: VT despues del documento")
}

@Test func readerParsesEmptyContainers() {
    let rows: [(input: String, expected: JSONValue?)] = [
        ("{ }", .object([:])), ("[ ]", .array([])), ("{}", .object([:])), ("[]", .array([])),
        ("{\t}", .object([:])), ("[\r\n]", .array([])),
        ("[ [ ], { } ]", .array([.array([]), .object([:])])),
        (#"{"a": [ ], "b": { }}"#, .object(["a": .array([]), "b": .object([:])])),
        ("[,]", nil), ("{,}", nil), ("[1,]", nil),
    ]
    checkTable(rows, "contenedor")
}

// MARK: - Depth

@Test func readerAllowsThirtyTwoLevelsAndRejectsThirtyThree() {
    for (open, close, core) in [("[", "]", ""), ("[", "]", "1"), (#"{"a":"#, "}", "1"), (#"{"a":["#, "]}", "1")] {
        // The mixed row nests two containers per repetition, so halve it.
        let step = open.count > 1 && open.hasSuffix("[") ? 2 : 1
        let atLimit = nested(open, close, levels: 32 / step, core: core)
        let overLimit = nested(open, close, levels: 32 / step + 1, core: core)
        expect(parse(atLimit) != nil, "16q-3a lector: 32 niveles de \(open) se aceptan")
        expect(parse(overLimit) == nil, "16q-3a lector: mas de 32 niveles de \(open) se rechazan")
    }
    expect(parse(nested("[", "]", levels: 33)) == nil, "16q-3a lector: 33 arreglos, exactamente uno de mas")
    expect(parse(nested("[", "]", levels: 32)) != nil, "16q-3a lector: 32 arreglos, exactamente el tope")
    expect(parse(nested("[", "]", levels: 5000)) == nil, "16q-3a lector: una bomba de profundidad")
}

@Test func readerCountsObjectLevelsLikeArrayLevels() {
    expect(parse(nested(#"{"a":"#, "}", levels: 32, core: "1")) != nil, "16q-3a lector: 32 objetos")
    expect(parse(nested(#"{"a":"#, "}", levels: 33, core: "1")) == nil, "16q-3a lector: 33 objetos")
    expect(parse(nested(#"{"a":"#, "}", levels: 32, core: "[]")) == nil, "16q-3a lector: un arreglo en el nivel 33")
    expect(parse(nested(#"{"a":"#, "}", levels: 31, core: "[]")) != nil, "16q-3a lector: un arreglo en el nivel 32")
}

// MARK: - BOM

@Test func readerRejectsALeadingBOM() {
    expect(parse(bytes: [0xEF, 0xBB, 0xBF] + Array(#"{"a":1}"#.utf8)) == nil, "16q-3a lector: BOM al inicio del documento")
    expect(parse(bytes: [0xEF, 0xBB, 0xBF] + Array("[]".utf8)) == nil, "16q-3a lector: BOM antes de un arreglo")
    expectEq(parse(#"{"a":1}"#), .object(["a": .number("1", 1)]), "16q-3a lector: sin BOM se lee igual")
}

@Test func readerKeepsABOMInsideAKeyOrValueDistinctFromNone() {
    let bob = "bob"
    let marked = "\u{FEFF}bob"
    expectEq(marked.unicodeScalars.count, 4, "fixture: el BOM es un escalar mas")
    for input in [#"{"k":"\#(marked)"}"#, #"{"k":"\ufeffbob"}"#] {
        guard case .object(let object)? = parse(input), case .string(let text)? = object["k"] else {
            Issue.record("16q-3a lector: \(input.debugDescription) debia leerse")
            continue
        }
        expectEq(Array(text.unicodeScalars).map(\.value), [0xFEFF, 0x62, 0x6F, 0x62],
                 "16q-3a lector: el BOM de un valor no se come")
    }
    for input in [#"{"\#(marked)":1}"#, #"{"\ufeffbob":1}"#] {
        guard case .object(let object)? = parse(input), let key = object.keys.first else {
            Issue.record("16q-3a lector: \(input.debugDescription) debia leerse")
            continue
        }
        expectEq(Array(key.unicodeScalars).map(\.value), [0xFEFF, 0x62, 0x6F, 0x62],
                 "16q-3a lector: el BOM de una clave no se come")
    }
    let withBOM = ActionVersion(toolName: "t", argumentsJSON: #"{"to":"\#(marked)"}"#)
    expect(withBOM != ActionVersion(toolName: "t", argumentsJSON: #"{"to":"\#(bob)"}"#),
           "16q-3a lector: <BOM>bob y bob son versiones distintas")
    let keyWithBOM = ActionVersion(toolName: "t", argumentsJSON: #"{"\#(marked)":1}"#)
    expect(keyWithBOM != ActionVersion(toolName: "t", argumentsJSON: #"{"\#(bob)":1}"#),
           "16q-3a lector: una clave <BOM>bob y bob son versiones distintas")
}

@Test func readerRefusesInvalidUTF8AndOverlongForms() {
    let rows: [[UInt8]] = [[0x22, 0xFF, 0x22], [0x22, 0xC0, 0xAF, 0x22], [0x22, 0xE2, 0x82, 0x22], [0x22, 0xED, 0xA0, 0x80, 0x22]]
    for bytes in rows { expect(parse(bytes: bytes) == nil, "16q-3a lector: \(bytes) no es UTF-8 valido") }
    expectEq(parse(bytes: [0x22, 0xF0, 0x9F, 0x98, 0x80, 0x22]), .string("😀"), "16q-3a lector: UTF-8 de 4 bytes valido")
}

// MARK: - Exponent overflow (fix round, finding 1)

@Test func extremeExponentsNeverTrapAndNeverComeOutComplete() {
    let lexemes = [
        "1.0e-9223372036854775808", "1e-9223372036854775808", "0.0e-9223372036854775808",
        "0e9223372036854775807", "0.0e9223372036854775807", "1e-9223372036854775807",
        "1e-99999999999999999999", "0.5e-99999999999999999999",
    ]
    for lexeme in lexemes {
        let s = ActionSummary.make(argumentsJSON: "{\"x\":\(lexeme)}")
        expect(!s.isComplete, "16q-3a exponente: \(lexeme) no se juzga y no tumba la app")
    }
}

@Test func roundTripsRefusesExponentsPastTheSaneBoundWithoutTrapping() {
    for lexeme in ["10e9223372036854775807", "1.0e9223372036854775807", "1.0e-9223372036854775808",
                   "1e+9223372036854775807", "1e401", "1e-401"] {
        expect(!JSONValue.roundTrips(lexeme, 0), "16q-3a exponente: \(lexeme) no hace viaje de ida y vuelta")
    }
    expect(JSONValue.roundTrips("1e300", 1e300), "16q-3a exponente: un exponente real sigue valiendo")
    expect(JSONValue.roundTrips("5e-324", 5e-324), "16q-3a exponente: el subnormal minimo tambien")
}
