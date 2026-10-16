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
    expectEq(TurnRedaction.redact("ver token abc123"), "ver token abc123", "corto")
}

@Test func readingToolOutputIsMaskedAndOthersAreNot() {
    let outcome = ParentToolOutcome(ok: true, output: "nota 4111 1111 1111 1111", tool: "look")
    expectEq(TurnRedaction.redact(outcome, tool: "look").output, "nota \(mask)", "look")
    expectEq(TurnRedaction.redact(outcome, tool: "click").output, outcome.output, "click no lee contenido")
}
