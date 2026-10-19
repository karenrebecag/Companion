import CompanionTestKit
import Foundation
import Testing

@testable import CompanionCore

// Valores sintéticos: ninguno es un dato real.
private let mask = TurnRedaction.mask

@Test func jwtIsMaskedButTwoDottedWordsAreNot() {
    let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.c2lnbmF0dXJl"
    expectEq(TurnRedaction.redact("token \(jwt) fin"), "token \(mask) fin", "jwt")
    expectEq(TurnRedaction.redact("v1.2.3 y a.b.c"), "v1.2.3 y a.b.c", "tres segmentos sin eyJ")
}

@Test func cardsMaskOnlyWhenLuhnPasses() {
    expectEq(TurnRedaction.redact("tarjeta 4111 1111 1111 1111 ok"), "tarjeta \(mask) ok", "espacios")
    expectEq(TurnRedaction.redact("4111-1111-1111-1111"), mask, "guiones")
    expectEq(TurnRedaction.redact("4111111111111111"), mask, "juntos")
    expectEq(TurnRedaction.redact("pedido 4111 1111 1111 1112"), "pedido 4111 1111 1111 1112", "Luhn falla")
    expectEq(TurnRedaction.redact("tel 5512345678"), "tel 5512345678", "demasiado corto")
}

@Test func clabeNeedsItsCheckDigit() {
    expectEq(TurnRedaction.redact("CLABE 012180000112345671"), "CLABE \(mask)", "dígito válido")
    expectEq(TurnRedaction.redact("ref 012180000112345672"), "ref 012180000112345672", "dígito inválido")
}

@Test func curpAndRfcNeedTheirFormat() {
    expectEq(TurnRedaction.redact("CURP ABCD800101HDFRRN09."), "CURP \(mask).", "curp")
    expectEq(TurnRedaction.redact("ABCD800101AB1"), mask, "rfc persona fisica")
    expectEq(TurnRedaction.redact("ABC800101AB1"), mask, "rfc persona moral")
    expectEq(TurnRedaction.redact("ABCD801301AB1"), "ABCD801301AB1", "mes 13 no es fecha")
    expectEq(TurnRedaction.redact("ABCD800101HDFRRN0"), "ABCD800101HDFRRN0", "curp incompleta")
}

@Test func longHexIsMaskedOnlyAfterAKeyword() {
    let hex = String(repeating: "a1b2c3d4", count: 5)
    expectEq(TurnRedaction.redact("Client secret: \(hex)"), "Client secret: \(mask)", "secret")
    expectEq(TurnRedaction.redact("client id \(hex)"), "client id \(mask)", "client")
    expectEq(TurnRedaction.redact("commit \(hex)"), "commit \(hex)", "sin palabra clave")
    expectEq(TurnRedaction.redact("ver token abc"), "ver token abc", "corto")
}

@Test func everyToolOutputIsMaskedButOnlyReadersGetTheNote() {
    let outcome = ParentToolOutcome(ok: true, output: "nota 4111 1111 1111 1111", tool: "look")
    let read = TurnRedaction.redact(outcome, tool: "look").output
    expect(read.hasPrefix("nota \(mask)\n(1 value(s) hidden"), "look: tapa y avisa")
    expect(TurnRedaction.redact(outcome, tool: "click").output == "nota \(mask)", "click: tapa sin aviso")
    expect(TurnRedaction.redact(
        ParentToolOutcome(ok: true, output: "sin secretos"), tool: "look").output == "sin secretos", "nada que avisar")
}

@Test func cardGluedToOtherDigitsStillMasks() {
    expectEq(TurnRedaction.redact("4111 1111 1111 1111 123"), "\(mask) 123", "tarjeta + CVV")
    expectEq(TurnRedaction.redact("4111.1111.1111.1111"), mask, "puntos")
    expectEq(TurnRedaction.redact("CLABE 0121 8000 0112 3456 71"), "CLABE \(mask)", "clabe con espacios")
}

