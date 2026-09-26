import CompanionCore
@testable import CompanionServices
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
    let source = try? String(
        contentsOfFile: "Sources/CompanionServices/ClaudeCodeExecutor.swift",
        encoding: .utf8)
    guard let source else { return }  // fuera del repo: nada que vigilar
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
