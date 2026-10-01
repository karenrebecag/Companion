import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// approval-after-cut D3 (Karen, 2026-10-01): in realtime a barge-in withdraws
// the parent's sheet the way a press does in classic, and as Pipecat does by
// default: interrupting cancels the function call in flight. The call is
// still answered, as an interruption, and nobody asks the model to talk over
// the user who just cut it.

private let parked = ApprovalRequest(
    requestId: "r1", toolName: "open_url", summary: "open example.com", inputJSON: "{}")
private let next = ApprovalRequest(
    requestId: "r2", toolName: "open_url", summary: "open example.org", inputJSON: "{}")
private let openArguments = #"{"url":"https://example.com"}"#
private let nextArguments = #"{"url":"https://example.org"}"#

private func sheetTools() -> FakeParentTools {
    let tools = FakeParentTools(handledNames: ["open_url"])
    tools.setScriptedApproval(parked)
    return tools
}

private func interruptedAnswerSent(_ sent: [String]) -> Bool {
    sent.contains { $0.contains("function_call_output") && $0.contains(ContractError.interrupted.wire) }
}

/// The agent is talking when the call arrives: a press then is a barge-in.
@MainActor private func parkWhileSpeaking(
    _ h: VoiceHarness, approvals: any ApprovalsProvider, requested: @escaping () async -> Bool
) async {
    await h.session.start()
    await pumpUntil("listening") { h.watch.latest.state == .listening }
    h.transport.yield(.agentAudioStarted)
    await pumpUntil("speaking") { h.watch.latest.state == .speaking }
    h.transport.yield(.functionCall(name: "open_url", arguments: openArguments, callId: "c1"))
    await pumpUntilAsync("the sheet is up") { await requested() }
}

/// The loop handles events one at a time, so once the next call's sheet is
/// up, everything the cut call was going to send has been sent.
@MainActor private func sendNextCall(
    _ h: VoiceHarness, tools: FakeParentTools, approvals: ScriptedApprovals
) async {
    tools.setScriptedApproval(next)
    h.transport.yield(.functionCall(name: "open_url", arguments: nextArguments, callId: "c2"))
    await pumpUntilAsync("the next sheet is up") { approvals.requests.contains { $0.requestId == "r2" } }
}

@Suite struct RealtimeBargeInWithdraws {
    @Test @MainActor func aBargeInWhileTheSheetWaitsActsOnNothingAndWithdrawsTheCard() async {
        let approvals = ScriptedApprovals(park: true)
        let tools = sheetTools()
        let h = makeVoiceHarness(parentTools: tools, approvals: approvals)
        let seen = SessionEventBox(h.session.events)
        await parkWhileSpeaking(h, approvals: approvals) { !approvals.requests.isEmpty }

        await h.session.hold()
        let before = h.transport.sent.count
        _ = await approvals.resolve(requestId: "r1", approved: true)
        await pumpUntilAsync("the card is withdrawn") {
            seen.events.contains(.approvalWithdrawn(requestId: "r1"))
        }
        await sendNextCall(h, tools: tools, approvals: approvals)

        let cutReply = Array(h.transport.sent.dropFirst(before))
        #expect(interruptedAnswerSent(cutReply), "the cut call went unanswered")
        #expect(!hasMessage(cutReply, type: "response.create"),
                "the model was asked to talk over the user who cut it")
        #expect(tools.executeCalls.isEmpty, "the late yes acted for a reply the user talked over")

