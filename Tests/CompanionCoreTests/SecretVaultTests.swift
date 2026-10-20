import CompanionTestKit
import Foundation
import Testing

@testable import CompanionCore

// Valores sintéticos: ninguno es un dato real.

@Test func aSecretBecomesAReferenceAndOnlyOpeningBringsItBack() {
    let key = "sk-abcdefghijklmnop1234"
    let (vault, text) = SecretVault().sealing("escribe \(key) y luego \(key)")
    expectEq(text, "escribe [[ref:1]] y luego [[ref:1]]", "el mismo valor, la misma referencia")
    expectEq(vault.opening("[[ref:1]]"), key, "abrir devuelve el valor")
    expect(vault.opening("[[ref:2]]") == nil, "una referencia desconocida no se abre")
    expectEq(vault.resealing("escribí \(key) en Nombre"), "escribí [[ref:1]] en Nombre",
             "la salida de una tool vuelve a la referencia")
    expectEq(SecretVault().sealing("hola Safari").text, "hola Safari", "sin secreto no cambia nada")
    expectEq(TurnRedaction.redact("escribe [[ref:12]]"), "escribe [[ref:12]]",
             "la redacción no tapa una referencia (con \"secret:\" la tapaba)")
}

/// Review M2: a short value used to rewrite references already put in, and
/// a one-digit PIN rewrote every digit of the output.
@Test func resealingNeverRewritesAReferenceOrOrdinaryDigits() {
    let (vault, _) = SecretVault().sealing("contraseña: secretito, pin: 1, sk-abcdefghijklmnopsecretito")
    let out = vault.resealing("sk-abcdefghijklmnopsecretito y secretito, paso 1")
    expectEq(out, "[[ref:3]] y [[ref:1]], paso 1", "una pasada, valores cortos fuera")
}

@Test func aFactWithAReferenceIsNotRemembered() {
    guard case .failure = MemoryTool.accepted("la clave del banco es [[ref:1]]") else {
        expect(false, "una referencia no se guarda en memoria")
        return
    }
}
