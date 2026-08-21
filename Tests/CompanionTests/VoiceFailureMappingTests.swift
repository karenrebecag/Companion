import CompanionCore
import CompanionServices
import Foundation
import Testing

@Test @MainActor func voiceFailureMappingTests() {
    testTransportErrorsMapToNetwork()
    testChatErrorsMap()
    testURLErrorsMap()
    testUnknownFallsBackToDrop()
}

@MainActor func testTransportErrorsMapToNetwork() {
    expectEq(
        VoiceFailureMapping.failure(for: VoiceTransportError.unreachable),
        .networkUnavailable,
        "transporte inalcanzable ⇒ sin conexión")
    expectEq(
        VoiceFailureMapping.failure(for: VoiceTransportError.timeout),
        .networkUnavailable,
        "timeout de apertura ⇒ sin conexión")
    expectEq(
        VoiceFailureMapping.failure(for: VoiceTransportError.unauthorized),
        .sessionDropped,
        "401 no es problema de red")
}

@MainActor func testChatErrorsMap() {
    expectEq(
        VoiceFailureMapping.failure(for: ChatError.unreachable),
        .networkUnavailable,
        "chat inalcanzable ⇒ sin conexión")
    expectEq(
        VoiceFailureMapping.failure(for: ChatError.unauthorized),
        .noProviders,
        "clave rechazada no es problema de red")
}

@MainActor func testURLErrorsMap() {
    expectEq(
        VoiceFailureMapping.failure(for: URLError(.notConnectedToInternet)),
        .networkUnavailable,
        "wifi apagado ⇒ sin conexión")
    expectEq(
        VoiceFailureMapping.failure(for: URLError(.networkConnectionLost)),
        .networkUnavailable,
        "red caída a mitad de turno ⇒ sin conexión")
    expectEq(
        VoiceFailureMapping.failure(for: URLError(.badURL)),
        .sessionDropped,
        "URL mala no es problema de red")
}

@MainActor func testUnknownFallsBackToDrop() {
    expectEq(
        VoiceFailureMapping.failure(for: nil), .sessionDropped,
        "sin error concreto ⇒ caída de sesión")
    expectEq(
        VoiceFailureMapping.failure(for: SecretStoreError.denied),
        .sessionDropped,
        "error ajeno ⇒ caída de sesión")
}
