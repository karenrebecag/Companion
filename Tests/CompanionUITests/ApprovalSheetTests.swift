import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// Wave 19-1: la hoja consume `ApprovalCopy` (Core). Aqui se fija lo que la
// hoja PROMETE mas alla del copy puro (ApprovalCopyTests): el puente nombra
// a quien pide y esconde recordar; permitir jamas tiene atajo de teclado.

@Test @MainActor func approvalSheetTests() {
    let bridge = ApprovalCopy.display(
        for: ApprovalRequest(
            requestId: "1", toolName: BridgePolicy.sessionApprovalTool,
            summary: BridgeCopy.sheetTitle(.en), inputJSON: #"{"client":"claude-code"}"#),
        language: .en)
    expectEq(bridge.title, "claude-code " + BridgeCopy.sheetTitle(.en),
             "hoja del puente: el titulo nombra al cliente")
    expect(BridgeCopy.sheetTitle(.es).contains("tu Mac"),
           "hoja del puente: pide usar tu Mac, no 'tus manos' (feedback 19-1b)")
    expect(BridgeCopy.sheetTitle(.en).contains("your Mac"), "hoja del puente: en ingles igual")
    expect(bridge.preview == nil, "hoja del puente: sin caja de detalle (19-1c)")
    expect(!bridge.showsRemember, "hoja del puente: sin recordar, no hay ApprovalKey")

    let ordinary = ApprovalCopy.display(
        for: ApprovalRequest(
            requestId: "2", toolName: "open_url", summary: "abrir url",
            inputJSON: #"{"url":"https://x.dev/a"}"#),
        language: .es)
    expect(ordinary.showsRemember, "otra tool: sigue ofreciendo recordar")

    // Un Return perdido no aprueba (security review 16): permitir es click.
    expect(ApprovalSheet.allowShortcut == nil, "hoja: permitir sin atajo de teclado")

    // El vector de Claude viaja en el bundle: si el empaquetado lo pierde,
    // este test lo dice antes que la hoja (19-1b).
    expect(ClaudeLogo.image != nil, "hoja: el logo de Claude carga del bundle")

    // La garantia 19-1: los botones de respuesta nunca salen de pantalla.
    // Un preview alto por saltos de linea scrollea aunque sea corto en
    // caracteres (review 19-1c).
    expect(!ApprovalSheet.previewScrolls("corto"), "preview corto abraza su texto")
    expect(ApprovalSheet.previewScrolls(String(repeating: "a", count: 401)),
           "preview largo scrollea")
    expect(ApprovalSheet.previewScrolls(String(repeating: "ln\n", count: 9)),
           "preview de muchas lineas scrollea aunque sea corto")
}
