import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// approval-after-cut (D2-C plus Karen's decision of 2026-10-01): when a cut
// leaves a parent sheet behind, the card goes and the island says, without
// jargon, why it stopped listening.

private let parked = ApprovalRequest(
    requestId: "r1", toolName: "open_url", summary: "open example.com", inputJSON: "{}")
private let openCall = ToolCallRef(
    id: "c1", name: "open_url", arguments: #"{"url":"https://example.com"}"#)

@MainActor private func sheetRig(approvals: any ApprovalsProvider) -> (VoiceHarness, FakeParentTools) {
    let tools = FakeParentTools(handledNames: ["open_url"])
    tools.setScriptedApproval(parked)
    let h = makeVoiceHarness(key: nil, language: .es, parentTools: tools, approvals: approvals)
    h.chat.rounds = [[.toolCalls([openCall])], [.text("Listo.")]]
    h.transcriber.stoppedText = "abre la página"
    return (h, tools)
}
