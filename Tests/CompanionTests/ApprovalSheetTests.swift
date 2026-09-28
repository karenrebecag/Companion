import CompanionCore
@testable import CompanionUI
import Foundation
import Testing

// Wave 17 §6: the sheet for `bridge_session` shows `summary` (already
// `BridgeCopy.sheetTitle`) as its title, `BridgeCopy.sheetDetail` as its
// detail, and hides "remember" — that tool has no `ApprovalKey` to key a
// memory on (security review 2026-09-28, ApprovalMemoryTests).

@Test @MainActor func approvalSheetTests() async {
    await pinLanguage {
        testBridgeSessionUsesItsOwnTitleAndDetail()
        testBridgeSessionHidesRemember()
        testAnOrdinaryToolKeepsItsCatalogTitleAndOffersRemember()
    }
}

@MainActor func testBridgeSessionUsesItsOwnTitleAndDetail() {
    let request = ApprovalRequest(
        requestId: "1", toolName: "bridge_session",
        summary: BridgeCopy.sheetTitle(.en), inputJSON: #"{"client":"claude-code"}"#)
    let plan = ApprovalSheet.plan(for: request, language: .en)
    expectEq(plan.title, BridgeCopy.sheetTitle(.en), "hoja del puente: el título es el summary")
    expectEq(plan.detail, BridgeCopy.sheetDetail(.en), "hoja del puente: el detalle es BridgeCopy")
}

@MainActor func testBridgeSessionHidesRemember() {
    let request = ApprovalRequest(
        requestId: "1", toolName: "bridge_session",
        summary: BridgeCopy.sheetTitle(.es), inputJSON: "{}")
    let plan = ApprovalSheet.plan(for: request, language: .es)
    expect(!plan.showsRemember, "hoja del puente: sin recordar, no hay ApprovalKey")
}

@MainActor func testAnOrdinaryToolKeepsItsCatalogTitleAndOffersRemember() {
    let request = ApprovalRequest(
        requestId: "2", toolName: "open_url", summary: "abrir url", inputJSON: #"{"url":"https://x"}"#)
    let plan = ApprovalSheet.plan(for: request, language: .en)
    expectEq(plan.title, Localized.string("approval.title.parent"), "otra tool: título del catálogo")
    expect(plan.showsRemember, "otra tool: sigue ofreciendo recordar")
}
