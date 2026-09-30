import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Integration fix round 1, item 3 (C4): the session lists an MCP request
// before the approvals actor parks it. A spoken "no" in that window has
// nothing to withdraw, so it must not tell the model it was applied.

@Test @MainActor func mcpSpokenNoRaceTests() async {
    await testASpokenNoBeforeTheMCPRequestParksAsksForTheClick()
    await testASpokenNoOnAParkedMCPRequestStillResolves()
}

/// Parks a request only once the test opens the door, so the test can stand
/// in the window between the session listing it and the actor holding it.
private actor LateParkingApprovals: ApprovalsProvider {
    private var door: CheckedContinuation<Void, Never>?
    private var doorOpen = false
    private var pending: [String: CheckedContinuation<ApprovalResponse, Never>] = [:]

    var arrived: Bool { door != nil || doorOpen }
    var parked: Bool { !pending.isEmpty }

    func request(_ approval: ApprovalRequest) async -> ApprovalResponse {
        if !doorOpen { await withCheckedContinuation { door = $0 } }
        return await withCheckedContinuation { pending[approval.requestId] = $0 }
    }

    func openDoor() {
        doorOpen = true
        door?.resume()
        door = nil
    }

    func resolve(requestId: String, approved: Bool) async -> Bool {
        guard let continuation = pending.removeValue(forKey: requestId) else { return false }
        continuation.resume(returning: ApprovalResponse(requestId: requestId, approved: approved))
        return true
    }
}

private func mcpRequest() -> ApprovalRequest {
    ApprovalRequest(requestId: "m1", toolName: "docs/search", summary: "search", inputJSON: "{}", isMCP: true)
}

@MainActor func testASpokenNoBeforeTheMCPRequestParksAsksForTheClick() async {
    let approvals = LateParkingApprovals()
    let h = makeVoiceHarness(approvals: approvals)
    let deciding = Task { await h.session.noteMCPApproval(mcpRequest()) }
    await pumpUntilAsync("carrera mcp: la peticion va camino del actor") { await approvals.arrived }
    expect(!(await approvals.parked), "carrera mcp: previo, todavia no esta aparcada")
    expectEq(await h.session.answerPendingApproval(false), .needsClick,
             "carrera mcp: un no que no retiro nada pide el clic")
    await approvals.openDoor()
    await pumpUntilAsync("carrera mcp: ahora si esta aparcada") { await approvals.parked }
    _ = await approvals.resolve(requestId: "m1", approved: false)
    await deciding.value
}

@MainActor func testASpokenNoOnAParkedMCPRequestStillResolves() async {
    let approvals = LateParkingApprovals()
    await approvals.openDoor()
    let h = makeVoiceHarness(approvals: approvals)
    let deciding = Task { await h.session.noteMCPApproval(mcpRequest()) }
    await pumpUntilAsync("mcp aparcada: la hoja la tiene") { await approvals.parked }
    expectEq(await h.session.answerPendingApproval(false), .resolved,
             "mcp aparcada: el no hablado la rechaza")
    await deciding.value
    expect(!(await approvals.parked), "mcp aparcada: ya no espera")
}
