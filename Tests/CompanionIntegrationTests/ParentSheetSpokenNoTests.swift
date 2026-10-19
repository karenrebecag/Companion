import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// classic-spoken-yes-parent-sheet, phase 2b-2 (Karen's D3 and plan answer 3):
// a clear spoken "no" to a parent sheet that was asked refuses it, and the
// turn ends with only the fixed "no" line, without a second model round. A
// click on Deny keeps today's road: the model hears the refusal and answers.

private let refusal = Escalation.approvalRefusedSpoken(.es)
private let needsClick = Escalation.approvalNeedsClickSpoken(.es)
/// The rig's second model round: said only if the model got another turn.
private let modelAfterwards = "Listo."

/// The session reducer is not in this harness: the test plays it, answering
/// the sheet the way the reducer would once the spoken answer reaches it.
@MainActor private func answerAsTheReducer(
    _ rig: ParentSheetRig, _ seen: SessionEventBox, approved: Bool
) async {
    await pumpUntilAsync("the spoken answer reached the reducer") {
        seen.events.contains(.approvalSpoken(requestId: "r1", approved: approved))
    }
    _ = await rig.approvals.resolve(requestId: "r1", approved: approved)
}

@Suite struct ParentSheetSpokenNo {
    @Test @MainActor func aSpokenNoRefusesTheSheetAndEndsTheTurnOnItsOwnLine() async {
        let rig = await parentSheetRig()
        let seen = SessionEventBox(rig.h.session.events)
        await restWithTheQuestionSaid(rig)

        await answerHold(rig, "no, gracias")
        await answerAsTheReducer(rig, seen, approved: false)
        await rig.h.session.awaitClassicTurn()

        #expect(rig.tools.executeCalls.isEmpty)
        #expect(rig.h.synth.queue.contains(refusal), "the no has its own line")
        #expect(rig.h.chat.histories.count == 1, "the model got a second round after a spoken no")
        #expect(!rig.h.synth.queue.contains(modelAfterwards))
        #expect(!rig.h.synth.queue.contains(needsClick))
    }

    /// The round that showed the sheet also handed off an errand: the user's
    /// no stops the whole turn, so the errand never starts either.
    @Test @MainActor func aSpokenNoAlsoStopsTheErrandOfTheSameRound() async {
        let jobs = GatedJob()
        let rig = await parentSheetRig(
            firstRound: [.toolCalls([parentOpenCall]), .handoff(q1Flights)], jobs: jobs)
        let seen = SessionEventBox(rig.h.session.events)
        await restWithTheQuestionSaid(rig)

        await answerHold(rig, "no")
        await answerAsTheReducer(rig, seen, approved: false)
        await rig.h.session.awaitClassicTurn()

        #expect(jobs.goals.isEmpty, "a refused turn still started its errand")
        #expect(rig.h.synth.queue.contains(refusal))
        #expect(rig.tools.executeCalls.isEmpty)
    }

