import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func rateLimitRetryTests() {
    testATooFastAnswerIsRetriedBeforeGivingUp()
    testTheWaitGrowsAndIsCapped()
    testTheHeaderGapIsMarkedNotHidden()
    testOtherFailuresAreNotRetried()
    testExhaustedRetriesStillSayRateLimited()
}

@MainActor func testATooFastAnswerIsRetriedBeforeGivingUp() {
    // El defecto: un 429 bajaba de peldaño y, sin siguiente peldaño, el
    // usuario leia "no hay proveedor disponible". La verdad era "espera diez
    // segundos" — un fallo temporal contado como fallo de configuracion.
    expect(RetryPolicy.shouldRetry(.rateLimited, attempt: 1),
           "el primer 429 se reintenta")
    expect(RetryPolicy.shouldRetry(.rateLimited, attempt: 2),
           "y el segundo")
    expect(!RetryPolicy.shouldRetry(.rateLimited, attempt: RetryPolicy.maxAttempts),
           "pero no para siempre: esperar sin fin es otra forma de colgarse")
}

@MainActor func testTheWaitGrowsAndIsCapped() {
    // Crece para no martillear al proveedor, y tiene techo porque una espera
    // sin fin es otra forma de colgarse.
    expect(RetryPolicy.delay(attempt: 2) > RetryPolicy.delay(attempt: 1),
           "cada intento espera mas que el anterior")
    expect(RetryPolicy.delay(attempt: 99) <= RetryPolicy.maxDelay,
           "y nunca mas del techo")
}

@MainActor func testTheHeaderGapIsMarkedNotHidden() {
    // `Retry-After` es lo que el proveedor pide de verdad, y no llega hasta
    // aqui: ChatTransport expone status y lineas, no cabeceras. Queda como
    // HACK con su gatillo, no como un parametro que nadie puede rellenar.
    guard let root = Conformance.repoRoot() else {
        print("  nota  [rateLimitRetry] fuera del checkout: no hay que escanear")
        return
    }
    let path = "Sources/CompanionCore/Chat/RetryPolicy.swift"
    let source = (try? String(
        contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
    expect(source.contains("enum RetryPolicy"), "\(path) se lee y declara RetryPolicy")
    expect(source.contains("HACK:") && source.contains("Retry-After"),
           "la carencia esta escrita, con su disparador de mejora")
}

@MainActor func testOtherFailuresAreNotRetried() {
    // Una clave mala no mejora por insistir.
    expect(!RetryPolicy.shouldRetry(.unauthorized, attempt: 1), "401 no")
    expect(!RetryPolicy.shouldRetry(.noProvider, attempt: 1), "sin proveedor no")
    // El timeout TAMPOCO se reintenta, y es una decision con numero detras:
    // turnTimeout son 60 s, asi que tres intentos son tres minutos esperando
    // una respuesta que el siguiente proveedor podia dar ya.
    expect(!RetryPolicy.shouldRetry(.timeout, attempt: 1),
           "un timeout baja de peldaño en vez de repetirse")
}

@MainActor func testExhaustedRetriesStillSayRateLimited() {
    // Y sobre todo: agotado el reintento, se dice lo que fue.
    expectEq(RetryPolicy.exhausted(.rateLimited), ChatError.rateLimited,
             "el error conserva su identidad hasta el final")
}