        // The cut is spent on its own call: the next one asks and acts.
        let beforeNext = h.transport.sent.count
        _ = await approvals.resolve(requestId: "r2", approved: true)
        await pumpUntil("the next call acts and the model goes on") {
            hasMessage(Array(h.transport.sent.dropFirst(beforeNext)), type: "response.create")
        }
        #expect(tools.executeCalls.map(\.argumentsJSON) == [nextArguments])
    }

    @Test @MainActor func aPressWhileTheModelIsStillThinkingAlsoWithdrawsTheCard() async {
        let approvals = ScriptedApprovals(park: true)
        let tools = sheetTools()
        let h = makeVoiceHarness(parentTools: tools, approvals: approvals)
        let seen = SessionEventBox(h.session.events)
        await h.session.start()
        await pumpUntil("listening") { h.watch.latest.state == .listening }
        h.transport.yield(.speechStarted)
        h.transport.yield(.speechStopped)
        await pumpUntil("thinking") { h.watch.latest.state == .thinking }
        h.transport.yield(.functionCall(name: "open_url", arguments: openArguments, callId: "c1"))
        await pumpUntilAsync("the sheet is up") { !approvals.requests.isEmpty }

        await h.session.hold()
        _ = await approvals.resolve(requestId: "r1", approved: true)

        await pumpUntilAsync("the card is withdrawn") {
            seen.events.contains(.approvalWithdrawn(requestId: "r1"))
        }
        await sendNextCall(h, tools: tools, approvals: approvals)
        #expect(tools.executeCalls.isEmpty, "the late yes acted for a turn cut before it spoke")
        #expect(interruptedAnswerSent(h.transport.sent))
    }

    @Test @MainActor func aStopWhileTheSheetWaitsActsOnNothingAndWithdrawsTheCard() async {
        let approvals = ScriptedApprovals(park: true)
        let tools = sheetTools()
        let h = makeVoiceHarness(parentTools: tools, approvals: approvals)
        let seen = SessionEventBox(h.session.events)
        await parkWhileSpeaking(h, approvals: approvals) { !approvals.requests.isEmpty }

        await h.session.interrupt()
        let before = h.transport.sent.count
        _ = await approvals.resolve(requestId: "r1", approved: true)
        await pumpUntilAsync("the card is withdrawn") {
            seen.events.contains(.approvalWithdrawn(requestId: "r1"))
        }
        await sendNextCall(h, tools: tools, approvals: approvals)

        let cutReply = Array(h.transport.sent.dropFirst(before))
        #expect(interruptedAnswerSent(cutReply))
        #expect(!hasMessage(cutReply, type: "response.create"), "a stop was followed by more talk")
        #expect(tools.executeCalls.isEmpty, "the late yes acted after the user said stop")
        #expect(h.watch.latest.state == .listening)
    }

    // The app's own actor ends the wait when its caller is cut, with no
    // answer from anyone: the whole chain from the press to the notice.
    @Test @MainActor func withTheRealActorABargeInEndsTheSheetWithoutAnyAnswer() async {
        let approvals = Approvals(clock: RealtimeClock())
        let tools = sheetTools()
        let h = makeVoiceHarness(parentTools: tools, approvals: approvals)
        let seen = SessionEventBox(h.session.events)
        await parkWhileSpeaking(h, approvals: approvals) {
            seen.events.contains { if case .job(.approvalRequested, _) = $0 { true } else { false } }
        }

        await h.session.hold()

        await pumpUntilAsync("the card is withdrawn") {
            seen.events.contains(.approvalWithdrawn(requestId: "r1"))
        }
        await pumpUntil("the call is answered") { interruptedAnswerSent(h.transport.sent) }
        #expect(tools.executeCalls.isEmpty)
        let stillParked = await approvals.resolve(requestId: "r1", approved: true)
        #expect(!stillParked, "the barge-in left the sheet waiting for a yes")
    }

    // The other side: with nobody cutting, a yes still acts once and the
    // model is asked to go on.
    @Test @MainActor func aYesWithNobodyCuttingStillActsAndAsksTheModelToGoOn() async {
        let approvals = ScriptedApprovals(park: true)
        let tools = sheetTools()
        let h = makeVoiceHarness(parentTools: tools, approvals: approvals)
        let seen = SessionEventBox(h.session.events)
        await parkWhileSpeaking(h, approvals: approvals) { !approvals.requests.isEmpty }
        let before = h.transport.sent.count

        _ = await approvals.resolve(requestId: "r1", approved: true)

        await pumpUntilAsync("the card settles") {
            seen.events.contains(.approvalSettled(requestId: "r1"))
        }
        await pumpUntil("the model is asked to go on") {
            hasMessage(Array(h.transport.sent.dropFirst(before)), type: "response.create")
        }
        #expect(tools.executeCalls.count == 1)
        #expect(!interruptedAnswerSent(h.transport.sent))
    }

    // Security review of #87 (LOW): the guard's waits besides the sheet
    // (binding the request, reading memory) are cut points too.
    @Test @MainActor func aBargeInDuringTheGuardsOtherWaitsStillActsOnNothing() async {
        let approvals = ScriptedApprovals(park: true)
        let tools = SlowBinding(sheetTools())
        let h = makeVoiceHarness(parentTools: tools, approvals: approvals)
        await h.session.start()
        await pumpUntil("listening") { h.watch.latest.state == .listening }
        h.transport.yield(.agentAudioStarted)
        await pumpUntil("speaking") { h.watch.latest.state == .speaking }
        h.transport.yield(.functionCall(name: "open_url", arguments: openArguments, callId: "c1"))
        await pumpUntil("the guard is binding") { tools.binding }

        await h.session.hold()
        tools.release()

        await pumpUntil("the call is answered") { interruptedAnswerSent(h.transport.sent) }
        #expect(tools.inner.executeCalls.isEmpty, "a cut call acted once the guard let it through")
        #expect(approvals.requests.isEmpty, "this call never needed a sheet")
    }
}