    /// The same, when the model wrote its errand as text instead of a call:
    /// nothing is proposed or started after the user said no.
    @Test @MainActor func aSpokenNoAlsoStopsAnErrandWrittenAsText() async {
        let jobs = GatedJob()
        let rig = await parentSheetRig(
            firstRound: [.text(#"{"goal":"busca vuelos en Safari"}"#), .toolCalls([parentOpenCall])],
            jobs: jobs)
        let seen = SessionEventBox(rig.h.session.events)
        await restWithTheQuestionSaid(rig)

        await answerHold(rig, "no")
        await answerAsTheReducer(rig, seen, approved: false)
        await rig.h.session.awaitClassicTurn()

        #expect(jobs.goals.isEmpty, "a refused turn still started its errand")
        #expect(rig.h.synth.queue == [parentQuestion, refusal], "something was said after the no")
    }

    @Test @MainActor func aClickOnDenyStillHandsTheRefusalToTheModel() async {
        let rig = await parentSheetRig()
        await restWithTheQuestionSaid(rig)

        _ = await rig.approvals.resolve(requestId: "r1", approved: false)
        await rig.h.session.awaitClassicTurn()

        #expect(rig.tools.executeCalls.isEmpty)
        #expect(rig.h.chat.histories.count == 2, "a click-deny lost the model's answer")
        #expect(rig.h.synth.queue.contains(modelAfterwards))
        #expect(!rig.h.synth.queue.contains(refusal))
    }

    /// "no sé" is no answer: like any other words it is a turn of its own,
    /// never a refusal of the sheet.
    @Test @MainActor func aHedgeIsATurnNotARefusal() async {
        let rig = await parentSheetRig()
        let seen = SessionEventBox(rig.h.session.events)
        await restWithTheQuestionSaid(rig)

        await answerHold(rig, "no sé")
        await pumpUntil("the words opened a new turn") { rig.h.chat.histories.count >= 2 }
        #expect(!seen.events.contains(.approvalSpoken(requestId: "r1", approved: false)))
        _ = await rig.approvals.resolve(requestId: "r1", approved: false)
        await rig.h.session.awaitClassicTurn()
        #expect(!rig.h.synth.queue.contains(refusal))
    }

    /// A no the sheet did not take (another request is in front) refused
    /// nothing: the voice asks for the click, and a later click-deny is the
    /// click's, with the model's round, not the voice's line.
    @Test @MainActor func aNoTheSheetDidNotTakeLeavesNoMarkOnTheTurn() async {
        let rig = await parentSheetRig()
        await restWithTheQuestionSaid(rig)
        await rig.h.session.approvalFront(requestId: "someone-else")

        await answerHold(rig, "no")
        await pumpUntil("the voice asks for the click") { rig.h.synth.queue.contains(needsClick) }
        rig.h.synth.yield(.finished)

        _ = await rig.approvals.resolve(requestId: "r1", approved: false)
        await rig.h.session.awaitClassicTurn()
        #expect(rig.h.chat.histories.count == 2, "a no the sheet never took still ended the turn")
        #expect(!rig.h.synth.queue.contains(refusal))
    }

    /// A click answered the sheet while the key was down: whatever the hold
    /// heard is no answer to it any more. Nothing heard is nothing, and any
    /// words, a "no" too, are an ordinary turn; the click's action stands.
    @Test(arguments: ["", "no", "mejor busca vuelos a Lima"])
    @MainActor func aClickDuringTheHoldLeavesItsWordsAnOrdinaryTurn(_ words: String) async {
        let rig = await parentSheetRig()
        let seen = SessionEventBox(rig.h.session.events)
        await restWithTheQuestionSaid(rig)

        rig.h.clock.now += 1
        rig.h.transcriber.stoppedText = words
        await rig.h.session.hold()
        await pumpUntil("listening for the answer") { rig.h.watch.latest.state == .listening }
        _ = await rig.approvals.resolve(requestId: "r1", approved: true)
        await pumpUntil("the click acted") { rig.tools.executeCalls.count == 1 }
        await pumpUntilAsync("the session closed the sheet") {
            await rig.h.session.pendingApproval == nil
        }
        // The clicked turn's next round comes first, so the count below is
        // the hold's own (the release-first order is #130's).
        await pumpUntil("the clicked turn went on") { rig.h.chat.histories.count == 2 }
        await rig.h.session.release()
        if !words.isEmpty {
            await pumpUntil("the words opened a turn") { rig.h.chat.histories.count == 3 }
            #expect(rig.h.chat.histories.last?.contains {
                $0.role == .user && $0.content.contains(words)
            } == true)
        }
        await rig.h.session.awaitClassicTurn()

        #expect(rig.h.chat.histories.count == (words.isEmpty ? 2 : 3))
        #expect(rig.tools.executeCalls.count == 1)
        #expect(!rig.h.synth.queue.contains(needsClick))
        #expect(!rig.h.synth.queue.contains(refusal))
        #expect(!seen.events.contains { if case .approvalSpoken = $0 { true } else { false } })
    }

    /// The ear's stop is a wait: a job's request can take the sheet's place
    /// in it. The "no" was said to the parent's question, so it refuses
    /// nothing else.
    @Test @MainActor func aNoNeverRefusesARequestThatArrivedWhileTheEarStopped() async {
        let rig = await parentSheetRig()
        let seen = SessionEventBox(rig.h.session.events)
        await restWithTheQuestionSaid(rig)

        rig.h.clock.now += 1
        rig.h.transcriber.stoppedText = "no"
        await rig.h.session.hold()
        await pumpUntil("listening for the answer") { rig.h.watch.latest.state == .listening }
        let stopsBefore = rig.h.transcriber.stops
        // Long enough that the request below lands inside the stop on a
        // loaded machine too; the stop has no gate to hold it.
        rig.h.transcriber.stopDelays = [2]
        let release = Task { await rig.h.session.release() }
        await pumpUntil("the ear is stopping") { rig.h.transcriber.stops > stopsBefore }
        let job = ApprovalRequest(requestId: "j1", toolName: "run_shell", summary: "ls", inputJSON: "{}")
        await rig.h.session.noteApproval(job)
        await release.value

        #expect(!seen.events.contains { if case .approvalSpoken = $0 { true } else { false } })
        #expect(!rig.h.synth.queue.contains(refusal))
        _ = await rig.approvals.resolve(requestId: "r1", approved: false)
        await rig.h.session.awaitClassicTurn()
    }

