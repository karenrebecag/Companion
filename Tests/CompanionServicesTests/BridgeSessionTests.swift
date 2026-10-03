import CompanionCore
import CompanionCoreTestSupport
import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// Wave 17 (spec §5, filas 5-13). El actor del protocolo: hoja en la primera
// call (no en hello), presupuesto, pausa/reanuda, y el gate de cada llamada
// con `said: ""` porque el puente no tiene palabras de la usuaria.
@Test @MainActor func bridgeSessionTests() async {
    await testHelloBadTokenClosesGoodTokenLists()
    await testFirstCallDeniedClosesSession()
    await testFirstCallApprovedOpensAndExecutes()
    await testBridgeSessionSheetIsNeverRememberedRequestAlwaysAsked()
    await testPerCallGateDeniedAndApproved()
    await testTypeTextGateSeesEmptySaid()
    await testArgumentsPassThroughUnchangedAndOpenAppDoesNotDoublePin()
    await testCallBeforeHelloIsNoSession()
    await testCallAfterStopIsSessionClosed()
    await testSessionClosedNamesTheWayBack()
    await testPauseIsPausedResumeProceedsAndRepins()
    await testUnknownToolIsUnknownTool()
    await testAKnownToolNotReadyNamesTheReason()
    await testThirtyFirstWriteIsRateLimited()
    await testSixtyFirstReadIsRateLimitedWithItsOwnWait()
    await testBusyNamesAnOpenSheetApartFromAnotherAgent()
    await testHelloDuringAVoiceTurnIsPaused()
    await testByeClosesAndNextHelloProceeds()
    await testLogNeverLeaksArgumentsOrOutput()
    await testStopWithdrawsPendingSheetAndClosesSession()
    await testOnActionFiresForSuccessfulWriteCallsOnly()
    await testOnCallFiresForEverySuccessfulCall()
    await testOversizedLineThroughHandleClosesTheConnection()
    await testABadArgumentIsInvalidArgsBeforeAnySheet()
    await testEveryKindOfBadArgumentIsInvalidArgsByName()
    await testBadArgumentsSpendNoRateBudget()
}

// MARK: - wire helpers

private func helloLine(id: Int, token: String, client: String = "claude-code") -> String {
    #"{"id":\#(id),"method":"hello","params":{"token":"\#(token)","client":"\#(client)","protocol":1}}"#
}

private func callLine(id: Int, name: String, argumentsJSON: String = "{}") -> String {
    #"{"id":\#(id),"method":"call","params":{"name":"\#(name)","arguments":\#(argumentsJSON)}}"#
}

private func byeLine(id: Int) -> String {
    #"{"id":\#(id),"method":"bye"}"#
}

/// `try?` here is a test-only JSON peek, not the production ban (gates.sh
/// only scans Sources).
private func callResultOutput(_ line: String) -> String? {
    guard let data = line.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let result = obj["result"] as? [String: Any]
    else { return nil }
    return result["output"] as? String
}

private func session(
    tools: FakeParentTools, approvals: (any ApprovalsProvider)? = nil, token: String = "tok",
    onAction: @escaping @Sendable (String) -> Void = { _ in },
    onCall: @escaping @Sendable (String) -> Void = { _ in }
) -> BridgeSession {
    BridgeSession(
        tools: tools, guard: ParentToolGuard(approvals: approvals),
        token: { token }, language: { .en }, accessibility: { true }, onAction: onAction,
        onCall: onCall)
}

private func waitUntil(timeout: TimeInterval = 2, _ pred: @escaping @Sendable () -> Bool) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !pred(), Date() < deadline {
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
}

// MARK: - 5. hello

@MainActor func testHelloBadTokenClosesGoodTokenLists() async {
    let s = session(tools: FakeParentTools())

    let bad = await s.handle(line: helloLine(id: 1, token: "wrong"))
    expect(bad.close, "bad token: closes the connection")
    expect(bad.reply.contains(BridgeCode.badToken), "bad token: code bad_token")

    let good = await s.handle(line: helloLine(id: 2, token: "tok"))
    expect(!good.close, "good token: stays open")
    expect(good.reply.contains("look") && good.reply.contains("click"),
           "good token: hello lists the fake's specs")
    expect(await s.state == .listed, "good token: state listed")
}

// MARK: - 6. first call denied

