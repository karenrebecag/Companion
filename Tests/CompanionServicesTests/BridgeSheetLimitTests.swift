import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

// Wave 20c D5 review F1. Withdrawn and timed-out sheets are not denials, so
// the deny cool-down cannot bound how often a token-holding peer makes a
// sheet appear. A separate per-process limit counts EVERY sheet shown.

@Test @MainActor func bridgeSheetLimitTests() async {
    await testWithdrawnSessionSheetsStopFurtherSheetsAcrossReconnects()
    await testPerCallSheetsAreBoundedToo()
    await testTheLimitLiftsWhenTheWindowPasses()
    await testANormalSessionIsUnaffected()
}

private let sheetTool = "click"

private func clickTools() -> FakeParentTools {
    let tools = FakeParentTools()
    tools.setScriptedApproval(ApprovalRequest(
        requestId: "click-1", toolName: sheetTool, summary: "s", inputJSON: "{}"))
    return tools
}

/// hello -> call -> sheet parked -> EOF: the withdrawn shape, no denial.
@MainActor func testWithdrawnSessionSheetsStopFurtherSheetsAcrossReconnects() async {
    let tools = FakeParentTools()
    let approvals = ScriptedApprovals(park: true)
    let session = makeSession(tools, approvals)
    for i in 0 ..< BridgePolicy.maxSheetsPerWindow {
        let pair = BridgePair()
        let serving = Task.detached { await session.serve(pair.connection) }
        pair.send(hello(1))
        _ = pair.readLine()
        pair.send(call(2))
        await pollUntilTrue { approvals.requests.count == i + 1 }
        pair.closeClient()
        await serving.value
    }
    expectEq(approvals.requests.count, BridgePolicy.maxSheetsPerWindow, "F1: sheets up to the limit are shown")

    let pair = BridgePair()
    let serving = Task.detached { await session.serve(pair.connection) }
    pair.send(hello(1))
    let helloReply = pair.readLine() ?? "<silence>"
    expect(helloReply.contains("tools"), "F1: withdrawn sheets never turned into a deny cool-down: \(helloReply)")
    pair.send(call(2))
    let reply = pair.readLine() ?? "<silence>"
    expect(reply.contains(BridgeCode.coolingDown), "F1: the next call is refused: \(reply)")
    // The sheet window, not the denial count: no one denied anything here.
    expect(reply.contains("approval requests") && reply.contains("Wait 10 min"),
           "M1: names the sheet limit and its wait: \(reply)")
    pair.closeClient()
    await serving.value
    expectEq(approvals.requests.count, BridgePolicy.maxSheetsPerWindow, "F1: no sheet was raised past the limit")
    expectEq(tools.executeCalls.count, 0, "F1: nothing executed")
}

@MainActor func testPerCallSheetsAreBoundedToo() async {
    let tools = clickTools()
    let approvals = ScriptedApprovals(answer: true)
    let session = makeSession(tools, approvals)
    _ = await session.handle(line: hello(1))
    // The session sheet is the first one shown.
    for i in 1 ..< BridgePolicy.maxSheetsPerWindow {
        let r = await session.handle(line: call(10 + i, sheetTool))
        expect(r.reply.contains(#""ok":true"#), "F1: click \(i) is under the limit: \(r.reply)")
    }
    expectEq(approvals.requests.count, BridgePolicy.maxSheetsPerWindow, "F1: every shown sheet counted, approved too")
    let over = await session.handle(line: call(99, sheetTool))
    expect(over.reply.contains(BridgeCode.coolingDown), "F1: over the limit the call is refused: \(over.reply)")
    expectEq(approvals.requests.count, BridgePolicy.maxSheetsPerWindow, "F1: and no sheet is shown for it")
    expectEq(tools.executeCalls.count, BridgePolicy.maxSheetsPerWindow - 1, "F1: the refused click never ran")
}

@MainActor func testTheLimitLiftsWhenTheWindowPasses() async {
    let clock = IdleClock()
    let approvals = ScriptedApprovals(answer: true)
    let session = idleSession(FakeParentTools(), approvals, clock: clock)
    for _ in 0 ..< BridgePolicy.maxSheetsPerWindow {
        let pair = BridgePair()
        let serving = Task.detached { await session.serve(pair.connection) }
        pair.send(hello(1))
        _ = pair.readLine()
        pair.send(call(2))
        _ = pair.readLine()
        pair.closeClient()
        await serving.value
    }
    expectEq(approvals.requests.count, BridgePolicy.maxSheetsPerWindow, "F1: window full")
    clock.advance(BridgePolicy.sheetWindow + 1)
    let pair = BridgePair()
    let serving = Task.detached { await session.serve(pair.connection) }
    pair.send(hello(1))
    _ = pair.readLine()
    pair.send(call(2))
    let reply = pair.readLine() ?? "<silence>"
    pair.closeClient()
    await serving.value
    expect(!reply.contains(BridgeCode.coolingDown), "F1: after the window a sheet is allowed again: \(reply)")
    expectEq(approvals.requests.count, BridgePolicy.maxSheetsPerWindow + 1, "F1: the new sheet was shown")
}

@MainActor func testANormalSessionIsUnaffected() async {
    let tools = clickTools()
    let approvals = ScriptedApprovals(answer: true)
    let session = makeSession(tools, approvals)
    _ = await session.handle(line: hello(1))
    for i in 0 ..< 6 {
        let r = await session.handle(line: call(10 + i, sheetTool))
        expect(r.reply.contains(#""ok":true"#), "F1: normal use, click \(i): \(r.reply)")
    }
    expectEq(tools.executeCalls.count, 6, "F1: all six ran")
}
