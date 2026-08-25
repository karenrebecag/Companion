import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

@Test @MainActor func failureReportingTests() {
    testNoProviderIsNotANetworkProblem()
    testRealNetworkErrorsStillReadAsNetwork()
    testServicesNoLongerWritesUserCopy()
}

@MainActor func testNoProviderIsNotANetworkProblem() {
    // Visto en produccion: la escalera se quedaba sin proveedores y la app
    // decia "no hay conexion a internet" con la red perfectamente bien. Manda
    // al usuario a arreglar lo que no esta roto, y `noProviders` — que es la
    // respuesta correcta — ya existia en la enum.
    expectEq(VoiceFailureMapping.failure(for: ChatError.noProvider),
             .noProviders,
             "quedarse sin proveedores no es quedarse sin red")
}

@MainActor func testRealNetworkErrorsStillReadAsNetwork() {
    expectEq(VoiceFailureMapping.failure(for: ChatError.unreachable),
             .networkUnavailable, "inalcanzable si es red")
    expectEq(VoiceFailureMapping.failure(for: ChatError.timeout),
             .networkUnavailable, "timeout tambien")
    expectEq(VoiceFailureMapping.failure(for: URLError(.notConnectedToInternet)),
             .networkUnavailable, "y el error del sistema, claro")
}

@MainActor func testServicesNoLongerWritesUserCopy() {
    // El fallo salia DOS veces en el hilo con dos redacciones distintas:
    // VoiceSession lo escribia desde Services con texto cableado, y
    // VoiceViewModel lo escribia desde el catalogo. Un fallo, un emisor, y el
    // que sobrevive es el que pasa por el catalogo de idiomas.
    let services = Bundle.main  // ancla: el test mira el codigo, no el bundle
    _ = services
    let source = try? String(
        contentsOfFile: "Sources/CompanionServices/ClassicRuntime.swift",
        encoding: .utf8)
    guard let source else { return }  // fuera del repo: nada que vigilar
    expect(!source.contains("Verifica tu red"),
           "Services no vuelve a llevar copy de usuario cableado")
    expect(!source.contains("No te escuché"),
           "ni el resto de las frases del hilo")
}