@MainActor func testFirstCallDeniedClosesSession() async {
    let tools = FakeParentTools()
    let approvals = ScriptedApprovals(answer: false)
    let s = session(tools: tools, approvals: approvals)

    _ = await s.handle(line: helloLine(id: 1, token: "tok"))
    let result = await s.handle(line: callLine(id: 2, name: "look"))

    expect(result.reply.contains(BridgeCode.deniedByUser), "denied: code denied_by_user")
    expect(await s.state == .closed, "denied: session closed")
    expect(tools.executeCalls.isEmpty, "denied: execute never runs")
    expect(approvals.requests.contains { $0.toolName == "bridge_session" },
           "denied: the sheet asked for bridge_session")
}

// MARK: - 7. first call approved / remembered

@MainActor func testFirstCallApprovedOpensAndExecutes() async {
    let tools = FakeParentTools()
    let approvals = ScriptedApprovals(answer: true)
    let s = session(tools: tools, approvals: approvals)

    _ = await s.handle(line: helloLine(id: 1, token: "tok"))
    let result = await s.handle(line: callLine(id: 2, name: "look"))

    expect(result.reply.contains(#""ok":true"#), "approved: call succeeds")
    expectEq(tools.executeCalls.count, 1, "approved: execute called once")
    expectEq(tools.beginTurnCount, 1, "approved: beginTurn called once")
    expect(await s.state == .open(until: nil), "approved: state open")
}

/// Security review 2026-09-28 (HIGH): `bridge_session` has no `ApprovalKey`
/// (see `ApprovalMemoryTests.testBridgeSessionIsNeverRemembered`), so even
/// a provider with a "remembered: true" answer sitting in memory for some
/// OTHER tool must still ask — `remembered()` never fires for this one.
/// One sheet per connection, every time.
@MainActor func testBridgeSessionSheetIsNeverRememberedRequestAlwaysAsked() async {
    let tools = FakeParentTools()
    // `remembered: true` here would (wrongly) skip `request()` if the fake
    // did not gate on `ApprovalKey.from` the way the real actor does.
    let approvals = ScriptedApprovals(answer: true, remembered: true)
    let s = session(tools: tools, approvals: approvals)

    _ = await s.handle(line: helloLine(id: 1, token: "tok"))
    let result = await s.handle(line: callLine(id: 2, name: "look"))

    expect(!result.reply.contains(BridgeCode.deniedByUser), "not denied: the scripted answer approves")
    expect(approvals.requests.contains { $0.toolName == "bridge_session" },
           "bridge_session: request() was asked — remembered() never shortcuts it")
    expectEq(tools.executeCalls.count, 1, "asked and approved: execute still runs")
}

// MARK: - 8. per-call gate

@MainActor func testPerCallGateDeniedAndApproved() async {
    let clickRequest = ApprovalRequest(
        requestId: "click-1", toolName: "click", summary: "delete", inputJSON: "{}")

    let deniedTools = FakeParentTools()
    deniedTools.setScriptedApproval(clickRequest)
    let deniedApprovals = ScriptedApprovals(answer: true) // approves bridge_session
    deniedApprovals.setAnswer(false, forTool: "click") // denies the click itself
    let denied = session(tools: deniedTools, approvals: deniedApprovals)
    _ = await denied.handle(line: helloLine(id: 1, token: "tok"))
    let deniedResult = await denied.handle(line: callLine(id: 2, name: "click"))
    expect(deniedResult.reply.contains(#""ok":false"#), "per-call denied: ok false")
    expect(callResultOutput(deniedResult.reply)?.hasPrefix("denied_by_user") == true,
           "per-call denied: output starts with denied_by_user")
    expect(deniedTools.executeCalls.isEmpty, "per-call denied: execute not called")

    let approvedTools = FakeParentTools()
    approvedTools.setScriptedApproval(clickRequest)
    let approvedApprovals = ScriptedApprovals(answer: true)
    let approved = session(tools: approvedTools, approvals: approvedApprovals)
    _ = await approved.handle(line: helloLine(id: 1, token: "tok"))
    let approvedResult = await approved.handle(line: callLine(id: 2, name: "click"))
    expect(approvedResult.reply.contains(#""ok":true"#), "per-call approved: ok true")
    expectEq(approvedTools.grantedCalls.count, 1, "per-call approved: granted called")
    expectEq(approvedTools.executeCalls.count, 1, "per-call approved: execute called")
}

// MARK: - 9. type_text: no words spoken

@MainActor func testTypeTextGateSeesEmptySaid() async {
    let tools = FakeParentTools()
    tools.setScriptedApproval(ApprovalRequest(
        requestId: "tt-1", toolName: "type_text", summary: "type", inputJSON: "{}"))
    let s = session(tools: tools, approvals: ScriptedApprovals(answer: true))

    _ = await s.handle(line: helloLine(id: 1, token: "tok"))
    _ = await s.handle(line: callLine(id: 2, name: "type_text", argumentsJSON: #"{"text":"hola"}"#))

    expect(!tools.saidSeen.isEmpty && tools.saidSeen.allSatisfy(\.isEmpty),
           "type_text: the gate always sees said == \"\"")
}

// MARK: - 10/11. arguments pass through; open_app does not double-pin

@MainActor func testArgumentsPassThroughUnchangedAndOpenAppDoesNotDoublePin() async {
    let tools = FakeParentTools(handledNames: ["look", "open_app"])
    let s = session(tools: tools, approvals: ScriptedApprovals(answer: true))

    _ = await s.handle(line: helloLine(id: 1, token: "tok"))
    _ = await s.handle(line: callLine(id: 2, name: "look"))
    expectEq(tools.beginTurnCount, 1, "session open: beginTurn once")

    let argsJSON = #"{"name":"Safari"}"#
    _ = await s.handle(line: callLine(id: 3, name: "open_app", argumentsJSON: argsJSON))
    expectEq(tools.executeCalls.last?.argumentsJSON, argsJSON,
             "open_app: arguments pass through unchanged")
    expectEq(tools.beginTurnCount, 1,
             "open_app: the session does not re-pin — ParentToolRunner does that itself")
}

// MARK: - 12-session. lifecycle

@MainActor func testCallBeforeHelloIsNoSession() async {
    let s = session(tools: FakeParentTools())
    let result = await s.handle(line: callLine(id: 1, name: "look"))
    expect(result.reply.contains(BridgeCode.noSession), "before hello: no_session")
}

@MainActor func testCallAfterStopIsSessionClosed() async {
    let tools = FakeParentTools()
    let s = session(tools: tools, approvals: ScriptedApprovals(answer: true))
    _ = await s.handle(line: helloLine(id: 1, token: "tok"))
    _ = await s.handle(line: callLine(id: 2, name: "look"))
    await s.stop()
    let result = await s.handle(line: callLine(id: 3, name: "look"))
    expect(result.reply.contains(BridgeCode.sessionClosed), "after stop: session_closed")
}

// Audit H3: after a denied or expired sheet every call read "session is closed" for up to the
// idle close, with nothing the agent could do. A new hello on the same connection is accepted.
@MainActor func testSessionClosedNamesTheWayBack() async {
    let approvals = ScriptedApprovals(answer: false)
    let s = session(tools: FakeParentTools(), approvals: approvals)
    _ = await s.handle(line: helloLine(id: 1, token: "tok"))
    _ = await s.handle(line: callLine(id: 2, name: "look"))
    let closed = await s.handle(line: callLine(id: 3, name: "look"))
    expect(closed.reply.contains(BridgeCode.sessionClosed), "after a denial: session_closed")
    expect(closed.reply.contains("hello again") && closed.reply.contains("retry the call")
           && closed.reply.contains("sheet"), "session_closed names the way back: \(closed.reply)")
    let again = await s.handle(line: helloLine(id: 4, token: "tok"))
    expect(again.reply.contains("\"tools\""), "the new hello lists tools: \(again.reply)")
    // The promise in the message: the call after that hello asks the user again.
    let asked = approvals.requests.count
    let retried = await s.handle(line: callLine(id: 5, name: "look"))
    expectEq(approvals.requests.count, asked + 1, "the retried call raises a new sheet")
    expect(!retried.reply.contains(BridgeCode.sessionClosed), "and is judged by it: \(retried.reply)")
}

@MainActor func testPauseIsPausedResumeProceedsAndRepins() async {
    let tools = FakeParentTools()
    let s = session(tools: tools, approvals: ScriptedApprovals(answer: true))
    _ = await s.handle(line: helloLine(id: 1, token: "tok"))
    _ = await s.handle(line: callLine(id: 2, name: "look"))
    expectEq(tools.beginTurnCount, 1, "opened: beginTurn once")

    await s.pause()
    let paused = await s.handle(line: callLine(id: 3, name: "look"))
    expect(paused.reply.contains(BridgeCode.paused), "paused: its own code: \(paused.reply)")
    expect(paused.reply.contains("retry"), "paused: says to retry")

    await s.resume()
    expectEq(tools.beginTurnCount, 2, "resume: beginTurn called again")
    let resumed = await s.handle(line: callLine(id: 4, name: "look"))
    expect(!resumed.reply.contains("\"error\""), "resume: proceeds")
}

@MainActor func testUnknownToolIsUnknownTool() async {
    let tools = FakeParentTools(handledNames: [])
    let s = session(tools: tools)
    _ = await s.handle(line: helloLine(id: 1, token: "tok"))
    let result = await s.handle(line: callLine(id: 2, name: "does_not_exist"))
    expect(result.reply.contains(BridgeCode.unknownTool), "unknown tool: unknown_tool")
}

/// Wave 20b D4: "not now" is not "does not exist" - the model retries a
/// tool it was told is missing, and never brings the target app forward.
@MainActor func testAKnownToolNotReadyNamesTheReason() async {
    let tools = FakeParentTools(handledNames: [], unavailable: ["look": "self_in_front"])
    let s = session(tools: tools)
    _ = await s.handle(line: helloLine(id: 1, token: "tok"))
    let front = await s.handle(line: callLine(id: 2, name: "look"))
    expect(front.reply.contains(BridgeCode.selfInFront), "look con Companion delante: self_in_front")
    expect(front.reply.contains("Companion is in front"), "el mensaje dice que hacer")
    expect(!front.reply.contains(BridgeCode.unknownTool), "no es unknown_tool")
    let gone = await s.handle(line: callLine(id: 3, name: "does_not_exist"))
    expect(gone.reply.contains(BridgeCode.unknownTool), "un nombre que no existe sigue siendo unknown_tool")
    tools.setUnavailable(["click": "needs_accessibility", "see": "not_available"])
    let ax = await s.handle(line: callLine(id: 4, name: "click"))
    expect(ax.reply.contains("needs_accessibility"), "sin Accesibilidad: needs_accessibility")
    expect(ax.reply.contains("Privacy & Security > Accessibility"), "M1: nombra la ruta: \(ax.reply)")
    let none = await s.handle(line: callLine(id: 5, name: "see"))
    expect(none.reply.contains(BridgeCode.notAvailable), "sin respaldo: not_available")
}

@MainActor func testThirtyFirstWriteIsRateLimited() async {
    let tools = FakeParentTools(handledNames: ["click"])
    let s = session(tools: tools, approvals: ScriptedApprovals(answer: true))
    _ = await s.handle(line: helloLine(id: 1, token: "tok"))

    // Call 1 goes through the approval flow, which re-admits and records
    // itself as the first write; 29 more fill the 30-write budget.
    let first = await s.handle(line: callLine(id: 2, name: "click"))
    expect(!first.reply.contains(BridgeCode.rateLimited), "write 1 (approval flow): under budget")
    for i in 0 ..< 29 {
        let result = await s.handle(line: callLine(id: i + 3, name: "click"))
        expect(!result.reply.contains(BridgeCode.rateLimited), "write \(i + 2): under budget")
    }
    let result31 = await s.handle(line: callLine(id: 40, name: "click"))
    expect(result31.reply.contains(BridgeCode.rateLimited), "write 31: rate_limited")
    // The real clock moves between calls, so the exact figure can be 1 min or just under it; what
    // must hold is that it is the minute of the action window, not "retry at once".
    expect(result31.reply.contains(", then retry") && !result31.reply.contains("Wait 1 s,"),
           "M1: names the action window's wait: \(result31.reply)")
}

@MainActor func testSixtyFirstReadIsRateLimitedWithItsOwnWait() async {
    let tools = FakeParentTools(handledNames: ["look"])
    let s = session(tools: tools, approvals: ScriptedApprovals(answer: true))
    _ = await s.handle(line: helloLine(id: 1, token: "tok"))
    for i in 0 ..< BridgePolicy.readBudgetPerMinute {
        _ = await s.handle(line: callLine(id: i + 2, name: "look"))
    }
    let over = await s.handle(line: callLine(id: 100, name: "look"))
    expect(over.reply.contains(BridgeCode.rateLimited), "read 61: rate_limited")
    // Sized from the read budget: the write budget is empty and would say 1 s.
    expect(over.reply.contains(", then retry") && !over.reply.contains("Wait 1 s,"),
           "M1: the read budget's wait: \(over.reply)")
}

@MainActor func testBusyNamesAnOpenSheetApartFromAnotherAgent() async {
    let tools = FakeParentTools()
    let approvals = ScriptedApprovals(park: true)
    let s = session(tools: tools, approvals: approvals)
    _ = await s.handle(line: helloLine(id: 1, token: "tok"))
    let parked = Task { await s.handle(line: callLine(id: 2, name: "look")) }
    await waitUntil { !approvals.requests.isEmpty }
    let waiting = await s.handle(line: callLine(id: 3, name: "look"))
    expect(waiting.reply.contains(BridgeCode.busy), "sheet up: busy")
    expect(waiting.reply.contains("approval sheet is open"), "M1: names the sheet: \(waiting.reply)")
    let again = await s.handle(line: helloLine(id: 4, token: "tok"))
    expect(again.reply.contains("approval sheet is open"), "M1: a hello meanwhile too: \(again.reply)")
    await s.stop()
    _ = await parked.value

    let open = session(tools: FakeParentTools(), approvals: ScriptedApprovals(answer: true))
    _ = await open.handle(line: helloLine(id: 1, token: "tok"))
    _ = await open.handle(line: callLine(id: 2, name: "look"))
    let other = await open.handle(line: helloLine(id: 3, token: "tok"))
    expect(other.reply.contains(BridgeCode.busy), "session open: a second hello is busy")
    expect(other.reply.contains("Another agent"), "M1: names the other agent: \(other.reply)")
    expect(!other.reply.contains("approval sheet"), "and not a sheet")
}

@MainActor func testHelloDuringAVoiceTurnIsPaused() async {
    let s = session(tools: FakeParentTools(), approvals: ScriptedApprovals(answer: true))
    _ = await s.handle(line: helloLine(id: 1, token: "tok"))
    _ = await s.handle(line: callLine(id: 2, name: "look"))
    await s.pause()
    let hello = await s.handle(line: helloLine(id: 3, token: "tok"))
    expect(hello.reply.contains(BridgeCode.paused), "M1: a voice turn is paused, not busy: \(hello.reply)")
}

@MainActor func testByeClosesAndNextHelloProceeds() async {
    let tools = FakeParentTools()
    let s = session(tools: tools, approvals: ScriptedApprovals(answer: true))
    _ = await s.handle(line: helloLine(id: 1, token: "tok"))
    let bye = await s.handle(line: byeLine(id: 2))
    expect(bye.close, "bye: closes")

    let next = await s.handle(line: helloLine(id: 3, token: "tok"))
    expect(!next.reply.contains("\"error\""), "bye: a following hello proceeds")
}

// MARK: - 13. logging never leaks arguments or output

@MainActor func testLogNeverLeaksArgumentsOrOutput() async {
    let tools = FakeParentTools(handledNames: ["type_text"])
    tools.setScriptedOutcome(ParentToolOutcome(
        ok: true, output: "typed 22 chars", target: "", tool: "type_text"))
    let s = session(tools: tools, approvals: ScriptedApprovals(answer: true))
    let log = FileManager.default.temporaryDirectory
        .appendingPathComponent("bridge-session-\(UUID().uuidString).log")

    await Log.capturing(to: log) {
        _ = await s.handle(line: helloLine(id: 1, token: "tok"))
        _ = await s.handle(
            line: callLine(id: 2, name: "type_text", argumentsJSON: #"{"text":"a super secret phrase"}"#))
    }

    let contents = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
    expect(contents.contains("chars="), "log: carries the char count")
    expect(!contents.contains("a super secret phrase"), "log: never the typed text")
}

// MARK: - G1. stop() withdraws a pending sheet and closes the session

/// Review 2026-09-28 (spec §3 "Corte"): `stop()` used to leave a parked
/// sheet waiting forever — the client would never learn its "wants to use
/// your hands" request had been withdrawn. Now `stop()` resolves it denied
/// through the same `Approvals` provider the sheet itself would resolve on.
@MainActor func testStopWithdrawsPendingSheetAndClosesSession() async {
    let tools = FakeParentTools()
    let approvals = ScriptedApprovals(park: true)
    let s = session(tools: tools, approvals: approvals)

    _ = await s.handle(line: helloLine(id: 1, token: "tok"))
    let callTask = Task { await s.handle(line: callLine(id: 2, name: "look")) }
    await waitUntil { !approvals.requests.isEmpty }

    await s.stop()

    let result = await callTask.value
    expect(result.reply.contains(BridgeCode.deniedByUser)
        || result.reply.contains(BridgeCode.sessionClosed),
        "stop: the parked call resolves denied or session_closed")
    let requestId = approvals.requests.first?.requestId
    expect(approvals.resolutions.contains { $0.requestId == requestId && !$0.approved },
           "stop: the parked sheet was withdrawn as denied")
    expect(await s.state == .closed, "stop: state closed")
}

// MARK: - G2. onAction fires for a successful write call only

/// 17-2's island chip blinks on a write action; `onAction` is the seam.
@MainActor func testOnActionFiresForSuccessfulWriteCallsOnly() async {
    let recorder = Box<[String]>()
    let record: @Sendable (String) -> Void = { name in
        recorder.set((recorder.get() ?? []) + [name])
    }

    let clickTools = FakeParentTools(handledNames: ["click"])
    let clickSession = session(
        tools: clickTools, approvals: ScriptedApprovals(answer: true), onAction: record)
    _ = await clickSession.handle(line: helloLine(id: 1, token: "tok"))
    _ = await clickSession.handle(line: callLine(id: 2, name: "click"))
    expectEq(recorder.get(), ["click"], "click ok: onAction fires once")

    let lookTools = FakeParentTools(handledNames: ["look"])
    let lookSession = session(
        tools: lookTools, approvals: ScriptedApprovals(answer: true), onAction: record)
    _ = await lookSession.handle(line: helloLine(id: 1, token: "tok"))
    _ = await lookSession.handle(line: callLine(id: 2, name: "look"))
    expectEq(recorder.get(), ["click"], "look ok: onAction not called — not a write tool")

    let deniedTools = FakeParentTools(handledNames: ["click"])
    deniedTools.setScriptedApproval(ApprovalRequest(
        requestId: "c1", toolName: "click", summary: "delete", inputJSON: "{}"))
    let deniedApprovals = ScriptedApprovals(answer: true)
    deniedApprovals.setAnswer(false, forTool: "click")
    let deniedSession = session(tools: deniedTools, approvals: deniedApprovals, onAction: record)
    _ = await deniedSession.handle(line: helloLine(id: 1, token: "tok"))
    _ = await deniedSession.handle(line: callLine(id: 2, name: "click"))
    expectEq(recorder.get(), ["click"], "click denied: onAction still not called")
}

/// Wave 20b D1: the aura lights on every executed call, reads included, and
/// never for a denied one.
@MainActor func testOnCallFiresForEverySuccessfulCall() async {
    let recorder = Box<[String]>()
    let record: @Sendable (String) -> Void = { name in recorder.set((recorder.get() ?? []) + [name]) }
    let tools = FakeParentTools(handledNames: ["look", "click"])
    let s = session(tools: tools, approvals: ScriptedApprovals(answer: true), onCall: record)
    _ = await s.handle(line: helloLine(id: 1, token: "tok"))
    _ = await s.handle(line: callLine(id: 2, name: "look"))
    _ = await s.handle(line: callLine(id: 3, name: "click"))
    expectEq(recorder.get(), ["look", "click"], "onCall: lecturas y escrituras")

    let deniedTools = FakeParentTools(handledNames: ["click"])
    deniedTools.setScriptedApproval(ApprovalRequest(
        requestId: "c1", toolName: "click", summary: "delete", inputJSON: "{}"))
    let deniedApprovals = ScriptedApprovals(answer: true)
    deniedApprovals.setAnswer(false, forTool: "click")
    let denied = session(tools: deniedTools, approvals: deniedApprovals, onCall: record)
    _ = await denied.handle(line: helloLine(id: 1, token: "tok"))
    _ = await denied.handle(line: callLine(id: 2, name: "click"))
    expectEq(recorder.get(), ["look", "click"], "onCall: una llamada negada no enciende el aura")
}

// MARK: - fakes

// MARK: - code review 2026-09-28 (MEDIUM): the size contract at the actor

/// `BridgeConnection` already cuts an oversized line before it reaches the
/// actor, so in production `handle(line:)` never saw one and answered with
/// `close: false`. Spec §3c is "una línea mayor cierra la conexión": the
/// entry point documented as "pure enough to test without a socket" must
/// honour it on its own, or a future caller that trusts it inherits a hole.
@MainActor func testOversizedLineThroughHandleClosesTheConnection() async {
    let s = session(tools: FakeParentTools())
    let oversized = "{\"id\":1,\"method\":\"hello\",\"params\":{\"token\":\""
        + String(repeating: "a", count: BridgeCodec.maxLineBytes) + "\"}}"

    let result = await s.handle(line: oversized)

    expect(result.reply.contains(BridgeCode.frameTooLarge), "handle: too large is frame_too_large")
    expect(result.close, "handle: too large closes the connection, like the transport does")
}

// MARK: - M6. arguments checked where the call lands

/// A client that skips the shim gets the same refusal, and it costs no
/// sheet, no rate budget and no execution.
@MainActor func testABadArgumentIsInvalidArgsBeforeAnySheet() async {
    let tools = FakeParentTools(handledNames: ["type_text"], specNames: [], specs: [ParentTool.typeText.spec(.en)])
    let approvals = ScriptedApprovals(answer: true)
    let s = session(tools: tools, approvals: approvals)
    _ = await s.handle(line: helloLine(id: 1, token: "tok"))
    let typo = await s.handle(line: callLine(id: 2, name: "type_text", argumentsJSON: #"{"txet":"hola"}"#))
    expect(typo.reply.contains(BridgeCode.invalidArgs) && typo.reply.contains("unknown argument `txet`"),
           "misspelled key: \(typo.reply)")
    let empty = await s.handle(line: callLine(id: 3, name: "type_text", argumentsJSON: #"{"text":""}"#))
    expect(empty.reply.contains(BridgeCode.invalidArgs) && empty.reply.contains("1-16000 UTF-8 bytes"),
           "empty text: \(empty.reply)")
    expect(approvals.requests.isEmpty, "no sheet was raised")
    expect(tools.executeCalls.isEmpty, "nothing ran")
    let good = await s.handle(line: callLine(id: 4, name: "type_text", argumentsJSON: #"{"text":"hola"}"#))
    expect(good.reply.contains(#""ok":true"#), "a valid call still runs: \(good.reply)")
}

@MainActor func testEveryKindOfBadArgumentIsInvalidArgsByName() async {
    let tools = FakeParentTools(
        handledNames: ["type_text", "scroll"], specNames: [],
        specs: [ParentTool.typeText.spec(.en), ParentTool.scroll.spec(.en)])
    let s = session(tools: tools, approvals: ScriptedApprovals(answer: true))
    _ = await s.handle(line: helloLine(id: 1, token: "tok"))
    let oversized = String(repeating: "a", count: ToolProperty.maxTextBytes + 1)
    let calls: [(String, String, String)] = [
        ("type_text", #"{"text":"a\u0000b"}"#, "`text`"),
        ("type_text", #"{"text":"\#(oversized)"}"#, "`text`"),
        ("scroll", #"{"direction":"sideways"}"#, "`direction`"),
    ]
    for (offset, (name, arguments, named)) in calls.enumerated() {
        let out = await s.handle(line: callLine(id: offset + 2, name: name, argumentsJSON: arguments))
        expect(out.reply.contains(BridgeCode.invalidArgs) && out.reply.contains(named), "\(name): \(out.reply.prefix(200))")
    }
    expect(tools.executeCalls.isEmpty, "nothing ran")
}

/// Thirty writes a minute is the cap; refused calls must not count toward it.
@MainActor func testBadArgumentsSpendNoRateBudget() async {
    let tools = FakeParentTools(handledNames: ["type_text"], specNames: [], specs: [ParentTool.typeText.spec(.en)])
    let s = session(tools: tools, approvals: ScriptedApprovals(answer: true))
    _ = await s.handle(line: helloLine(id: 1, token: "tok"))
    for id in 2...40 {
        _ = await s.handle(line: callLine(id: id, name: "type_text", argumentsJSON: #"{"text":""}"#))
    }
    let good = await s.handle(line: callLine(id: 41, name: "type_text", argumentsJSON: #"{"text":"hola"}"#))
    expect(good.reply.contains(#""ok":true"#), "after 39 refusals a valid write still runs: \(good.reply)")
}