@Test func moreKeyFamiliesAreMasked() {
    for secret in ["sk_live_abcdefghijklmnop1234", "sk_test_abcdefghijklmnop1234", "rk_live_abcdefghijklmnop1234",
                   "sb_secret_abcdefghijklmnop1234", "AIza" + String(repeating: "a", count: 35),
                   "sk-abcdefghijklmnop1234"] {
        expectEq(TurnRedaction.redact("k \(secret) z"), "k \(mask) z", secret)
    }
    expectEq(TurnRedaction.redact("eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoiYSJ9"), mask, "jwt cortado")
}

@Test func aSecretLabelAnywhereInALineMasksItsValue() {
    expectEq(TurnRedaction.redact("ver client secret: Xy8Q~abcdefghij ok"), "ver client secret: \(mask) ok", "azure")
    expectEq(TurnRedaction.redact("la clave=hunter22 fin"), "la clave=\(mask) fin", "clave")
    expectEq(TurnRedaction.redact("sin dos puntos clave del mapa"), "sin dos puntos clave del mapa", "sin valor")
}

@Test func looseBase64BodyIsMaskedButAPathIsNot() {
    let body = String(repeating: "Ab3dEf7hIj", count: 7)
    expectEq(TurnRedaction.redact("pem \(body)"), "pem \(mask)", "base64 largo")
    let path = "/Users/ana/Library/Application/Support/Algo/Muy/Largo/De/Verdad/Por/Aqui/Mismo/Ok"
    expectEq(TurnRedaction.redact(path), path, "ruta larga")
}

@Test func decimalNumbersAreNotCardsButARealCardStillIs() {
    let json = #"{"language":"es","confidence":0.9999963045120239}"#
    expectEq(TurnRedaction.redact(json), json, "float largo")
    expectEq(TurnRedaction.redact("version 2026.10.16.1234567890123"), "version 2026.10.16.1234567890123", "version")
    expectEq(TurnRedaction.redact("tarjeta 4111.1111.1111.1111"), "tarjeta \(mask)", "tarjeta con puntos")
    expectEq(TurnRedaction.redact(#"{"confidence":0.99,"card":"4111111111111111"}"#), #"{"confidence":0.99,"card":"\#(mask)"}"#, "tarjeta real")
}

@Test func aCardNextToADecimalIsStillMasked() {
    expectEq(TurnRedaction.redact("total 9.99 4111111111111111"), "total 9.99 \(mask)", "precio")
    expectEq(TurnRedaction.redact("v1.2 4111111111111111"), "v1.2 \(mask)", "version")
    expectEq(TurnRedaction.redact("ip 10.0.0.1 5500000000000004"), "ip 10.0.0.1 \(mask)", "ip")
    expectEq(TurnRedaction.redact("4111111111111111.5"), "\(mask).5", "fraccion pegada")
    expectEq(TurnRedaction.redact("3.5 032180000118359719"), "3.5 \(mask)", "clabe")
    expectEq(TurnRedaction.redact("4111111111111111 5500000000000004"), "\(mask) \(mask)", "dos tarjetas")
}

// QA 606: the model's reply read "Passkeys: iCloud ..." and the label rule
// masked "iCloud" as if it were a password. A label followed by a plain
// word is prose; a label followed by a value with a digit, or a long run of
// letters, is still a secret.
@Test func aLabelFollowedByAPlainWordIsProseNotASecret() {
    expectEq(TurnRedaction.redact("Passkeys: iCloud Keychain guarda las claves"),
             "Passkeys: iCloud Keychain guarda las claves", "passkeys: iCloud")
    expectEq(TurnRedaction.redact("Token: Android y Autofill"),
             "Token: Android y Autofill", "token: palabra corta sin dígitos")
}

@Test func aLabelFollowedByAValueWithDigitsOrLengthStillMasks() {
    expectEq(TurnRedaction.redact("ver password: hunter2x fin"), "ver password: \(mask) fin", "con dígito")
    expectEq(TurnRedaction.redact("ver clave: correcthorse fin"), "ver clave: \(mask) fin", "letras largas")
    expectEq(TurnRedaction.redact("ver token: abcdefghijkl fin"), "ver token: \(mask) fin", "doce letras")
}
