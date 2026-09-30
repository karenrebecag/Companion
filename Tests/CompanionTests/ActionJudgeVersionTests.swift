@testable import CompanionCore
import Foundation
import Testing

// 16q-3a: the version digest, the identity of exactly this action.

private func summary(_ json: String) -> ActionSummary { ActionSummary.make(argumentsJSON: json) }

private func version(_ tool: String, _ args: String) -> ActionVersion {
    ActionVersion(toolName: tool, argumentsJSON: args)
}

private func version(_ args: String) -> ActionVersion {
    version("app:slack:slack-send-message", args)
}

private let slackTool = "app:slack:slack-send-message"

private func app(_ json: String) -> ProposedAction? {
    ProposedAction.app(toolName: slackTool, label: "Send Message · Slack", group: .crearYCambiar, argumentsJSON: json)
}

// MARK: - ActionVersion

@Test func actionVersionIgnoresKeyOrder() {
    expectEq(version(#"{"a":1,"b":2}"#), version(#"{"b":2,"a":1}"#), "16q-3a version: el orden de claves no cuenta")
    expectEq(version(#"{"o":{"x":1,"y":2},"a":1}"#), version(#"{"a":1,"o":{"y":2,"x":1}}"#),
             "16q-3a version: tampoco en objetos anidados")
}

@Test func actionVersionChangesWithOneCharacter() {
    expect(version(#"{"to":"ana@corp.test"}"#) != version(#"{"to":"ana@corp.tesu"}"#), "16q-3a version: un caracter")
    expect(version(#"{"to":"ana"}"#) != version(#"{"to":"ana "}"#), "16q-3a version: los espacios cuentan")
    expect(version("a:b", "{}") != version("a:c", "{}"), "16q-3a version: el nombre de la tool cuenta")
    expect(version("ab", "{}") != version("a", "b{}"), "16q-3a version: el separador evita la colision")
}

@Test func actionVersionFallsBackToRawBytesForNonJSON() {
    expectEq(version("not json"), version("not json"), "16q-3a version: mismos bytes, misma version")
    expect(version("not json") != version("not jsom"), "16q-3a version: bytes distintos")
    expect(version("") != version("{}"), "16q-3a version: vacio no es objeto vacio")
}

@Test func actionVersionIsAStableSHA256() {
    expectEq(version(#"{"a":1}"#).hex.count, 64, "16q-3a version: SHA256 en hex")
}

// MARK: - Version

@Test func appVersionHashesTheRealArguments() {
    let json = #"{"channel":"ventas","text":"hola"}"#
    expectEq(app(json)?.version, version(slackTool, json),
             "16q-3a version: la de .app es la de los argumentos reales, mutacion: hash sobre {}")
    expect(app(json)?.version != app(#"{"channel":"ventas","text":"hoal"}"#)?.version,
           "16q-3a version: mismos tool y otros argumentos, otra version")
    expect(app(json)?.version != version(slackTool, "{}"), "16q-3a version: no es la de un objeto vacio")
    let request = ApprovalRequest(requestId: "r", toolName: "fs/write", summary: "s", inputJSON: json)
    expectEq(ProposedAction.mcp(request).version, version("fs/write", json), "16q-3a version: la de .mcp tambien")
    expect(ProposedAction.mcp(request).version != version("fs/write", "{}"), "16q-3a version: mcp no hashea {}")
}

@Test func versionSeparatorCannotCollide() {
    expect(version("a\u{0}b", "{}") != version("a", "b\u{0}{}"), "16q-3a version: un nombre con NUL no se come los argumentos")
    expect(version("ab", "{}") != version("a", "b{}"), "16q-3a version: el limite del nombre cuenta")
    expect(version("a\u{0}", "x") != version("a", "\u{0}x"), "16q-3a version: el NUL viaja de un lado al otro y no colisiona")
    expect(version("a\u{1}", "x") != version("a", "\u{1}x"), "16q-3a version: ni con el byte del marcador")
    expect(version("", "abc") != version("a", "bc"), "16q-3a version: nombre vacio")
    expect(version("a", "") != version("", "a"), "16q-3a version: argumentos vacios")
    expect(version("tool", #"{"a":1}"#) != version("tool", "n"), "16q-3a version: un JSON y un texto crudo no se confunden")
    expect(version("tool", "null") != version("tool", "n"), "16q-3a version: null y el texto n")
}

@Test func versionIsPinnedToAKnownSHA256() {
    expectEq(version("t", #"{"a":1}"#).hex,
             "e22b6fdb64e6c54f50214acc10aea8e55447fb9ca2fc8a4b3e8cc70bc8204695",
             "16q-3a version: vector fijo, SHA256(u64be(len) | tool | 0x01 | canonico)")
    expectEq(version("t", "not json").hex,
             "f6c82505c3429811581475cbb173fb66c16f1547297a717aa5bebfb12a298921",
             "16q-3a version: vector fijo del camino de bytes crudos, SHA256(u64be(len) | tool | 0x00 | bytes)")
}

@Test func versionChangesWithCase() {
    expect(version(slackTool, #"{"to":"Ana"}"#) != version(slackTool, #"{"to":"ana"}"#), "16q-3a version: mayuscula en un valor")
    expect(version(slackTool, #"{"To":"a"}"#) != version(slackTool, #"{"to":"a"}"#), "16q-3a version: mayuscula en una clave")
    expect(version("App:slack:x", "{}") != version("app:slack:x", "{}"), "16q-3a version: mayuscula en la tool")
}

@Test func versionKeepsDuplicateKeysAndBigIntegersApart() {
    expect(version("t", #"{"a":1,"a":2}"#) != version("t", #"{"a":2}"#), "16q-3a version: la clave repetida no se colapsa")
    expect(version("t", #"{"a":1,"a":2}"#) != version("t", #"{"a":1}"#), "16q-3a version: ni al primero")
    expect(version("t", #"{"n":9007199254740993}"#) != version("t", #"{"n":9007199254740992}"#),
           "16q-3a version: enteros que un Double confundiria")
    expect(version("t", #"{"n":18446744073709551617}"#) != version("t", #"{"n":18446744073709551616}"#),
           "16q-3a version: enteros mas alla de Int64")
    expect(version("t", #"{"n":1.0}"#) != version("t", #"{"n":1}"#), "16q-3a version: la forma del numero cuenta")
    expectEq(version("t", #"{"n":1,"m":2}"#), version("t", #"{"m":2,"n":1}"#), "16q-3a version: el orden sigue sin contar")
    expectEq(version("t", #"{"s":"\u0041"}"#), version("t", #"{"s":"A"}"#), "16q-3a version: un escape y su letra son lo mismo")
    expectEq(version("t", #"{"s":"\ud83d\ude00"}"#), version("t", #"{"s":"😀"}"#),
             "16q-3a version: un par sustituto y su emoji son lo mismo")
}

@Test func summaryAndVersionShareOneParser() {
    let dup = #"{"to":"ana@corp.test","to":"x@evil.test"}"#
    expect(!summary(dup).isComplete, "16q-3a un parser: el resumen ve la ambiguedad")
    expect(version("t", dup) != version("t", #"{"to": "ana@corp.test","to":"x@evil.test"}"#),
           "16q-3a un parser: la version cae a bytes crudos, el camino estricto, con el mismo criterio")
    let fine = #"{"b":2,"a":"x"}"#
    expect(summary(fine).isComplete, "16q-3a un parser: lo que el resumen lee bien")
    expectEq(version("t", fine), version("t", #"{"a":"x","b":2}"#), "16q-3a un parser: la version lo canoniza")
    expectEq(version("t", "  {\"a\":1}\n"), version("t", #"{"a":1}"#), "16q-3a un parser: espacios fuera del JSON no cuentan")
}

@Test func versionIsPinnedForNestedArraysAndUTF8KeyOrder() {
    // Under Swift's own String order U+212B sorts before U+00C6 (its NFC is
    // U+00C5); under UTF-8 bytes it sorts after. The digest must follow bytes.
    let angstrom = "\u{212B}", ae = "\u{C6}"
    expect(angstrom < ae, "fixture: en orden de String el angstrom va antes")
    expect(!Array(angstrom.utf8).lexicographicallyPrecedes(Array(ae.utf8)), "fixture: en bytes UTF-8 va despues")
    let json = "{\"\(angstrom)\":true,\"z\":[1,\"a\"],\"\(ae)\":null}"
    // shasum -a 256 over: 00*7 01 | "t" | 01 | {s1:z[#1:1s1:a]s2:<C3 86>ns3:<E2 84 AB>t}
    expectEq(version("t", json).hex, "9b934f9139a543e980202d1a2789a94b0a3d4994d9adb9744807dcf22a1f3f73",
             "16q-3a version: vector fijo con lista anidada y orden de claves por bytes UTF-8")
    let reordered = "{\"\(ae)\":null,\"z\":[1,\"a\"],\"\(angstrom)\":true}"
    expectEq(version("t", reordered).hex, version("t", json).hex, "16q-3a version: el orden de entrada sigue sin contar")
    expect(version("t", "{\"z\":[\"a\",1],\"\(angstrom)\":true,\"\(ae)\":null}") != version("t", json),
           "16q-3a version: el orden de una lista si cuenta")
}

// MARK: - Input byte cap (fix round, finding 2)

@Test func versionIsCanonicalAtTheByteCapAndRawPastIt() {
    let cap = ActionSummary.maxArgumentBytes
    expectEq(version(argumentsOfExactly(cap)), version(argumentsOfExactly(cap, bodyFirst: true)),
             "16q-3a tope de bytes: en el tope se hashea la forma canonica, el orden no cuenta")
    expect(version(argumentsOfExactly(cap + 1)) != version(argumentsOfExactly(cap + 1, bodyFirst: true)),
           "16q-3a tope de bytes: pasado el tope se hashean los bytes crudos, sin parsear")
}

@Test func twoDifferentSecretsAreTwoVersions() {
    expectEq(summary(#"{"password":"hunter2"}"#), summary(#"{"password":"hunter3"}"#),
             "fixture: el juez ve lo mismo para los dos secretos")
    expect(version(#"{"password":"hunter2"}"#) != version(#"{"password":"hunter3"}"#),
           "16q-3a secretos: la version hashea el valor real, no el marcador")
}
