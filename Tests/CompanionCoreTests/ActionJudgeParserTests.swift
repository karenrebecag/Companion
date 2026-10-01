@testable import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// 16q-3a: the verdict parser, one test per way the contract can be broken.

private func verdictsBody(_ entries: [String], extra: String = "") -> Data {
    Data(#"{"verdicts":[\#(entries.joined(separator: ","))]\#(extra)}"#.utf8)
}

private func entry(_ id: String, covered: String = "true", reason: String = #""asked""#) -> String {
    #"{"id":"\#(id)","covered":\#(covered),"reason":\#(reason)}"#
}

private let twoIDs = ["a1", "a2"]
private let invalid = JudgeVerdict.failed(.invalid)

private func parse(_ data: Data, ids: [String] = twoIDs) -> [JudgeVerdict] {
    JudgeVerdictParser.parse(data, ids: ids)
}

// MARK: - Parser: the valid shape

@Test func judgeParserAcceptsTheStrictShape() {
    let got = parse(verdictsBody([entry("a1"), entry("a2", covered: "false", reason: #""not_asked""#)]))
    expectEq(got, [.covered, .notCovered(.notAsked)], "16q-3a parser: forma estricta, en el orden de los ids")
    let reordered = parse(verdictsBody([entry("a2", covered: "false", reason: #""other_target""#), entry("a1")]))
    expectEq(reordered, [.covered, .notCovered(.otherTarget)], "16q-3a parser: el orden de la respuesta no manda, el de los ids si")
}

// MARK: - Parser: the invalid forms, one test each

@Test func judgeParserRejectsAnEmptyOrNonJSONBody() {
    expectEq(parse(Data()), [invalid, invalid], "16q-3a parser 1: cuerpo vacio")
    expectEq(parse(Data("not json".utf8)), [invalid, invalid], "16q-3a parser 1: no es JSON")
    expectEq(parse(Data(#"{"verdicts":[{"id":"a1""#.utf8)), [invalid, invalid], "16q-3a parser 1: JSON a medias")
}

@Test func judgeParserRejectsATopLevelThatIsNotAnObject() {
    expectEq(parse(Data("[]".utf8)), [invalid, invalid], "16q-3a parser 2: arreglo en la raiz")
}

@Test func judgeParserRejectsAnExtraTopLevelKey() {
    let body = verdictsBody([entry("a1"), entry("a2")], extra: #","note":"hi""#)
    expectEq(parse(body), [invalid, invalid], "16q-3a parser 3: clave de mas en la raiz")
}

@Test func judgeParserRejectsAMissingOrNonArrayVerdicts() {
    expectEq(parse(Data("{}".utf8)), [invalid, invalid], "16q-3a parser 4: sin verdicts")
    expectEq(parse(Data(#"{"verdicts":{"a1":true}}"#.utf8)), [invalid, invalid], "16q-3a parser 4: verdicts no es arreglo")
}

@Test func judgeParserRejectsAnEntryThatIsNotAnObject() {
    expectEq(parse(verdictsBody([#""a1""#, entry("a2")])), [invalid, invalid], "16q-3a parser 5: entrada que no es objeto")
}

@Test func judgeParserRejectsAnIDThatIsNotInTheRequest() {
    let got = parse(verdictsBody([entry("a1"), entry("a2"), entry("a9")]))
    expectEq(got, [invalid, invalid], "16q-3a parser 6: id que sobra invalida el lote")
}

@Test func judgeParserRejectsAMissingID() {
    let got = parse(verdictsBody([entry("a1")]))
    expectEq(got, [.covered, invalid], "16q-3a parser 7: el id que falta queda fallado y no arrastra al otro")
}

@Test func judgeParserRejectsARepeatedID() {
    let got = parse(verdictsBody([entry("a1"), entry("a1"), entry("a2")]))
    expectEq(got, [invalid, .covered], "16q-3a parser 8: un id repetido no se cree ni la primera ni la segunda vez")
}

@Test func judgeParserRejectsAnExtraKeyInAnEntry() {
    let extra = #"{"id":"a1","covered":true,"reason":"asked","why":"because"}"#
    expectEq(parse(verdictsBody([extra, entry("a2")])), [invalid, .covered], "16q-3a parser 9: clave de mas en la entrada")
}

@Test func judgeParserRejectsAMissingKeyInAnEntry() {
    let noReason = #"{"id":"a1","covered":true}"#
    let noCovered = #"{"id":"a2","reason":"asked"}"#
    expectEq(parse(verdictsBody([noReason, noCovered])), [invalid, invalid], "16q-3a parser 10: falta covered o reason")
}

@Test func judgeParserRejectsAWrongType() {
    let text = parse(verdictsBody([entry("a1", covered: #""true""#), entry("a2")]))
    expectEq(text, [invalid, .covered], "16q-3a parser 11: covered como texto")
    let number = parse(verdictsBody([entry("a1", covered: "1"), entry("a2")]))
    expectEq(number, [invalid, .covered], "16q-3a parser 11: covered como numero")
    let reasonNumber = parse(verdictsBody([entry("a1", reason: "3"), entry("a2")]))
    expectEq(reasonNumber, [invalid, .covered], "16q-3a parser 11: reason como numero")
    let idNumber = parse(verdictsBody([#"{"id":1,"covered":true,"reason":"asked"}"#, entry("a2")]))
    expectEq(idNumber, [invalid, invalid], "16q-3a parser 11: id que no es texto no se puede atribuir")
}

@Test func judgeParserRejectsAReasonOutsideTheEnum() {
    let got = parse(verdictsBody([entry("a1", covered: "false", reason: #""because_i_said""#), entry("a2")]))
    expectEq(got, [invalid, .covered], "16q-3a parser 12: reason fuera del enum")
}

@Test func judgeParserRejectsCoveredWithAReasonOtherThanAsked() {
    let got = parse(verdictsBody([entry("a1", covered: "true", reason: #""unclear""#), entry("a2")]))
    expectEq(got, [invalid, .covered], "16q-3a parser 13: covered:true exige reason asked")
}

@Test func judgeParserRejectsNotCoveredWithReasonAsked() {
    let got = parse(verdictsBody([entry("a1", covered: "false", reason: #""asked""#), entry("a2")]))
    expectEq(got, [invalid, .covered], "16q-3a parser 14: asked y no cubierta se contradicen")
}

@Test func judgeParserNeverReturnsCoveredForAnEmptyIDList() {
    expectEq(JudgeVerdictParser.parse(verdictsBody([]), ids: []), [], "16q-3a parser: sin ids no hay veredictos")
}

@Test func parserMapsEveryReasonLiteral() {
    expectEq(JudgeReason.allCases.count, 5, "16q-3a parser: un reason nuevo obliga a actualizar este test")
    let literals: [(String, JudgeReason)] = [
        ("not_asked", .notAsked), ("other_target", .otherTarget),
        ("broader_effect", .broaderEffect), ("unclear", .unclear),
    ]
    for (raw, reason) in literals {
        let got = parse(verdictsBody([entry("a1", covered: "false", reason: "\"\(raw)\""), entry("a2")]))
        expectEq(got, [.notCovered(reason), .covered], "16q-3a parser: \(raw) -> notCovered(\(reason))")
    }
    for typo in ["broader-effect", "broaderEffect", "Broader_Effect", "unclear ", "Unclear", "not asked", "other-target", "notAsked"] {
        let got = parse(verdictsBody([entry("a1", covered: "false", reason: "\"\(typo)\""), entry("a2")]))
        expectEq(got, [invalid, .covered], "16q-3a parser: \(typo.debugDescription) no es un reason")
    }
    expectEq(JudgeReason.allCases.map(\.rawValue), ["asked", "not_asked", "other_target", "broader_effect", "unclear"],
             "16q-3a parser: los literales de la spec 4")
}

@Test func judgeFailureRawValuesAreTheLogKeys() {
    let expected: [(JudgeFailure, String)] = [
        (.timeout, "timeout"), (.http, "http"), (.invalid, "invalid"), (.noProvider, "no_provider"),
        (.noWords, "no_words"), (.tooMany, "too_many"), (.cancelled, "cancelled"),
    ]
    expectEq(JudgeFailure.allCases.count, expected.count, "16q-3a fallos: un caso nuevo obliga a actualizar este test")
    for (failure, raw) in expected {
        expectEq(failure.rawValue, raw, "16q-3a fallos: clave de log de \(failure)")
        expectEq(JudgeVerdict.failed(failure).description, "failed:\(raw)", "16q-3a fallos: descripcion de \(failure)")
    }
}

@Test func verdictDescriptionsAreTheLogValues() {
    expectEq(JudgeVerdict.covered.description, "covered", "16q-3a veredicto: covered")
    expectEq(JudgeVerdict.notCovered(.notAsked).description, "not_covered:not_asked", "16q-3a veredicto: not_asked")
    expectEq(JudgeVerdict.notCovered(.otherTarget).description, "not_covered:other_target", "16q-3a veredicto: other_target")
    expectEq(JudgeVerdict.notCovered(.broaderEffect).description, "not_covered:broader_effect", "16q-3a veredicto: broader_effect")
    expectEq(JudgeVerdict.notCovered(.unclear).description, "not_covered:unclear", "16q-3a veredicto: unclear")
    expectEq(JudgeVerdict.failed(.invalid).description, "failed:invalid", "16q-3a veredicto: failed")
}

@Test func parserRejectsRootsThatAreNotObjects() {
    for root in [#""x""#, "null", "true", "5", "[]", #"[{"verdicts":[]}]"#] {
        expectEq(parse(Data(root.utf8)), [invalid, invalid], "16q-3a parser: raiz \(root)")
    }
}

@Test func parserRejectsAMisspelledKeyThatLeavesTheRightCount() {
    let typo = #"{"id":"a1","covered":true,"reasons":"asked"}"#
    let noID = #"{"ident":"a2","covered":true,"reason":"asked"}"#
    expectEq(parse(verdictsBody([typo, entry("a2")])), [invalid, .covered], "16q-3a parser: reasons en vez de reason")
    expectEq(parse(verdictsBody([entry("a1"), noID])), [invalid, invalid], "16q-3a parser: sin id no se atribuye")
    let rootTypo = Data(#"{"verdict":[{"id":"a1","covered":true,"reason":"asked"}]}"#.utf8)
    expectEq(parse(rootTypo), [invalid, invalid], "16q-3a parser: verdict en vez de verdicts")
}

@Test func parserRejectsADuplicateKeyInsideOneEntry() {
    let lastWinsCovered = #"{"id":"a1","covered":false,"reason":"asked","covered":true}"#
    expectEq(parse(verdictsBody([lastWinsCovered, entry("a2")])), [invalid, invalid],
             "16q-3a parser: covered repetido, mutacion: el ultimo gana daria covered")
    let dupReason = #"{"id":"a1","covered":true,"reason":"not_asked","reason":"asked"}"#
    expectEq(parse(verdictsBody([dupReason, entry("a2")])), [invalid, invalid], "16q-3a parser: reason repetido")
    let dupID = #"{"id":"a2","id":"a1","covered":true,"reason":"asked"}"#
    expectEq(parse(verdictsBody([dupID, entry("a2")])), [invalid, invalid], "16q-3a parser: id repetido dentro de la entrada")
    let dupRoot = Data(#"{"verdicts":[],"verdicts":[{"id":"a1","covered":true,"reason":"asked"}]}"#.utf8)
    expectEq(parse(dupRoot), [invalid, invalid], "16q-3a parser: verdicts repetido en la raiz")
}

@Test func parserRejectsNullValues() {
    expectEq(parse(verdictsBody([entry("a1", covered: "null"), entry("a2")])), [invalid, .covered], "16q-3a parser: covered null")
    expectEq(parse(verdictsBody([entry("a1", reason: "null"), entry("a2")])), [invalid, .covered], "16q-3a parser: reason null")
    expectEq(parse(verdictsBody([#"{"id":null,"covered":true,"reason":"asked"}"#, entry("a2")])), [invalid, invalid],
             "16q-3a parser: id null no se atribuye")
    expectEq(parse(Data(#"{"verdicts":null}"#.utf8)), [invalid, invalid], "16q-3a parser: verdicts null")
    expectEq(parse(verdictsBody(["null", entry("a2")])), [invalid, invalid], "16q-3a parser: entrada null")
}

@Test func parserRejectsBodiesOverTheSizeCap() {
    let valid = #"{"verdicts":[{"id":"a1","covered":true,"reason":"asked"},{"id":"a2","covered":true,"reason":"asked"}]}"#
    let capBytes = 16 * 1024
    let atCap = valid + String(repeating: " ", count: capBytes - valid.utf8.count)
    expectEq(atCap.utf8.count, capBytes, "fixture: justo en el tope")
    expectEq(parse(Data(atCap.utf8)), [.covered, .covered], "16q-3a parser: 16 KB exactos se aceptan")
    expectEq(parse(Data((atCap + " ").utf8)), [invalid, invalid],
             "16q-3a parser: 16 KB + 1 se rechazan, mutacion: quitar el tope")
    let padded = valid + String(repeating: " ", count: 10 * 1024 * 1024)
    expectEq(parse(Data(padded.utf8)), [invalid, invalid], "16q-3a parser: 10 MB tampoco")
}

@Test func parserRejectsMoreThanSixteenEntries() {
    let fifteenRepeats = Array(repeating: entry("a1"), count: 15)
    expectEq(parse(verdictsBody(fifteenRepeats + [entry("a2")])), [invalid, .covered],
             "16q-3a parser: 16 entradas se leen, el repetido falla solo el")
    expectEq(parse(verdictsBody(fifteenRepeats + [entry("a1"), entry("a2")])), [invalid, invalid],
             "16q-3a parser: 17 entradas se rechazan, mutacion: quitar el tope")
}

@Test func parserRejectsInvalidUTF8AndHostileNesting() {
    var bytes = Array(#"{"verdicts":[{"id":"a"#.utf8)
    bytes.append(0xFF)
    bytes.append(contentsOf: Array(#"","covered":true,"reason":"asked"}]}"#.utf8))
    // The id is the replacement character on purpose: a lenient decoder turns
    // the bad byte into exactly this id and would call it covered.
    expectEq(parse(Data(bytes), ids: ["a\u{FFFD}"]), [invalid], "16q-3a parser: UTF-8 invalido, mutacion: decodificar con reemplazo")
    let deep = String(repeating: "[", count: 5000) + String(repeating: "]", count: 5000)
    expectEq(parse(Data("{\"verdicts\":\(deep)}".utf8)), [invalid, invalid], "16q-3a parser: anidamiento hostil")
    expectEq(parse(Data(#"{"verdicts":[{"id":"a\ud800","covered":true,"reason":"asked"}]}"#.utf8)), [invalid, invalid],
             "16q-3a parser: sustituto suelto")
}