    /// A press after the no, before the sheet took it: the new turn cuts the
    /// parked one, which then says nothing over it.
    @Test @MainActor func aPressAfterTheNoCutsTheTurnBeforeItsLine() async {
        let rig = await parentSheetRig()
        let seen = SessionEventBox(rig.h.session.events)
        await restWithTheQuestionSaid(rig)
        await answerHold(rig, "no")
        await pumpUntilAsync("the spoken answer reached the reducer") {
            seen.events.contains(.approvalSpoken(requestId: "r1", approved: false))
        }

        rig.h.chat.rounds = [[.text("Claro.")]]
        await answerHold(rig, "que hora es")
        await pumpUntil("the words opened a turn") { rig.h.chat.histories.count >= 2 }
        _ = await rig.approvals.resolve(requestId: "r1", approved: false)
        await rig.h.session.awaitClassicTurn()

        #expect(!rig.h.synth.queue.contains(refusal), "a cut turn spoke over the next one")
        #expect(rig.h.synth.queue.contains("Claro."))
        #expect(rig.tools.executeCalls.isEmpty)
    }

    /// The dictation key types; only FN answers the voice, a no included.
    @Test @MainActor func theDictationKeyNeverRefusesTheSheet() async {
        let rig = await parentSheetRig()
        let seen = SessionEventBox(rig.h.session.events)
        await restWithTheQuestionSaid(rig)

        await answerHold(rig, "no", dictate: true)
        await pumpUntil("the hold went to a turn") { rig.h.chat.histories.count >= 2 }
        #expect(!seen.events.contains { if case .approvalSpoken = $0 { true } else { false } })
        _ = await rig.approvals.resolve(requestId: "r1", approved: false)
        await rig.h.session.awaitClassicTurn()
        #expect(!rig.h.synth.queue.contains(refusal))
    }

    /// A question not yet said is no question: the no is a cut, as #87 made.
    @Test @MainActor func aNoBeforeTheQuestionWasSaidIsACut() async {
        let rig = await parentSheetRig()
        let seen = SessionEventBox(rig.h.session.events)
        await holdUntilTheParentSheet(rig)
        await pumpUntil("the voice asks") { timesAsked(rig.h) == 1 }

        await answerHold(rig, "no")
        await pumpUntil("the no opened a new turn") { rig.h.chat.histories.count >= 2 }
        #expect(!seen.events.contains { if case .approvalSpoken = $0 { true } else { false } })
        _ = await rig.approvals.resolve(requestId: "r1", approved: false)
        await rig.h.session.awaitClassicTurn()
        #expect(!rig.h.synth.queue.contains(refusal))
    }

    /// The mark is taken once: a later sheet with the same id, denied by a
    /// click, is the click's, with the model's round.
    @Test @MainActor func theRefusalMarkIsSpentByItsTurn() async {
        let rig = await parentSheetRig()
        let seen = SessionEventBox(rig.h.session.events)
        await restWithTheQuestionSaid(rig)
        await answerHold(rig, "no")
        await answerAsTheReducer(rig, seen, approved: false)
        await rig.h.session.awaitClassicTurn()
        let histories = rig.h.chat.histories.count

        rig.h.chat.rounds = [[.toolCalls([parentOpenCall])], [.text("Entendido.")]]
        rig.h.clock.now += 1
        rig.h.transcriber.stoppedText = "abre la pagina otra vez"
        await rig.h.session.hold()
        await pumpUntil("listening") { rig.h.watch.latest.state == .listening }
        await rig.h.session.release()
        await pumpUntilAsync("the second sheet is up") { rig.approvals.requests.count == 2 }
        _ = await rig.approvals.resolve(requestId: "r1", approved: false)
        await rig.h.session.awaitClassicTurn()

        #expect(rig.h.chat.histories.count == histories + 2, "a click-deny lost the model's round")
        #expect(rig.h.synth.queue.filter { $0 == refusal }.count == 1)
    }

    /// The reducer dropped the spoken no (the sheet had changed under it),
    /// and the user then clicked Allow: the action ran, so the turn must not
    /// say it will not do it, and the model hears the result.
    @Test @MainActor func aNoTheSheetDroppedThenAClickToAllowIsTheClicks() async {
        let rig = await parentSheetRig()
        let seen = SessionEventBox(rig.h.session.events)
        await restWithTheQuestionSaid(rig)

        await answerHold(rig, "no")
        await pumpUntilAsync("the spoken answer reached the reducer") {
            seen.events.contains(.approvalSpoken(requestId: "r1", approved: false))
        }
        _ = await rig.approvals.resolve(requestId: "r1", approved: true)
        await rig.h.session.awaitClassicTurn()

        #expect(rig.tools.executeCalls.count == 1)
        #expect(!rig.h.synth.queue.contains(refusal), "a refusal was said over an action that ran")
        #expect(rig.h.chat.histories.count == 2, "the model never heard the action's result")
    }

