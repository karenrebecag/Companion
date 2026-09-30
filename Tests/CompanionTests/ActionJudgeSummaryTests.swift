@testable import CompanionCore
import Foundation
import Testing

// 16q-3a: what the judge is shown of the arguments, and when that is not enough.

private func summary(_ json: String) -> ActionSummary { ActionSummary.make(argumentsJSON: json) }

private func keys(_ count: Int) -> String {
    let body = (0 ..< count).map { #""k\#(String(format: "%02d", $0))":1"# }.joined(separator: ",")
    return "{\(body)}"
}

private func app(_ json: String) -> ProposedAction? {
    ProposedAction.app(toolName: "app:slack:slack-send-message", label: "Send Message · Slack",
                       group: .crearYCambiar, argumentsJSON: json)
}

private func mcp(_ tool: String, _ json: String) -> ProposedAction {
    ProposedAction.mcp(ApprovalRequest(requestId: "r", toolName: tool, summary: "s", inputJSON: json))
}

@Test func actionSummaryKeepsShortTextsAndCollapsesLongOnes() {
    let long = String(repeating: "x", count: 81)
    let s = summary(#"{"to":"ana@corp.test","body":"\#(long)","n":3,"flag":true}"#)
    expectEq(s.values["to"], .text("ana@corp.test"), "16q-3a resumen: el destino corto viaja tal cual")
    expectEq(s.values["body"], .text("<text: 81 chars>"), "16q-3a resumen: el cuerpo largo viaja como longitud")
    expectEq(s.values["n"], .number(3), "16q-3a resumen: numero")
    expectEq(s.values["flag"], .bool(true), "16q-3a resumen: booleano")
    expectEq(summary(#"{"t":"\#(String(repeating: "y", count: 80))"}"#).values["t"],
             .text(String(repeating: "y", count: 80)), "16q-3a resumen: 80 exactos pasan")
}

@Test func actionSummaryNeverLetsThroughAStringLongerThan80() {
    let long = String(repeating: "z", count: 500)
    let keyed = summary(#"{"\#(long)":"v","k":"\#(long)","list":["\#(long)","b"],"deep":{"\#(long)":"\#(long)"}}"#)
    for (key, value) in keyed.values {
        expect(key.count <= 80, "16q-3a resumen: ninguna clave pasa de 80")
        switch value {
        case .text(let text): expect(text.count <= 80, "16q-3a resumen: ningun texto pasa de 80")
        case .list(let items): expect(items.allSatisfy { $0.count <= 80 }, "16q-3a resumen: ni los items")
        case .number, .bool: break
        }
    }
    let emoji = summary(#"{"k":"\#(String(repeating: "\u{1F600}", count: 200))"}"#)
    expectEq(emoji.values["k"], .text("<text: 200 chars>"), "16q-3a resumen: cuenta caracteres, no bytes")
}

@Test func actionSummaryShapesListsObjectsAndNulls() {
    let s = summary(#"{"cc":["a","b","c","d","e","f","g"],"mixed":["a",1],"obj":{"a":1,"b":2},"none":null,"empty":[]}"#)
    expectEq(s.values["cc"], .list(["a", "b", "c", "d", "e", "+2 more"]), "16q-3a resumen: los primeros 5 y cuantos faltan")
    expectEq(s.values["mixed"], .text("<list: 2 items>"), "16q-3a resumen: lista no homogenea colapsa")
    expectEq(s.values["obj"], .text("<object: 2 keys>"), "16q-3a resumen: objeto anidado")
    expectEq(s.values["none"], .text("<null>"), "16q-3a resumen: null")
    expectEq(s.values["empty"], .list([]), "16q-3a resumen: lista vacia")
}

@Test func actionSummaryCapsKeysAtSixteenAndSurvivesGarbage() {
    let many = (0 ..< 30).map { #""k\#(String(format: "%02d", $0))":1"# }.joined(separator: ",")
    let s = summary("{\(many)}")
    expectEq(s.values.count, 16, "16q-3a resumen: 16 claves como mucho")
    expect(!s.isComplete, "16q-3a resumen: con claves descartadas el resumen es incompleto")
    expect(s.values["k00"] != nil && s.values["k15"] != nil && s.values["k16"] == nil,
           "16q-3a resumen: las primeras 16 por orden de clave, determinista")
    expectEq(summary("not json").values.count, 0, "16q-3a resumen: no-JSON no viaja")
    expectEq(summary("[1,2]").values.count, 0, "16q-3a resumen: raiz que no es objeto")
    expectEq(summary("").values.count, 0, "16q-3a resumen: vacio")
}

@Test func actionSummaryStripsInvisibleCharacters() {
    let s = summary(#"{"to":"a‮b​c@x.test"}"#)
    expectEq(s.values["to"], .text("abc@x.test"), "16q-3a resumen: sanea bidi y ancho cero")
}

// MARK: - Summary: incomplete is not judgeable

@Test func summaryIsCompleteForAWellFormedObject() {
    let prose = String(repeating: "hola equipo ", count: 40)
    expect(summary(#"{"to":"ana@corp.test","body":"\#(prose)"}"#).isComplete,
           "16q-3a completo: un cuerpo en prosa viaja como longitud y no es una omision")
    expect(summary(keys(16)).isComplete, "16q-3a completo: 16 claves caben")
    expect(summary("{}").isComplete, "16q-3a completo: sin argumentos no hay nada que ocultar")
    expect(summary(#"{"a":null,"b":[],"c":true}"#).isComplete, "16q-3a completo: null, lista vacia y booleano")
}

@Test func summaryIsIncompleteWhenKeysWereDropped() {
    let s = summary(keys(17))
    expect(!s.isComplete, "16q-3a completo: la clave 17 se descarto, mutacion: quitar la marca de descarte")
    expectEq(s.values.count, 16, "16q-3a completo: sigue viajando lo que cabe")
    expect(!summary(keys(40)).isComplete, "16q-3a completo: 40 claves tambien")
}

@Test func summaryIsIncompleteWhenTwoKeysCollideAfterSanitising() {
    let s = summary("{\"to\":\"ana@corp.test\",\"to\u{200B}\":\"x@evil.test\"}")
    expect(!s.isComplete, "16q-3a completo: `to` y `to` con ancho cero chocan, mutacion: sobrescribir sin marcar")
    let bidi = summary("{\"channel\":\"ventas\",\"chan\u{202E}nel\":\"finanzas\"}")
    expect(!bidi.isComplete, "16q-3a completo: choque tras quitar bidi")
}

@Test func summaryIsIncompleteWhenTwoKeysCollideAfterTruncation() {
    let stem = String(repeating: "k", count: 40)
    let s = summary("{\"\(stem)a\":\"ana@corp.test\",\"\(stem)b\":\"x@evil.test\"}")
    expect(!s.isComplete, "16q-3a completo: dos claves de 41 que se cortan a 40 chocan")
    expectEq(s.values.count, 1, "16q-3a completo: y solo cabe una")
}

@Test func summaryIsIncompleteWhenTheArgumentsAreNotAnObject() {
    for json in ["", "   ", "not json", "[1,2]", "\"x\"", "5", "null", "true", #"{"a":"#, #"{"a":1,}"#, #"{"a":1} x"#] {
        let s = summary(json)
        expect(!s.isComplete, "16q-3a completo: \(json.debugDescription) no se puede juzgar")
        expectEq(s.values.count, 0, "16q-3a completo: \(json.debugDescription) no viaja nada")
    }
}

@Test func summaryIsIncompleteWhenAKeyIsInvisible() {
    let s = summary("{\"\u{200B}\u{202E}\":\"x@evil.test\"}")
    expect(!s.isComplete, "16q-3a completo: los argumentos no estan vacios pero la clave sale vacia")
    let plain = summary(#"{"":"x"}"#)
    expect(!plain.isComplete, "16q-3a completo: una clave vacia no dice de que es el valor")
}

@Test func summaryIsIncompleteForDuplicateKeys() {
    expect(!summary(#"{"to":"ana@corp.test","to":"x@evil.test"}"#).isComplete,
           "16q-3a completo: una clave repetida es ambigua, mutacion: el ultimo gana")
    expect(!summary(#"{"o":{"a":1,"a":2}}"#).isComplete, "16q-3a completo: tambien dentro de un anidado")
}

@Test func summaryParserIsStrictJSON() {
    for json in [#"{"a":01}"#, #"{"a":.5}"#, #"{"a":1e}"#, #"{"a":-}"#, #"{'a':1}"#, #"{"a":NaN}"#, #"{"a":Infinity}"#,
                 #"{"a":1e999}"#, "{\"a\":\"line\nbreak\"}", #"{"a":"\x"}"#, #"{"a":"\ud800"}"#, #"{"a":"\udc00x"}"#,
                 #"{"a":tru}"#, "/* c */ {\"a\":1}", #"{"a":[1,]}"#, #"{"a" 1}"#] {
        expect(!summary(json).isComplete, "16q-3a parser JSON: \(json.debugDescription) se rechaza")
    }
    let ok = summary(#"{ "t" : "é😀\n\t\"\\\/" , "n" : -1.5e2 , "b" : false }"#)
    expect(ok.isComplete, "16q-3a parser JSON: espacios, escapes y pares sustitutos validos")
    expectEq(ok.values["t"], .text("é😀\n\t\"\\/"), "16q-3a parser JSON: los escapes se decodifican")
    expectEq(ok.values["n"], .number(-150), "16q-3a parser JSON: numero con exponente")
    expectEq(ok.values["b"], .bool(false), "16q-3a parser JSON: booleano")
}

@Test func summaryParserRefusesADepthBomb() {
    let deep = String(repeating: "[", count: 400) + String(repeating: "]", count: 400)
    expect(!summary("{\"a\":\(deep)}").isComplete, "16q-3a parser JSON: 400 niveles no se recorren")
    let fine = String(repeating: "[", count: 8) + String(repeating: "]", count: 8)
    expect(JSONValue.parse(Data("{\"a\":\(fine)}".utf8)) != nil, "16q-3a parser JSON: 8 niveles si")
}

@Test func proposedActionCarriesTheCompletenessFlag() {
    expectEq(app(#"{"channel":"ventas"}"#)?.isComplete, true, "16q-3a completo: app completa")
    expectEq(app(keys(20))?.isComplete, false, "16q-3a completo: app con claves de mas")
    expectEq(mcp("fs/write", "garbage").isComplete, false, "16q-3a completo: mcp con argumentos ilegibles")
    expectEq(mcp("fs/write", #"{"path":"a"}"#).isComplete, true, "16q-3a completo: mcp completo")
}

// MARK: - Lists carry their total

@Test func aCutListCarriesItsTotal() {
    let seven = summary(#"{"to":["a","b","c","d","e","f","g"]}"#)
    expectEq(seven.values["to"], .list(["a", "b", "c", "d", "e", "+2 more"]),
             "16q-3a lista: 7 items dicen cuantos faltan, mutacion: quitar el marcador")
    expectEq(summary(#"{"to":["a","b","c","d","e","f"]}"#).values["to"], .list(["a", "b", "c", "d", "e", "+1 more"]),
             "16q-3a lista: 6 items, uno de mas")
    expectEq(summary(#"{"to":["a","b","c","d","e"]}"#).values["to"], .list(["a", "b", "c", "d", "e"]),
             "16q-3a lista: 5 exactos no llevan marcador")
    let bulk = (0 ..< 200).map { "\"u\($0)\"" }.joined(separator: ",")
    expectEq(summary("{\"to\":[\(bulk)]}").values["to"], .list(["u0", "u1", "u2", "u3", "u4", "+195 more"]),
             "16q-3a lista: un envio masivo se ve como masivo")
}

// MARK: - The 80-character cap, on graphemes

@Test func textCapCountsGraphemesAtTheBoundary() {
    let e80 = String(repeating: "\u{1F600}", count: 80)
    let e81 = String(repeating: "\u{1F600}", count: 81)
    expectEq(summary("{\"k\":\"\(e80)\"}").values["k"], .text(e80), "16q-3a tope: 80 emoji siguen como texto")
    expectEq(summary("{\"k\":\"\(e81)\"}").values["k"], .text("<text: 81 chars>"), "16q-3a tope: 81 emoji colapsan")
    let a80 = String(repeating: "a", count: 80)
    expectEq(summary("{\"k\":\"\(a80)\"}").values["k"], .text(a80), "16q-3a tope: 80 letras")
    expectEq(summary("{\"k\":\"\(a80)a\"}").values["k"], .text("<text: 81 chars>"), "16q-3a tope: 81 letras")
}

@Test func listItemCapCountsGraphemesAtTheBoundary() {
    let e80 = String(repeating: "\u{1F600}", count: 80)
    let e81 = String(repeating: "\u{1F600}", count: 81)
    expectEq(summary("{\"k\":[\"\(e80)\"]}").values["k"], .list([e80]), "16q-3a tope: un item de 80 se conserva")
    expectEq(summary("{\"k\":[\"\(e81)\"]}").values["k"], .text("<list: 1 items>"), "16q-3a tope: uno de 81 colapsa la lista")
    expectEq(summary("{\"k\":[\"a\",\"\(e81)\"]}").values["k"], .text("<list: 2 items>"),
             "16q-3a tope: y no importa en que posicion venga")
}

@Test func keyCapTruncatesAtFortyGraphemes() {
    let k40 = String(repeating: "k", count: 40)
    let s = summary("{\"\(k40)k\":\"v\"}")
    expectEq(s.values[k40], .text("v"), "16q-3a tope: una clave de 41 se corta a 40")
    expectEq(s.values.count, 1, "16q-3a tope: y no queda la de 41")
    expectEq(summary("{\"\(k40)\":\"v\"}").values[k40], .text("v"), "16q-3a tope: una de 40 pasa entera")
}

@Test func scalarCapStopsCombiningClustersFromCarryingKilobytes() {
    let mark = "\u{0301}"
    let fits = String(repeating: "a" + String(repeating: mark, count: 3), count: 80)
    expectEq(fits.unicodeScalars.count, 320, "fixture: 80 grafemas de 4 escalares")
    expectEq(summary("{\"k\":\"\(fits)\"}").values["k"], .text(fits), "16q-3a escalares: 320 exactos pasan")
    let over = fits + mark
    expectEq(over.count, 80, "fixture: sigue siendo 80 grafemas")
    expectEq(summary("{\"k\":\"\(over)\"}").values["k"], .text("<text: 80 chars>"),
             "16q-3a escalares: 321 colapsan aunque los grafemas sean 80")
    let zalgo = String(repeating: "a" + String(repeating: mark, count: 15), count: 80)
    expectEq(zalgo.unicodeScalars.count, 1280, "fixture: 1,2 KB de escalares")
    expectEq(summary("{\"k\":\"\(zalgo)\"}").values["k"], .text("<text: 80 chars>"),
             "16q-3a escalares: 80 grafemas de 16 escalares no viajan")
    expectEq(summary("{\"k\":[\"\(zalgo)\"]}").values["k"], .text("<list: 1 items>"),
             "16q-3a escalares: ni como item de lista")
    let zalgoKey = String(repeating: "a" + String(repeating: mark, count: 15), count: 40)
    let keyed = summary("{\"\(zalgoKey)\":1}")
    for key in keyed.values.keys {
        expect(key.unicodeScalars.count <= 160, "16q-3a escalares: una clave no pasa de 4 x 40 escalares")
    }
}

@Test func summarySizeIsBoundedInBytes() {
    let mark = "\u{0301}"
    let fits = String(repeating: "a" + String(repeating: mark, count: 3), count: 80)
    let body = (0 ..< 16).map { "\"k\(String(format: "%02d", $0))\":\"\(fits)\"" }.joined(separator: ",")
    let s = summary("{\(body)}")
    let bytes = s.values.reduce(0) { total, pair in
        if case .text(let text) = pair.value { return total + pair.key.utf8.count + text.utf8.count }
        return total
    }
    expect(s.isComplete && bytes <= 16 * (40 + 320 * 2 + 40), "16q-3a escalares: 16 claves acotadas (\(bytes) bytes)")
}

// MARK: - Input byte cap (fix round, finding 2)

/// `{"a":1,"b":"<prose>"}` padded to exactly `size` bytes. Prose so that,
/// under the cap, the body is complete and travels as its length.
func argumentsOfExactly(_ size: Int, bodyFirst: Bool = false) -> String {
    let frame = bodyFirst ? (#"{"b":""#, #"","a":1}"#) : (#"{"a":1,"b":""#, #""}"#)
    let prose = String(String(repeating: "a ", count: size).prefix(size - frame.0.utf8.count - frame.1.utf8.count))
    let json = frame.0 + prose + frame.1
    precondition(json.utf8.count == size, "fixture: exactly \(size) bytes")
    return json
}

@Test func summaryParsesArgumentsAtTheByteCap() {
    let s = summary(argumentsOfExactly(ActionSummary.maxArgumentBytes))
    expect(s.isComplete, "16q-3a tope de bytes: justo en el tope se resume")
    expectEq(s.values["a"], .number(1), "16q-3a tope de bytes: y viaja lo que nombra el destino")
}

@Test func summaryRefusesArgumentsOverTheByteCapWithoutParsing() {
    let s = summary(argumentsOfExactly(ActionSummary.maxArgumentBytes + 1))
    expect(!s.isComplete, "16q-3a tope de bytes: un byte de mas no se juzga")
    expectEq(s.values.count, 0, "16q-3a tope de bytes: y no viaja nada")
}

// MARK: - Sanitising a value hides a change (fix round, finding 4)

@Test func summaryIsIncompleteWhenSanitisingChangesAValue() {
    let value = summary("{\"to\":\"ana\u{200B}@x.com\"}")
    expectEq(value.values["to"], .text("ana@x.com"), "16q-3a saneado: el juez ve el texto limpio")
    expect(!value.isComplete, "16q-3a saneado: pero no es el que recibe la tool, asi que no se juzga")
    let item = summary("{\"to\":[\"bob@x.com\",\"ana\u{200B}@x.com\"]}")
    expectEq(item.values["to"], .list(["bob@x.com", "ana@x.com"]), "16q-3a saneado: la lista viaja limpia")
    expect(!item.isComplete, "16q-3a saneado: un item cambiado tambien la hace incompleta")
    expect(summary("{\"to\":\"ana@x.com\",\"cc\":[\"bob@x.com\"]}").isComplete,
           "16q-3a saneado: sin nada que limpiar sigue completo")
}

// MARK: - Secret keys travel as length only (fix round, item 6)

/// Every text the summary would put in front of the judge, keys included.
private func shownText(_ s: ActionSummary) -> String {
    s.values.map { key, value in
        switch value {
        case .text(let text): return key + "=" + text
        case .list(let items): return key + "=" + items.joined(separator: ",")
        case .number(let number): return key + "=\(number)"
        case .bool(let flag): return key + "=\(flag)"
        }
    }.joined(separator: ";")
}

@Test func aSecretValueNeverReachesTheJudge() {
    let s = summary(#"{"to":"ana@x.com","password":"hunter2"}"#)
    expect(!shownText(s).contains("hunter2"), "16q-3a secretos: una contrasena corta nunca viaja")
    expectEq(s.values["password"], .text("<text: 7 chars>"), "16q-3a secretos: solo su longitud")
    expect(s.isComplete, "16q-3a secretos: el juez no necesita el valor, el resumen sigue completo")
}

@Test func secretKeysMatchCaseAndSeparatorsAndWholeSegments() {
    for key in ["x-api-key", "Authorization", "API_KEY", "apiKey", "github_token", "Refresh-Token",
                "accessToken", "COOKIE", "user_session", "passwd", "client-secret", "Password"] {
        let s = summary("{\"\(key)\":\"s3cr3tvalue\"}")
        expect(!shownText(s).contains("s3cr3tvalue"), "16q-3a secretos: \(key) se reconoce")
        expect(s.isComplete, "16q-3a secretos: \(key) sigue completo")
    }
}

@Test func nonSecretKeysAreUnchanged() {
    let s = summary(#"{"to":"ana@x.com","url":"https://x.test/a","tokens":"12","max_tokens":5,"sessions":"a"}"#)
    expectEq(s.values["to"], .text("ana@x.com"), "16q-3a secretos: `to` viaja tal cual")
    expectEq(s.values["url"], .text("https://x.test/a"), "16q-3a secretos: `url` tambien")
    expectEq(s.values["tokens"], .text("12"), "16q-3a secretos: solo segmentos enteros, `tokens` no es `token`")
    expectEq(s.values["max_tokens"], .number(5), "16q-3a secretos: ni `max_tokens`")
    expectEq(s.values["sessions"], .text("a"), "16q-3a secretos: ni `sessions`")
}

@Test func aNestedObjectOrListUnderASecretKeyIsNeverExpanded() {
    let nested = summary(#"{"token":{"value":"hunter2","kind":"bearer"}}"#)
    expect(!shownText(nested).contains("hunter2") && !shownText(nested).contains("object"),
           "16q-3a secretos: un objeto bajo `token` no se abre ni se cuenta por claves")
    expect(nested.isComplete, "16q-3a secretos: y el resumen sigue completo")
    guard case .text(let marker)? = nested.values["token"] else {
        Issue.record("16q-3a secretos: el objeto viaja como marcador de longitud")
        return
    }
    expect(marker.hasPrefix("<text: ") && marker.hasSuffix(" chars>"), "16q-3a secretos: forma de longitud")
    let list = summary(#"{"api_key":["k1-hunter2","k2-hunter3"]}"#)
    expect(!shownText(list).contains("hunter"), "16q-3a secretos: los items de una lista bajo la clave tampoco")
    expect(list.isComplete, "16q-3a secretos: lista secreta completa")
}

@Test func secretKeysWithoutSeparatorsDigitsOrCommonSynonymsAreCaught() {
    for key in ["accesstoken", "ACCESSTOKEN", "authtoken", "myAPIToken", "password1", "token2", "secrets",
                "private_key", "privateKey", "access_key", "credential", "credentials", "passphrase", "pwd",
                "bearer", "jwt", "authorization_header", "ｔｏｋｅｎ", "client_credentials",
                "APIToken", "APISecret", "HTTPSession", "JWTToken", "apiKey2", "APIKey"] {
        let s = summary("{\"\(key)\":\"s3cr3tvalue\"}")
        expect(!shownText(s).contains("s3cr3tvalue"), "16q-3a secretos: \(key) se reconoce")
    }
}

@Test func countAndOrdinaryFieldsThatContainASecretWordStillTravel() {
    for key in ["tokens", "max_tokens", "maxTokens", "input_tokens", "tokenizer", "sessions", "author",
                "compass", "passenger", "keyword"] {
        let s = summary("{\"\(key)\":\"visible\"}")
        expect(shownText(s).contains("visible"), "16q-3a secretos: \(key) no es una credencial")
    }
}
