import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// Wave 20c D5 review F2. The parked-sheet slot is shared across connections:
// a late continuation of a gone connection must only settle its own sheet.

@Test @MainActor func bridgeParkedSheetTests() {
    testALateSettleFromAGoneConnectionDoesNotWipeTheNewSheet()
    testAStaleWithdrawnIdIsNotConsumedByTheWrongConnection()
    testSettlingOwnSheetStillClearsItAndReportsWithdrawal()
}

private func sheet(_ id: String) -> ApprovalRequest {
    ApprovalRequest(requestId: id, toolName: "click", summary: "s", inputJSON: "{}")
}

@MainActor func testALateSettleFromAGoneConnectionDoesNotWipeTheNewSheet() {
    let parked = BridgeParkedSheet()
    _ = parked.park(sheet("a"), owner: 1)
    expectEq(parked.takeForWithdrawal()?.requestId, "a", "F2: A's sheet withdrawn when B arrives")
    _ = parked.park(sheet("b"), owner: 2)
    expect(parked.settleCurrent(owner: 1), "F2: A's late settle learns its own sheet was withdrawn")
    expectEq(parked.takeForWithdrawal()?.requestId, "b", "F2: B's sheet is still withdrawable")
}

@MainActor func testAStaleWithdrawnIdIsNotConsumedByTheWrongConnection() {
    let parked = BridgeParkedSheet()
    _ = parked.park(sheet("a"), owner: 1)
    _ = parked.takeForWithdrawal()
    _ = parked.park(sheet("b"), owner: 2)
    expect(!parked.settleCurrent(owner: 2), "F2: B's settle is not told A's sheet was withdrawn")
    expect(parked.settleCurrent(owner: 1), "F2: A's withdrawn mark survived B's settle")
}

@MainActor func testSettlingOwnSheetStillClearsItAndReportsWithdrawal() {
    let parked = BridgeParkedSheet()
    _ = parked.park(sheet("a"), owner: 1)
    expect(!parked.settleCurrent(owner: 1), "F2: answered normally, not withdrawn")
    expect(parked.takeForWithdrawal() == nil, "F2: own settle cleared the slot")
    _ = parked.park(sheet("c"), owner: 1)
    _ = parked.takeForWithdrawal()
    expect(parked.settleCurrent(owner: 1), "F2: withdrawn reported once")
    expect(!parked.settleCurrent(owner: 1), "F2: and only once")
}
