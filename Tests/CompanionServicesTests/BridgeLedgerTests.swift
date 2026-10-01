import CompanionCore
import CompanionCoreTestSupport
import CompanionServices
import CompanionTestKit
import Foundation
import Testing

/// Review D6 (code MEDIUM): the request ledger is bounded by bytes as well
/// as by count, takes a typed outcome instead of re-parsing the reply, and
/// its window rules are pinned here.

private func helloLine(_ id: Int) -> String {
    #"{"id":\#(id),"method":"hello","params":{"token":"tok","client":"claude-code","protocol":1}}"#
}

private func callLine(_ id: Int, _ name: String) -> String {
    #"{"id":\#(id),"method":"call","params":{"name":"\#(name)","arguments":{}}}"#
}

private func byeLine(_ id: Int) -> String { #"{"id":\#(id),"method":"bye"}"# }

private final class Tick: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date = date.addingTimeInterval(seconds) } }
}

private func session(
    _ tools: FakeParentTools, approvals: ScriptedApprovals = ScriptedApprovals(answer: true),
    tick: Tick = Tick()
) -> BridgeSession {
    BridgeSession(
        tools: tools, guard: ParentToolGuard(approvals: approvals),
        token: { "tok" }, language: { .en }, accessibility: { true }, now: { tick.now })
}

@Test func anOversizedReplyIsNotRetainedAndItsRepeatSaysSo() {
    var ledger = BridgeRequestLedger()
    _ = ledger.begin(1)
    ledger.finish(1, outcome: .answered(String(repeating: "x", count: BridgeRequestLedger.maxReplayBytes + 1)))
    expectEq(ledger.begin(1), .tooLargeToReplay, "the repeat is told the reply is too large")
    expectEq(ledger.retainedBytes, 0, "the big payload is not kept")

    _ = ledger.begin(2)
    ledger.finish(2, outcome: .answered(String(repeating: "x", count: BridgeRequestLedger.maxReplayBytes)))
    expectEq(ledger.begin(2), .replay(String(repeating: "x", count: BridgeRequestLedger.maxReplayBytes)),
             "a reply at the threshold still replays")
}

@Test func theTypedOutcomeFreesTheIdOnARefusalAndCachesOnAnswer() {
    var ledger = BridgeRequestLedger()
    _ = ledger.begin(1)
    ledger.finish(1, outcome: .refused)
    expectEq(ledger.begin(1), .fresh, "a refusal frees the id")
    ledger.finish(1, outcome: .answered("ok"))
    expectEq(ledger.begin(1), .replay("ok"), "an answer is cached")
    _ = ledger.begin(3)
    ledger.finish(3, outcome: .dropped)
    expectEq(ledger.begin(3), .fresh, "a reply nobody could send frees the id")
}

@Test func theOldestAnsweredIdIsEvictedFirstAndARunningOneSurvives() {
    var ledger = BridgeRequestLedger()
    _ = ledger.begin(0)
    for id in 1 ... (BridgeRequestLedger.capacity + 5) {
        _ = ledger.begin(id)
        ledger.finish(id, outcome: .answered("r\(id)"))
    }
    expectEq(ledger.begin(0), .inFlight, "an id still running is never evicted")

    var window = BridgeRequestLedger()
    for id in 0 ..< (BridgeRequestLedger.capacity + 1) {
        _ = window.begin(id)
        window.finish(id, outcome: .answered("r\(id)"))
    }
    expectEq(window.begin(0), .fresh, "the oldest answered id fell out of the window")
    expectEq(window.begin(BridgeRequestLedger.capacity), .replay("r\(BridgeRequestLedger.capacity)"),
             "the newest is kept")
}

@Test @MainActor func aRepeatOfAHugeReplyDoesNotRunAgain() async {
    let huge = String(repeating: "y", count: BridgeRequestLedger.maxReplayBytes * 2)
    let tools = FakeParentTools(
        handledNames: ["look"], scriptedOutcome: ParentToolOutcome(ok: true, output: huge, target: "Safari"))
    let bridge = session(tools)
    _ = await bridge.handle(line: helloLine(1))
    let first = await bridge.handle(line: callLine(2, "look"))
    expect(first.reply.utf8.count > BridgeRequestLedger.maxReplayBytes, "the first answer is the big one")
    let again = await bridge.handle(line: callLine(2, "look"))
    expectEq(tools.executeCalls.count, 1, "the id ran once")
    expect(again.reply.contains(BridgeCode.replyTooLarge), "the repeat gets a small too-large error")
    expect(again.reply.utf8.count < 1_000, "and not the payload")
    expect(!again.close, "a repeat is not a reason to hang up")
}