    /// That dropped no leaves nothing behind: a later sheet with the same id,
    /// denied by a click, is the click's, with the model's round.
    @Test @MainActor func aNoThatNeverRefusedLeavesNoMarkForLater() async {
        let rig = await parentSheetRig()
        let seen = SessionEventBox(rig.h.session.events)
        await restWithTheQuestionSaid(rig)
        await answerHold(rig, "no")
        await pumpUntilAsync("the spoken answer reached the reducer") {
            seen.events.contains(.approvalSpoken(requestId: "r1", approved: false))
        }
        _ = await rig.approvals.resolve(requestId: "r1", approved: true)
        await rig.h.session.awaitClassicTurn()
        let histories = rig.h.chat.histories.count

        rig.h.chat.rounds = [[.toolCalls([parentOpenCall])], [.text("Entendido.")]]
        rig.h.clock.now += 1
        rig.h.transcriber.stoppedText = "abre la pagina otra vez"
        await rig.h.session.hold()
        await pumpUntil("listening") { rig.h.watch.latest.state == .listening }
        await rig.h.session.release()
        await pumpUntilAsync("the second sheet is up") { rig.approvals.requests.count == 2 }
        _ = await rig.approvals.resolve(requestId: "r1", approved: false)
        await rig.h.session.awaitClassicTurn()

        #expect(rig.h.chat.histories.count == histories + 2, "a stale mark ended a click's turn")
        #expect(!rig.h.synth.queue.contains(refusal))
    }

    /// The no ends the round too: a later call of the same round neither
    /// runs nor raises a sheet the user never heard about.
    @Test @MainActor func aSpokenNoStopsTheRestOfItsRound() async {
        let second = ToolCallRef(id: "c2", name: "open_url", arguments: #"{"url":"https://example.org"}"#)
        let rig = await parentSheetRig(firstRound: [.toolCalls([parentOpenCall, second])])
        let seen = SessionEventBox(rig.h.session.events)
        await restWithTheQuestionSaid(rig)

        await answerHold(rig, "no")
        await answerAsTheReducer(rig, seen, approved: false)
        await pumpUntil("the turn ended on its line") { rig.h.synth.queue.contains(refusal) }
        let sheets = rig.approvals.requests.count
        // Unblocks a second sheet if one was raised, so the turn can end.
        _ = await rig.approvals.resolve(requestId: "r1", approved: false)
        await rig.h.session.awaitClassicTurn()

        #expect(sheets == 1, "a later call of the refused round raised another sheet")
        #expect(rig.tools.executeCalls.isEmpty)
    }

    /// A pending MCP request outranks a job's in `answerPendingApproval`; the
    /// parent's no must never be spent on it.
    @Test @MainActor func aParentsNoIsNeverSpentOnAnMCPRequest() async {
        let rig = await parentSheetRig()
        await restWithTheQuestionSaid(rig)
        let mcp = ApprovalRequest(
            requestId: "m1", toolName: "run_shell", summary: "ls", inputJSON: "{}", isMCP: true)
        let session = rig.h.session
        let waiting = Task { await session.noteMCPApproval(mcp) }
        await pumpUntilAsync("the MCP sheet is up") { rig.approvals.requests.contains { $0.requestId == "m1" } }

        await answerHold(rig, "no")
        await pumpUntil("the voice asks for the click") { rig.h.synth.queue.contains(needsClick) }
        #expect(!rig.approvals.resolutions.contains { $0.requestId == "m1" }, "the parent's no refused the MCP request")

        _ = await rig.approvals.resolve(requestId: "m1", approved: false)
        await waiting.value
        _ = await rig.approvals.resolve(requestId: "r1", approved: false)
        await rig.h.session.awaitClassicTurn()
        #expect(!rig.h.synth.queue.contains(refusal))
    }

    /// The refusal ends this turn only: the next press is an ordinary turn
    /// that the model answers.
    @Test @MainActor func theTurnAfterASpokenNoIsAnOrdinaryOne() async {
        let rig = await parentSheetRig()
        let seen = SessionEventBox(rig.h.session.events)
        await restWithTheQuestionSaid(rig)
        await answerHold(rig, "no")
        await answerAsTheReducer(rig, seen, approved: false)
        await rig.h.session.awaitClassicTurn()

        rig.h.chat.rounds = [[.text("Claro.")]]
        rig.h.clock.now += 1
        rig.h.transcriber.stoppedText = "que hora es"
        await rig.h.session.hold()
        await pumpUntil("listening") { rig.h.watch.latest.state == .listening }
        await rig.h.session.release()
        await rig.h.session.awaitClassicTurn()
        #expect(rig.h.synth.queue.contains("Claro."))
        #expect(rig.h.synth.queue.filter { $0 == refusal }.count == 1)
    }
}
