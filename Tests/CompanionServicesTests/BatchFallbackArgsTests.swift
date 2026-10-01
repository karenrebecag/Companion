import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

@Test @MainActor func batchFallbackArgsTests() {
    testBatchCarriesThePermissionPosture()
}

@MainActor func testBatchCarriesThePermissionPosture() {
    // El camino de streaming pasa --permission-mode y --allowedTools; el batch
    // de respaldo no pasaba ninguno. Un especialista que cae a batch queda con
    // los permisos por defecto Y sin forma de pedir mas (no hay
    // --permission-prompt-tool en batch): no puede tocar disco, asi que
    // responde "no encontre nada" a preguntas que si tienen respuesta.
    // El prototipo SI llevaba estas banderas en su batch.
    guard let root = Conformance.repoRoot() else {
        print("  nota  [batchFallbackArgs] fuera del checkout: no hay que escanear")
        return
    }
    // Dentro del repo un archivo ausente o vacio es un fallo, no un pase en
    // vacio: si el fuente se mueve, el test debe gritar en vez de desarmarse.
    let path = "Sources/CompanionServices/Delegation/ClaudeCodeExecutor.swift"
    let source = (try? String(
        contentsOf: root.appendingPathComponent(path), encoding: .utf8)) ?? ""
    expect(source.contains("private func fallbackToBatch"),
           "\(path) se lee y trae el respaldo en batch")
    guard !source.isEmpty else { return }
    guard let start = source.range(of: "private func fallbackToBatch") else {
        expect(false, "el respaldo en batch sigue existiendo")
        return
    }
    let batch = String(source[start.lowerBound...].prefix(1200))
    // Wave 16b: both paths share `permissionArgs` (auto mode + deny list);
    // SpecialistAutoModeTests checks the batch launch's real arguments.
    expect(batch.contains("Self.permissionArgs"),
           "el batch declara su modo de permisos, el mismo que el streaming")
}
