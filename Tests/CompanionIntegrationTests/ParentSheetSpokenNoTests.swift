import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// classic-spoken-yes-parent-sheet, phase 2b-2 (Karen's D3 and plan answer 3):
// a clear spoken "no" to a parent sheet that was asked refuses it, and the
// turn ends with only the fixed "no" line, without a second model round. A
// click on Deny keeps today's road: the model hears the refusal and answers.

private let refusal = Escalation.approvalRefusedSpoken(.es)
private let needsClick = Escalation.approvalNeedsClickSpoken(.es)
/// The rig's second model round: said only if the model got another turn.
private let modelAfterwards = "Listo."

/// The session reducer is not in this harness: the test plays it, answering
/// the sheet the way the reducer would once the spoken answer reaches it.
@MainActor private func answerAsTheReducer(
    _ rig: ParentSheetRig, _ seen: SessionEventBox, approved: Bool
) async {
    await pumpUntilAsync("the spoken answer reached the reducer") {
        seen.events.contains(.approvalSpoken(requestId: "r1", approved: approved))
    }
    _ = await rig.approvals.resolve(requestId: "r1", approved: approved)
}