// The two races the reviews found, driven on the runtime alone so the cut
// lands exactly where each one needs it.
@Suite struct RealtimeBargeInRaces {
    @MainActor private func rig(_ approvals: ScriptedApprovals, _ tools: FakeParentTools) -> RealtimeRuntime {
        let runtime = RealtimeRuntime(
            transport: ScriptedVoiceTransport(), player: ScriptedPlayer(), thread: ScriptedThread())
        runtime.parentTools = tools
        runtime.parentGuard = ParentToolGuard(approvals: approvals)
        return runtime
    }

    // Security review of D3 (MEDIUM): the handler suspends before it holds
    // the call, and a barge-in in that gap found nothing to cut.
    @Test @MainActor func aBargeInBeforeTheCallIsHeldStillCutsIt() async {
        let approvals = ScriptedApprovals(park: true)
        let tools = sheetTools()
        let runtime = rig(approvals, tools)
        runtime.markTimeline = { @MainActor point in
            if case .toolCallSeen = point { await runtime.cancelAgent() }
        }

        let handled = Task {
            await runtime.handle(
                .functionCall(name: "open_url", arguments: openArguments, callId: "c1"), state: .speaking)
        }
        await pumpUntilAsync("the sheet is up") { !approvals.requests.isEmpty }
        _ = await approvals.resolve(requestId: "r1", approved: true)
        let follow = await handled.value

        #expect(tools.executeCalls.isEmpty, "a barge-in before the call was held let the yes act")
        #expect(follow.isEmpty)
    }

    // Code review of D3 (MEDIUM): a closed session's call that unwinds late
    // must not forget the call of the session that replaced it.
    @Test @MainActor func aLateUnwindFromAClosedSessionDoesNotHideTheNewCall() async {
        let approvals = ScriptedApprovals(park: true)
        let tools = sheetTools()
        let runtime = rig(approvals, tools)

        let closed = Task {
            await runtime.handle(
                .functionCall(name: "open_url", arguments: openArguments, callId: "c1"), state: .speaking)
        }
        await pumpUntilAsync("the first sheet is up") { approvals.requests.count == 1 }
        closed.cancel()
        tools.setScriptedApproval(next)
        let current = Task {
            await runtime.handle(
                .functionCall(name: "open_url", arguments: nextArguments, callId: "c2"), state: .speaking)
        }
        await pumpUntilAsync("the second sheet is up") { approvals.requests.count == 2 }
        _ = await approvals.resolve(requestId: "r1", approved: false)
        _ = await closed.value

        await runtime.cancelAgent()
        _ = await approvals.resolve(requestId: "r2", approved: true)
        _ = await current.value

        #expect(tools.executeCalls.isEmpty, "the barge-in missed the new session's call")
    }
}

/// Holds the guard in `bound` until the test lets go, then lets the call
/// through without a sheet: the cut has to be caught after the guard.
private final class SlowBinding: ParentToolExecuting, @unchecked Sendable {
    let inner: FakeParentTools
    private let lock = NSLock()
    private var waiting = false
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?

    init(_ inner: FakeParentTools) { self.inner = inner }

    var binding: Bool { lock.withLock { waiting } }

    func release() {
        let resume = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            released = true
            defer { waiter = nil }
            return waiter
        }
        resume?.resume()
    }

    func specs(_ language: AppLanguage) -> [ToolSpec] { inner.specs(language) }
    func handles(_ name: String) -> Bool { inner.handles(name) }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        await inner.execute(name: name, argumentsJSON: argumentsJSON)
    }
    func approval(for call: ToolCallRef, said: String) -> ApprovalRequest? {
        inner.approval(for: call, said: said)
    }
    // Ignores cancellation on purpose: a binding that reads another app
    // finishes its read whatever the caller does.
    func bound(_ request: ApprovalRequest) async -> ApprovalRequest {
        await withCheckedContinuation { continuation in
            let early = lock.withLock { () -> Bool in
                waiting = true
                if released { return true }
                waiter = continuation
                return false
            }
            if early { continuation.resume() }
        }
        return request
    }
    func actsWithoutSheet(_ call: ToolCallRef) async -> Bool { true }
}
