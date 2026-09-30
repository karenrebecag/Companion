import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Wave 20c D5 follow-up. A peer that is gone, quiet or only knocking must not
// keep the one bridge slot, leave a dead sheet on screen, drive the hands, or
// lock the caller out for something that was not a refusal.

@Test @MainActor func bridgeAbandonTests() async {
    await testJunkAndRejectedLinesDoNotKeepASessionAlive()
    await testAPeerThatLeavesMidSheetFreesTheSlotAndExecutesNothing()
    await testAPeerThatLeavesMidPerCallSheetExecutesNothing()
    await testStopsAndTimeoutsOfTheSessionSheetDoNotCoolTheCallerDown()
    await testStopsAndTimeoutsOfAPerCallSheetDoNotCoolTheCallerDown()
    await testApprovalsMarksItsOwnDeadlineAsTimedOut()
}

@MainActor func testJunkAndRejectedLinesDoNotKeepASessionAlive() async {
    let clock = IdleClock()
    let session = idleSession(FakeParentTools(), ScriptedApprovals(answer: true), clock: clock, timeout: 60)
    let pair = BridgePair()
    let serving = await openSession(session, pair)
    for junk in ["{}", "not json", call(20, "no_such_tool"), "{}"] {
        clock.advance(20)
        pair.send(junk)
        expect(pair.readLine() != nil, "idle: the peer gets an answer to \(junk)")
    }
    let expired = await session.expireIfIdle()
    let closed = !pair.connection.isOpen
    pair.closeClient()
    await serving.value
    expect(expired, "idle: lines that are not real activity do not hold the slot")
    expect(closed, "idle: the connection closed")
}

private struct Parked {
    let tools: FakeParentTools
    let approvals: ScriptedApprovals
    let session: BridgeSession
    let pair: BridgePair
    let released: ReleaseCount
    let done: ReleaseCount
    let serving: Task<Void, Never>
}

private func parkedCall(tool: String, parkAll: Bool) async -> Parked {
    let tools = FakeParentTools()
    let approvals = ScriptedApprovals(answer: true, park: parkAll)
    if tool != "look" {
        tools.setScriptedApproval(ApprovalRequest(
            requestId: "\(tool)-1", toolName: tool, summary: "s", inputJSON: "{}"))
        approvals.setPark(forTool: tool)
    }
    let session = makeSession(tools, approvals)
    let released = ReleaseCount()
    let pair = BridgePair(onClosed: { released.bump() })
    let done = ReleaseCount()
    let serving = Task.detached { await session.serve(pair.connection); done.bump() }
    pair.send(hello(1))
    _ = pair.readLine()
    pair.send(call(2, tool))
    await pollUntilTrue { approvals.requests.contains { $0.toolName == (parkAll ? BridgePolicy.sessionApprovalTool : tool) } }
    return Parked(tools: tools, approvals: approvals, session: session, pair: pair,
                  released: released, done: done, serving: serving)
}

@MainActor func testAPeerThatLeavesMidSheetFreesTheSlotAndExecutesNothing() async {
    let p = await parkedCall(tool: "look", parkAll: true)
    let sheet = p.approvals.requests.first
    p.pair.closeClient()
    await pollUntilTrue { p.done.value == 1 }
    let served = p.done.value == 1
    let withdrawals = p.approvals.resolutions.count
    if !served, let sheet { _ = await p.approvals.resolve(requestId: sheet.requestId, approved: false) }
    await p.serving.value
    expect(served, "EOF mid-sheet: serve ends without waiting for the sheet's own deadline")
    expectEq(withdrawals, 1, "EOF mid-sheet: the dead sheet was withdrawn")
    expectEq(p.approvals.resolutions.first?.requestId, sheet?.requestId, "EOF mid-sheet: that very sheet")
    expectEq(p.released.value, 1, "EOF mid-sheet: the slot is free for a reconnect")
    expectEq(p.tools.executeCalls.count, 0, "EOF mid-sheet: nothing executed for a departed peer")
}

@MainActor func testAPeerThatLeavesMidPerCallSheetExecutesNothing() async {
    let p = await parkedCall(tool: "click", parkAll: false)
    p.pair.connection.close()
    _ = await p.approvals.resolve(requestId: "click-1", approved: true)
    await pollUntilTrue { p.done.value == 1 }
    await p.serving.value
    expectEq(p.done.value, 1, "EOF mid per-call sheet: serve ends")
    expectEq(p.tools.executeCalls.count, 0, "EOF mid per-call sheet: even a late yes executes nothing")
}

private enum Abandon { case stop, timeout }