@Test @MainActor func aToolFailureIsAnAnswerAndIsReplayedNotRunAgain() async {
    let tools = FakeParentTools(
        handledNames: ["click"], scriptedOutcome: ParentToolOutcome(ok: false, output: "no", target: "Safari"))
    let bridge = session(tools)
    _ = await bridge.handle(line: helloLine(1))
    let first = await bridge.handle(line: callLine(2, "click"))
    let again = await bridge.handle(line: callLine(2, "click"))
    expect(first.reply.contains(#""ok":false"#), "the tool failed")
    expectEq(again.reply, first.reply, "ok:false is replayed")
    expectEq(tools.executeCalls.count, 1, "and not re-run")
}

@Test @MainActor func anUnknownToolFreesItsIdForARealCall() async {
    let tools = FakeParentTools(handledNames: ["look"])
    let bridge = session(tools)
    _ = await bridge.handle(line: helloLine(1))
    let refused = await bridge.handle(line: callLine(2, "brand_new_tool"))
    expect(refused.reply.contains(BridgeCode.unknownTool), "unknown tool refused")
    let real = await bridge.handle(line: callLine(2, "look"))
    expect(real.reply.contains(#""ok":true"#), "the id is free for a real call")
    expectEq(tools.executeCalls.count, 1, "and it ran once")
}

@Test @MainActor func aRateLimitedCallFreesItsIdOnceTheWindowSlides() async {
    let tick = Tick()
    let tools = FakeParentTools(handledNames: ["click"])
    let bridge = session(tools, tick: tick)
    _ = await bridge.handle(line: helloLine(1))
    for id in 10 ..< (10 + BridgePolicy.budgetPerMinute) { _ = await bridge.handle(line: callLine(id, "click")) }
    let limited = await bridge.handle(line: callLine(99, "click"))
    expect(limited.reply.contains(BridgeCode.rateLimited), "over budget")
    tick.advance(BridgePolicy.window + 1)
    let retry = await bridge.handle(line: callLine(99, "click"))
    expect(retry.reply.contains(#""ok":true"#), "the same id runs once the window slides")
}

@Test @MainActor func aDeniedCallFreesItsIdSoTheRepeatIsJudgedAgain() async {
    let tools = FakeParentTools(handledNames: ["click"])
    let approvals = ScriptedApprovals(answer: false)
    let bridge = session(tools, approvals: approvals)
    _ = await bridge.handle(line: helloLine(1))
    let denied = await bridge.handle(line: callLine(2, "click"))
    expect(denied.reply.contains(BridgeCode.deniedByUser), "denied by the user")
    expectEq(approvals.requests.count, 1, "one sheet so far")
    let after = await bridge.handle(line: callLine(2, "click"))
    // A denial closes the session, so the freed id meets the closed session
    // (no second sheet: nothing left to ask) instead of a cached denial.
    expect(after.reply.contains(BridgeCode.sessionClosed), "the repeat is judged afresh, by the closed session")
    expect(!after.reply.contains(BridgeCode.deniedByUser), "and is not the first answer replayed")
    expect(tools.executeCalls.isEmpty, "and nothing ran")
}

@Test @MainActor func byeResetsTheLedger() async {
    let tools = FakeParentTools(handledNames: ["look"])
    let bridge = session(tools)
    _ = await bridge.handle(line: helloLine(1))
    _ = await bridge.handle(line: callLine(2, "look"))
    _ = await bridge.handle(line: byeLine(3))
    _ = await bridge.handle(line: helloLine(1))
    _ = await bridge.handle(line: callLine(2, "look"))
    expectEq(tools.executeCalls.count, 2, "after bye the same id is a new request")
}

private final class Landed: @unchecked Sendable {
    private let lock = NSLock()
    private var reply: String?
    var value: String? { lock.withLock { reply } }
    func set(_ text: String) { lock.withLock { reply = text } }
}

/// One session, two connections: the gone connection's answer lands while
/// the new one has the same id running. Without the epoch guard the stale
/// finish would free the new connection's id and let it run twice.
@Test @MainActor func aStaleConnectionsAnswerDoesNotTouchTheNewLedger() async {
    let tools = FakeParentTools(handledNames: ["look"])
    let approvals = ScriptedApprovals(answer: true, park: true)
    let bridge = session(tools, approvals: approvals)
    _ = await bridge.handle(line: helloLine(1))
    let old = Task { await bridge.handle(line: callLine(2, "look")) }
    await pollUntilTrue { approvals.requests.count == 1 }
    await bridge.connectionClosed()

    _ = await bridge.handle(line: helloLine(1))
    let current = Task { await bridge.handle(line: callLine(2, "look")) }
    await pollUntilTrue { approvals.requests.count == 2 }
    let staleSheet = approvals.requests[0]
    let currentSheet = approvals.requests[1]

    _ = await approvals.resolve(requestId: staleSheet.requestId, approved: true)
    let oldReply = await old.value
    expectEq(oldReply.reply, "", "the gone connection's answer is dropped, not replayed")
    expectEq(tools.executeCalls.count, 0, "and it never ran")

    let repeated = Landed()
    let repeat2 = Task { repeated.set(await bridge.handle(line: callLine(2, "look")).reply) }
    await pollUntilTrue(timeout: 1) { repeated.value != nil || approvals.requests.count > 2 }
    expect(repeated.value?.contains(BridgeCode.busy) == true,
           "a re-sent id 2 on the new connection is answered busy, without a third sheet")
    // The ledger's own busy, not the policy's "another session is active"
    // that a freed id would meet on its way to a second sheet.
    expect(repeated.value?.contains("request 2 is already running") == true,
           "id 2 is still running on the new connection: the stale answer did not free it")
    expectEq(approvals.requests.count, 2, "so no second sheet was raised for it")

    _ = await approvals.resolve(requestId: currentSheet.requestId, approved: true)
    let currentReply = await current.value
    expect(currentReply.reply.contains(#""ok":true"#), "the new connection's own call completes")
    expectEq(tools.executeCalls.count, 1, "and ran exactly once")
    repeat2.cancel()
}
