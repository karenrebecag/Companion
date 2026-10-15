import CompanionTestKit
import Foundation
import Testing

@testable import CompanionCore

@Test func qaPolicyActsOnActAndConfirmBands() {
    expectEq(QAApprovalPolicy.decide(band: .act, tool: "look"), .act, "act actua")
    expectEq(QAApprovalPolicy.decide(band: .confirm, tool: "app:slack:send"), .act, "confirm actua")
}

@Test func qaPolicySendsCriticalToTheOwnerCheck() {
    expectEq(QAApprovalPolicy.decide(band: .critical, tool: "run_shell"), .ownerCheck, "critico pide prueba")
}

@Test func qaPolicyKeepsTheSessionSheetWhateverTheBand() {
    for band in [ActionBand.act, .confirm, .critical] {
        expectEq(
            QAApprovalPolicy.decide(band: band, tool: BridgePolicy.sessionApprovalTool), .sheet,
            "bridge_session conserva su hoja (\(band))")
    }
}

@Test func qaPolicyMapsEachOwnerCheckToItsOutcome() {
    expectEq(QAApprovalPolicy.outcome(for: .confirmed), .granted, "confirmed")
    expectEq(QAApprovalPolicy.outcome(for: .refused), .refused(code: "owner_refused"), "refused")
    expectEq(
        QAApprovalPolicy.outcome(for: .unavailable), .unavailable(code: "owner_unavailable"),
        "unavailable")
}

@Test func ownerReasonIsFixedInBothLanguages() {
    expectEq(ApprovalCopy.ownerReason(.es), "aprobar una acción crítica", "es")
    expectEq(ApprovalCopy.ownerReason(.en), "approve a critical action", "en")
}