/// One connection that opens a sheet for `tool` and then abandons it.
private func abandonOnce(
    _ tool: String, parkAll: Bool, how: Abandon, session: BridgeSession,
    tools: FakeParentTools, approvals: ScriptedApprovals
) async {
    let pair = BridgePair()
    let finished = ReleaseCount()
    let serving = Task.detached { await session.serve(pair.connection); finished.bump() }
    pair.send(hello(1))
    _ = pair.readLine()
    let before = approvals.requests.count
    pair.send(call(2, tool))
    await pollUntilTrue { approvals.requests.count > before }
    switch how {
    case .stop: await session.stop()
    case .timeout:
        if let request = approvals.requests.last { _ = await approvals.timeOut(requestId: request.requestId) }
    }
    _ = pair.readLine()
    pair.closeClient()
    await pollUntilTrue { finished.value == 1 }
    let ended = finished.value == 1
    // A sheet nobody withdrew would park serve forever; unblock so a red
    // run reports instead of hanging.
    if !ended, let request = approvals.requests.last { _ = await approvals.resolve(requestId: request.requestId, approved: false) }
    await serving.value
    expect(ended, "abandon (\(how)): serve ended without waiting on a dead sheet")
}

@MainActor func testStopsAndTimeoutsOfTheSessionSheetDoNotCoolTheCallerDown() async {
    for how in [Abandon.stop, .timeout] {
        let tools = FakeParentTools()
        let approvals = ScriptedApprovals(park: true)
        let session = makeSession(tools, approvals)
        for _ in 0 ..< BridgePolicy.maxDenials {
            await abandonOnce("look", parkAll: true, how: how, session: session, tools: tools, approvals: approvals)
        }
        let pair = BridgePair()
        let serving = Task.detached { await session.serve(pair.connection) }
        pair.send(hello(1))
        let reply = pair.readLine() ?? "<silence>"
        expect(!reply.contains(BridgeCode.coolingDown) && reply.contains("tools"),
               "cool-down: \(how) x\(BridgePolicy.maxDenials) on the session sheet is not a denial: \(reply)")
        pair.closeClient()
        await serving.value
    }
}

@MainActor func testStopsAndTimeoutsOfAPerCallSheetDoNotCoolTheCallerDown() async {
    for how in [Abandon.stop, .timeout] {
        let tools = FakeParentTools()
        let approvals = ScriptedApprovals(answer: true)
        tools.setScriptedApproval(ApprovalRequest(
            requestId: "click-1", toolName: "click", summary: "s", inputJSON: "{}"))
        approvals.setPark(forTool: "click")
        let session = makeSession(tools, approvals)
        for _ in 0 ..< BridgePolicy.maxDenials {
            await abandonOnce("click", parkAll: false, how: how, session: session, tools: tools, approvals: approvals)
        }
        let pair = BridgePair()
        let serving = Task.detached { await session.serve(pair.connection) }
        pair.send(hello(1))
        let reply = pair.readLine() ?? "<silence>"
        expect(!reply.contains(BridgeCode.coolingDown) && reply.contains("tools"),
               "cool-down: \(how) x\(BridgePolicy.maxDenials) on a per-call sheet is not a denial: \(reply)")
        pair.closeClient()
        await serving.value
    }
}

@MainActor func testApprovalsMarksItsOwnDeadlineAsTimedOut() async {
    let approvals = Approvals(clock: RealtimeClock(), timeout: 0.05)
    let expired = await approvals.request(ApprovalRequest(
        requestId: "t-1", toolName: "click", summary: "s", inputJSON: "{}"))
    expect(!expired.approved && expired.timedOut, "deadline: denied and marked as timed out")

    // The deadline timer is wall-clock, so a deny racing a short deadline
    // loses on a stalled runner. A deadline far beyond the test keeps the
    // deny the only thing that can answer.
    let patient = Approvals(clock: RealtimeClock(), timeout: 60)
    let answered = Task { await patient.request(ApprovalRequest(
        requestId: "t-2", toolName: "click", summary: "s", inputJSON: "{}")) }
    let denyLanded = await resolveOncePending(patient, requestId: "t-2", approved: false)
    // Without a landed deny the request would sit out its whole deadline.
    if !denyLanded { answered.cancel() }
    let denied = await answered.value
    expect(denyLanded, "deadline: the deny reached a pending sheet")
    expect(!denied.approved && !denied.timedOut, "deadline: a user's deny is not a timeout")
}

/// `resolve` answers false until the request is registered; retrying it is
/// the only signal `Approvals` exposes that the sheet is actually pending.
private func resolveOncePending(
    _ approvals: Approvals, requestId: String, approved: Bool, within seconds: TimeInterval = 5
) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if await approvals.resolve(requestId: requestId, approved: approved) { return true }
        await Task.yield()
        do { try await Task.sleep(nanoseconds: 1_000_000) } catch { return false }
    }
    return false
}
