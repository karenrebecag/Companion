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

@Suite struct ApprovalWithdrawn {
    @Test @MainActor func aWithdrawnSheetLeavesTheQueueAndTheIslandSaysWhy() {
        var machine = SessionMachine()
        _ = machine.handle(.job(.approvalRequested(parked)))
        let effects = machine.handle(.approvalWithdrawn(requestId: "r1"))
        #expect(machine.projection.approvalQueue.isEmpty, "the card stayed after its turn was cut")
        #expect(!effects.contains { if case .resolveApproval = $0 { true } else { false } },
                "the actor already ended the wait; resolving again answers nothing")
        #expect(machine.projection.notice == .approvalWithdrawn)
        #expect(effects.contains(.scheduleNoticeExpiry(SessionMachine.noticeDelay)))
        #expect(IslandNotice.content(for: .approvalWithdrawn) != nil)
        _ = machine.handle(.noticeExpired(.approvalWithdrawn))
        #expect(machine.projection.notice == nil)
    }

    @Test @MainActor func aWithdrawalForACardAlreadyAnsweredExplainsNothing() {
        var machine = SessionMachine()
        let effects = machine.handle(.approvalWithdrawn(requestId: "gone"))
        #expect(effects.isEmpty)
        #expect(machine.projection.notice == nil, "a notice about a card the user never saw leave")
    }

    @Test @MainActor func aWithdrawalNeverCoversANoticeTheUserMustActOn() {
        var machine = SessionMachine()
        _ = machine.handle(.pressed)
        _ = machine.handle(.released)
        _ = machine.handle(.dictationFailed(.needsAccessibility))
        _ = machine.handle(.job(.approvalRequested(parked)))
        _ = machine.handle(.approvalWithdrawn(requestId: "r1"))
        #expect(machine.projection.approvalQueue.isEmpty, "the card still goes")
        #expect(machine.projection.notice == .permission(.accessibilityDenied), "the permission stays up")
    }

    @Test @MainActor func theWithdrawnCopyIsRealAndTranslated() {
        for key in ["island.approvalWithdrawn.title", "island.approvalWithdrawn.body"] {
            for language in [AppLanguage.en, .es] {
                let text = Localized.string(key, language: language)
                #expect(!text.isEmpty && text != key, "\(key) \(language) does not resolve")
            }
        }
    }

    @Test @MainActor func aStopWhileTheSheetWaitsActsOnNothingAndWithdrawsTheCard() async {
        let approvals = ScriptedApprovals(park: true)
        let (h, tools) = sheetRig(approvals: approvals)
        let seen = SessionEventBox(h.session.events)
        await h.session.hold()
        await pumpUntil("listening") { h.watch.latest.state == .listening }
        await h.session.release()
        await pumpUntilAsync("the sheet is up") { !approvals.requests.isEmpty }

        await h.session.interrupt()
        _ = await approvals.resolve(requestId: "r1", approved: true)
        await h.session.awaitClassicTurn()

        #expect(tools.executeCalls.isEmpty, "the late yes acted for the stopped turn")
        await pumpUntilAsync("the card is withdrawn") {
            seen.events.contains(.approvalWithdrawn(requestId: "r1"))
        }
    }

    // The other side of the settle: a yes with nobody cut acts and closes the
    // card quietly. An "I stopped" notice here would be a lie.
    @Test @MainActor func aYesWithNobodyCutActsAndSettlesTheCardWithoutANotice() async {
        let approvals = ScriptedApprovals(park: true)
        let (h, tools) = sheetRig(approvals: approvals)
        let seen = SessionEventBox(h.session.events)
        await h.session.hold()
        await pumpUntil("listening") { h.watch.latest.state == .listening }
        await h.session.release()
        await pumpUntilAsync("the sheet is up") { !approvals.requests.isEmpty }

        _ = await approvals.resolve(requestId: "r1", approved: true)
        await h.session.awaitClassicTurn()

        #expect(tools.executeCalls.count == 1)
        await pumpUntilAsync("the card settles") {
            seen.events.contains(.approvalSettled(requestId: "r1"))
        }
        #expect(!seen.events.contains(.approvalWithdrawn(requestId: "r1")))
    }

    // D3 split: realtime's barge-in is its own PR; closing the session does
    // cancel the handler, so the guard's check already covers it.
    @Test @MainActor func closingRealtimeWhileTheSheetWaitsActsOnNothingAndWithdrawsTheCard() async {
        let approvals = ScriptedApprovals(park: true)
        let tools = FakeParentTools(handledNames: ["open_url"])
        tools.setScriptedApproval(parked)
        let h = makeVoiceHarness(parentTools: tools, approvals: approvals)
        let seen = SessionEventBox(h.session.events)
        await h.session.start()
        await pumpUntil("listening") { h.watch.latest.state == .listening }
        h.transport.yield(.functionCall(name: "open_url", arguments: openCall.arguments, callId: "c1"))
        await pumpUntilAsync("the sheet is up") { !approvals.requests.isEmpty }

        await h.session.hangUp()
        _ = await approvals.resolve(requestId: "r1", approved: true)

        await pumpUntilAsync("the card is withdrawn") {
            seen.events.contains(.approvalWithdrawn(requestId: "r1"))
        }
        #expect(tools.executeCalls.isEmpty, "the late yes acted for a closed session")
    }

    // Q1 is Karen's open question. This only records what happens today
    // with the real actor when the user presses to answer by voice: the
    // press cuts the turn, so the guard's own check is part of why nothing
    // runs. It is not evidence of how main behaved before this change.
    @Test @MainActor func characterizationASpokenYesToAParentSheetInClassicActsOnNothing() async {
        let approvals = Approvals(clock: RealtimeClock())
        let (h, tools) = sheetRig(approvals: approvals)
        let seen = SessionEventBox(h.session.events)
        await h.session.hold()
        await pumpUntil("listening") { h.watch.latest.state == .listening }
        await h.session.release()
        // `.thinking` comes before the tool call; pressing then would cut the
        // turn too early and hand the call to the "sí" turn instead.
        await pumpUntilAsync("the turn waits on the sheet") {
            seen.events.contains { if case .job(.approvalRequested, _) = $0 { true } else { false } }
        }

        h.transcriber.stoppedText = "sí"
        await h.session.hold()
        await pumpUntil("listening for the answer") { h.watch.latest.state == .listening }
        await h.session.release()
        await h.session.awaitClassicTurn()

        #expect(tools.executeCalls.isEmpty, "a spoken yes opened the page: Q1's premise is wrong")
        let stillParked = await approvals.resolve(requestId: "r1", approved: false)
        #expect(!stillParked, "the press left the sheet parked instead of ending the wait")
    }

    @Test func theRealActorDeniesAWaitWhoseCallerWasCancelled() async {
        let approvals = Approvals(clock: RealtimeClock())
        let waiting = Task { await approvals.request(parked) }
        // Either road is a denial: parked, the cancel handler resolves it;
        // not parked yet, the entry check refuses it. The pause only makes
        // the first road the likely one.
        do { try await Task.sleep(for: .milliseconds(50)) } catch {}
        waiting.cancel()
        let response = await waiting.value
        #expect(!response.approved)
    }
}
