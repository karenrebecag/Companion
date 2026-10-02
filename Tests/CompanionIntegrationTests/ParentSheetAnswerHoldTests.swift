import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// classic-spoken-yes-parent-sheet, phase 2a (Karen's D2: P2, the answer
// hold). Once the question of a parent sheet was said, a press over the
// resting turn answers it instead of cutting: "sí" asks for the click and
// the sheet stays, nothing heard leaves it, anything else is a cut (#87).

private let needsClick = Escalation.approvalNeedsClickSpoken(.es)

@Suite struct ParentSheetAnswerHold {
    @Test @MainActor func aYesAsksForTheClickAndTheNextYesStillDoes() async {
        let rig = await parentSheetRig()
        await restWithTheQuestionSaid(rig)

        await answerHold(rig, "sí")
        await pumpUntil("the voice asks for the click") { rig.h.synth.queue.contains(needsClick) }
        #expect(rig.tools.executeCalls.isEmpty)
        #expect(rig.h.watch.latest.sheetParked)
        #expect(rig.h.chat.histories.count == 1, "the yes opened a turn")

        // The sheet is still the one asked about: a second yes answers it too.
        rig.h.synth.yield(.finished)
        await answerHold(rig, "sí")
        await pumpUntil("asked again") { rig.h.synth.queue.filter { $0 == needsClick }.count == 2 }

        // Only the click acts.
        _ = await rig.approvals.resolve(requestId: "r1", approved: true)
        await rig.h.session.awaitClassicTurn()
        #expect(rig.tools.executeCalls.count == 1)
    }

    @Test @MainActor func wordsThatAreNoAnswerCutTheTurnAndOpenTheNext() async {
        let rig = await parentSheetRig()
        let seen = SessionEventBox(rig.h.session.events)
        await restWithTheQuestionSaid(rig)

        await answerHold(rig, "mejor busca vuelos a Lima")
        await pumpUntil("the words opened a new turn") { rig.h.chat.histories.count >= 2 }
        // The scripted actor ignores the cut (brief §8): the late yes stands
        // for a click that arrives after it.
        _ = await rig.approvals.resolve(requestId: "r1", approved: true)
        await pumpUntilAsync("the card is withdrawn") {
            seen.events.contains(.approvalWithdrawn(requestId: "r1"))
        }
        #expect(rig.tools.executeCalls.isEmpty)
        #expect(rig.h.chat.histories.last?.contains { $0.content.contains("busca vuelos a Lima") } == true)
        #expect(!rig.h.synth.queue.contains(needsClick))
    }

    @Test @MainActor func anAnswerHoldThatHeardNothingLeavesTheSheet() async {
        let rig = await parentSheetRig()
        let seen = SessionEventBox(rig.h.session.events)
        await restWithTheQuestionSaid(rig)

        await answerHold(rig, "")
        await pumpUntil("back at rest") { rig.h.watch.latest.state == .idle }
        #expect(seen.events.contains(.heardNothing))
        #expect(rig.h.watch.latest.sheetParked)
        #expect(rig.h.chat.histories.count == 1)
        #expect(!seen.events.contains(.approvalWithdrawn(requestId: "r1")))
        // Nothing said, nothing answered: the yes that follows is the first
        // answer the voice gives. The notice speaks from its own task, so the
        // count is read once that yes was answered and its line ended.
        await answerHold(rig, "sí")
        await pumpUntil("the yes is answered") { rig.h.synth.queue.contains(needsClick) }
        rig.h.synth.yield(.finished)
        for _ in 0..<50 { await Task.yield() }
        #expect(rig.h.synth.queue.filter { $0 == needsClick }.count == 1, "the empty hold was answered")
        _ = await rig.approvals.resolve(requestId: "r1", approved: true)
        await rig.h.session.awaitClassicTurn()
        #expect(rig.tools.executeCalls.count == 1)
    }

    /// The press must not re-pin the hands' target under a call still parked
    /// on its sheet (planner HIGH-1): only a press that starts a turn does.
    @Test @MainActor func anAnswerHoldLeavesTheHandsTurnAlone() async {
        let rig = await parentSheetRig()
        await restWithTheQuestionSaid(rig)
        let before = rig.tools.beginTurnCount

        await answerHold(rig, "sí")
        await pumpUntil("the voice asks for the click") { rig.h.synth.queue.contains(needsClick) }
        #expect(rig.tools.beginTurnCount == before)

        rig.h.synth.yield(.finished)
        await answerHold(rig, "otra cosa entonces")
        await pumpUntil("the words opened a new turn") { rig.h.chat.histories.count >= 2 }
        #expect(rig.tools.beginTurnCount == before + 1)
        _ = await rig.approvals.resolve(requestId: "r1", approved: false)
        await rig.h.session.awaitClassicTurn()
    }

    /// A question not yet said is no question: the press is the cut #87 made.
    @Test @MainActor func aPressBeforeTheQuestionWasSaidIsStillACut() async {
        let rig = await parentSheetRig()
        let seen = SessionEventBox(rig.h.session.events)
        await holdUntilTheParentSheet(rig)
        await pumpUntil("the voice asks") { timesAsked(rig.h) == 1 }

        await answerHold(rig, "sí")
        await pumpUntil("the yes opened a new turn") { rig.h.chat.histories.count >= 2 }
        _ = await rig.approvals.resolve(requestId: "r1", approved: true)
        await pumpUntilAsync("the card is withdrawn") {
            seen.events.contains(.approvalWithdrawn(requestId: "r1"))
        }
        #expect(rig.tools.executeCalls.isEmpty)
        #expect(!rig.h.synth.queue.contains(needsClick))
    }

