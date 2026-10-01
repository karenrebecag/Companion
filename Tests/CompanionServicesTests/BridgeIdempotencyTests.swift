import CompanionCore
import CompanionCoreTestSupport
import CompanionServices
import CompanionTestKit
import Foundation
import Testing

/// 20c D6 (M8a): a request id repeated on the same connection must not run
/// twice, for any tool, state and read tools included. A peer that resends
/// (a retry after a slow reply, or a replay) gets the first answer back.

private func helloLine(_ id: Int) -> String {
    #"{"id":\#(id),"method":"hello","params":{"token":"tok","client":"claude-code","protocol":1}}"#
}

private func callLine(_ id: Int, _ name: String) -> String {
    #"{"id":\#(id),"method":"call","params":{"name":"\#(name)","arguments":{}}}"#
}

private func makeSession(_ tools: FakeParentTools) -> BridgeSession {
    BridgeSession(
        tools: tools, guard: ParentToolGuard(approvals: ScriptedApprovals(answer: true)),
        token: { "tok" }, language: { .en }, accessibility: { true })
}

@Test @MainActor func aRepeatedRequestIdDoesNotExecuteTwice() async {
    for name in ["click", "look", "list_apps", "read_focused"] {
        let tools = FakeParentTools(handledNames: ["click", "look", "list_apps", "read_focused"])
        let session = makeSession(tools)
        _ = await session.handle(line: helloLine(1))
        let first = await session.handle(line: callLine(2, name))
        let again = await session.handle(line: callLine(2, name))
        expectEq(tools.executeCalls.count, 1, "\(name): the same id runs once")
        expectEq(again.reply, first.reply, "\(name): the repeat gets the first answer back")
        expect(!again.close, "\(name): a repeat is not a reason to hang up")
    }
}

@Test @MainActor func aRepeatedIdCannotBeUsedToRunADifferentTool() async {
    let tools = FakeParentTools(handledNames: ["click", "look"])
    let session = makeSession(tools)
    _ = await session.handle(line: helloLine(1))
    let first = await session.handle(line: callLine(2, "look"))
    let swapped = await session.handle(line: callLine(2, "click"))
    expectEq(tools.executeCalls.map(\.name), ["look"], "the id is spent by its first call, whatever the tool")
    expectEq(swapped.reply, first.reply, "the answer is the first one")
}

@Test @MainActor func distinctIdsStillRunAndANewConnectionStartsClean() async {
    let tools = FakeParentTools(handledNames: ["look"])
    let session = makeSession(tools)
    _ = await session.handle(line: helloLine(1))
    _ = await session.handle(line: callLine(2, "look"))
    _ = await session.handle(line: callLine(3, "look"))
    expectEq(tools.executeCalls.count, 2, "different ids both run")

    // The ledger belongs to the connection: after it goes away the same id
    // is a new request on the next one.
    await session.connectionClosed()
    _ = await session.handle(line: helloLine(1))
    _ = await session.handle(line: callLine(2, "look"))
    expectEq(tools.executeCalls.count, 3, "a new connection may reuse an id")
}

@Test @MainActor func aRepeatedIdWhileTheFirstIsStillRunningIsRefused() async {
    let tools = FakeParentTools(handledNames: ["look"])
    let approvals = ScriptedApprovals(answer: true, park: true)
    let session = BridgeSession(
        tools: tools, guard: ParentToolGuard(approvals: approvals),
        token: { "tok" }, language: { .en }, accessibility: { true })
    _ = await session.handle(line: helloLine(1))
    let first = Task { await session.handle(line: callLine(2, "look")) }
    await pollUntilTrue { !approvals.requests.isEmpty }
    let duplicate = await session.handle(line: callLine(2, "look"))
    expect(duplicate.reply.contains(BridgeCode.busy), "an id in flight is refused while it runs")
    if let sheet = approvals.requests.last { _ = await approvals.resolve(requestId: sheet.requestId, approved: true) }
    _ = await first.value
    expectEq(tools.executeCalls.count, 1, "and it ran once")
}

@Test func theRequestLedgerIsBounded() {
    var ledger = BridgeRequestLedger()
    for id in 0 ..< (BridgeRequestLedger.capacity + 10) {
        _ = ledger.begin(id)
        ledger.finish(id, outcome: .answered("r\(id)"))
    }
    expectEq(ledger.count, BridgeRequestLedger.capacity, "the ledger keeps a bounded window")
    if case .replay(let reply) = ledger.begin(BridgeRequestLedger.capacity + 9) {
        expectEq(reply, "r\(BridgeRequestLedger.capacity + 9)", "the newest id is still remembered")
    } else {
        expect(false, "the newest id must replay")
    }
}

@Test @MainActor func aCallRefusedUpFrontDoesNotSpendItsId() async {
    let tools = FakeParentTools(handledNames: ["look"])
    let session = makeSession(tools)
    let early = await session.handle(line: callLine(2, "look"))
    expect(early.reply.contains(BridgeCode.noSession), "no hello yet: no_session")
    _ = await session.handle(line: helloLine(1))
    _ = await session.handle(line: callLine(2, "look"))
    expectEq(tools.executeCalls.count, 1, "the same id runs once the session exists: nothing had run before")
}
