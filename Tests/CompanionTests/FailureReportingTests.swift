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
    guard let root = Conformance.repoRoot() else {
        print("  nota  [failureReporting] fuera del checkout: no hay que escanear")
        return
    }
    // Un archivo ausente o vacio daria "no contiene" trivialmente: el ancla
    // obliga a que el escaneo haya leido el runtime de verdad.
    let path = "Sources/CompanionServices/Voice/Classic/ClassicRuntime.swift"
    let source = (try? String(
        contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
    expect(source.contains("final class ClassicRuntime"), "\(path) se lee y declara ClassicRuntime")
    guard !source.isEmpty else { return }
    expect(!source.contains("Verifica tu red"),
           "Services no vuelve a llevar copy de usuario cableado")
    expect(!source.contains("No te escuché"),
           "ni el resto de las frases del hilo")
}