    /// The dictation key types; only FN answers the voice.
    @Test @MainActor func theDictationKeyNeverAnswersTheSheet() async {
        let rig = await parentSheetRig()
        await restWithTheQuestionSaid(rig)

        await answerHold(rig, "sí", dictate: true)
        await pumpUntil("the hold went to a turn") { rig.h.chat.histories.count >= 2 }
        #expect(!rig.h.synth.queue.contains(needsClick))
        _ = await rig.approvals.resolve(requestId: "r1", approved: false)
        await rig.h.session.awaitClassicTurn()
        #expect(rig.tools.executeCalls.isEmpty)
    }

    /// D1 (a) is structural, not only the risk list's: a parent sheet whose
    /// tool is low risk still takes the click. A later ADR that lets the
    /// voice approve changes this one guard in `admitsSpokenYes`.
    @Test @MainActor func aLowRiskParentSheetStillTakesTheClick() async {
        let rig = await parentSheetRig()
        rig.tools.setScriptedApproval(ApprovalRequest(
            requestId: "r1", toolName: "find_places", summary: "find cafes", inputJSON: "{}"))
        await restWithTheQuestionSaid(rig)

        await answerHold(rig, "sí")
        await pumpUntil("the voice asks for the click") { rig.h.synth.queue.contains(needsClick) }
        #expect(rig.tools.executeCalls.isEmpty, "a spoken yes approved a parent sheet")
        #expect(rig.h.watch.latest.sheetParked)
        _ = await rig.approvals.resolve(requestId: "r1", approved: false)
        await rig.h.session.awaitClassicTurn()
    }

    /// A click between the press and the release: the hold has nothing left
    /// to answer, so it is an ordinary turn, with its hands pinned for it.
    @Test @MainActor func aClickDuringTheAnswerHoldMakesItAnOrdinaryTurn() async {
        let rig = await parentSheetRig()
        await restWithTheQuestionSaid(rig)
        let before = rig.tools.beginTurnCount

        rig.h.clock.now += 1
        rig.h.transcriber.stoppedText = "sí"
        await rig.h.session.hold()
        await pumpUntil("listening for the answer") { rig.h.watch.latest.state == .listening }
        _ = await rig.approvals.resolve(requestId: "r1", approved: true)
        await pumpUntil("the click acted") { rig.tools.executeCalls.count == 1 }
        await rig.h.session.release()
        await pumpUntil("the words opened a turn") { rig.h.chat.histories.count >= 3 }

        #expect(rig.tools.beginTurnCount == before + 1, "the new turn kept the parked call's hands")
        #expect(!rig.h.synth.queue.contains(needsClick))
        #expect(rig.tools.executeCalls.count == 1)
    }

    /// A job's request took the sheet's place in the voice's ear while the
    /// parent turn rests: a yes is no answer to the parent, and the press is
    /// a cut, as it was before 2a.
    @Test @MainActor func aJobsRequestInFrontIsNotTheParentsToAnswer() async {
        let rig = await parentSheetRig()
        await restWithTheQuestionSaid(rig)
        let job = ApprovalRequest(requestId: "j1", toolName: "run_shell", summary: "ls", inputJSON: "{}")
        await rig.h.session.noteApproval(job)
        let before = rig.tools.beginTurnCount

        await answerHold(rig, "sí")
        await pumpUntil("the yes opened a turn") { rig.h.chat.histories.count >= 2 }
        #expect(rig.tools.beginTurnCount == before + 1)
        #expect(!rig.h.synth.queue.contains(needsClick))
        _ = await rig.approvals.resolve(requestId: "r1", approved: true)
        await rig.h.session.awaitClassicTurn()
        #expect(rig.tools.executeCalls.isEmpty)
    }

    /// Esc over an answer hold drops it: the sheet still waits, and the next
    /// press is judged afresh.
    @Test @MainActor func anEscapedAnswerHoldLeavesTheSheetAndTheNextYesIsAnswered() async {
        let rig = await parentSheetRig()
        let seen = SessionEventBox(rig.h.session.events)
        await restWithTheQuestionSaid(rig)

        rig.h.clock.now += 1
        await rig.h.session.hold()
        await pumpUntil("listening") { rig.h.watch.latest.state == .listening }
        await rig.h.session.discard()
        await pumpUntil("back at rest") { rig.h.watch.latest.state == .idle }
        #expect(rig.h.watch.latest.sheetParked)
        #expect(!seen.events.contains(.approvalWithdrawn(requestId: "r1")))

        await answerHold(rig, "sí")
        await pumpUntil("the voice asks for the click") { rig.h.synth.queue.contains(needsClick) }
        #expect(rig.tools.executeCalls.isEmpty)
        _ = await rig.approvals.resolve(requestId: "r1", approved: false)
        await rig.h.session.awaitClassicTurn()
    }

    /// After a stop the sheet is gone: a later yes answers nothing and is a
    /// turn like any other.
    @Test @MainActor func aYesAfterAStopIsAnOrdinaryTurn() async {
        let rig = await parentSheetRig()
        await restWithTheQuestionSaid(rig)
        await rig.h.session.interrupt()
        _ = await rig.approvals.resolve(requestId: "r1", approved: true)
        await rig.h.session.awaitClassicTurn()

        await answerHold(rig, "sí")
        await pumpUntil("the yes opened a turn") { rig.h.chat.histories.count >= 2 }
        #expect(!rig.h.synth.queue.contains(needsClick))
        #expect(rig.tools.executeCalls.isEmpty)
    }
}
