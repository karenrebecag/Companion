import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// classic-spoken-yes-parent-sheet, phase 1b: a classic hold turn whose parent
// tool waits on the sheet rests, and the voice asks the question once. It
// counts as asked only when its audio ended (`announcedAt`), the same rule a
// job's question follows; a press over it leaves it unsaid.

private let workLine = Acknowledgement.working(tool: "open_url", .es)

@Suite struct ParentSheetQuestion {
    @Test @MainActor func theRestingTurnAsksOnceAndItCountsOnlyWhenItFinishes() async {
        let rig = await parentSheetRig()
        await holdUntilTheParentSheet(rig)
        await pumpUntil("the voice asks") { timesAsked(rig.h) == 1 }
        #expect(rig.h.watch.latest.state == .idle, "the turn rests while the sheet waits")
        #expect(rig.h.watch.latest.sheetParked)
        #expect(await parentAnnouncedAt(rig.h) == nil, "asked is not said: the audio has not ended")

        rig.h.synth.yield(.finished)
        await pumpUntilAsync("the question counts as said") { await parentAnnouncedAt(rig.h) != nil }
        #expect(timesAsked(rig.h) == 1, "one question per sheet")

        // The click: the turn takes its voice back and the reply is heard.
        _ = await rig.approvals.resolve(requestId: "r1", approved: true)
        await pumpUntil("the voice is the turn's again") { rig.h.watch.latest.state == .speaking }
        #expect(!rig.h.watch.latest.sheetParked)
        await rig.h.session.awaitClassicTurn()
        #expect(rig.tools.executeCalls.count == 1)
        #expect(rig.h.synth.queue.contains { $0.contains("Listo") }, "the reply after the click is spoken")
        #expect(timesAsked(rig.h) == 1)
    }

    /// The model spoke before calling the tool: its line ends first, then the
    /// question, and only that second end makes it said.
    @Test @MainActor func aLineBeforeTheToolEndsBeforeTheQuestionIsAsked() async {
        let rig = await parentSheetRig(firstRound: [.text("Voy a abrirla."), .toolCalls([parentOpenCall])])
        await holdUntilTheParentSheet(rig)
        await pumpUntil("the line plays") { rig.h.watch.latest.state == .speaking }
        #expect(timesAsked(rig.h) == 0, "the question never talks over the turn's own line")

        rig.h.synth.yield(.finished)
        await pumpUntil("the voice asks") { timesAsked(rig.h) == 1 }
        #expect(rig.h.watch.latest.state == .idle)
        #expect(await parentAnnouncedAt(rig.h) == nil, "the line's end is not the question's")

        rig.h.synth.yield(.finished)
        await pumpUntilAsync("the question counts as said") { await parentAnnouncedAt(rig.h) != nil }
        let queue = rig.h.synth.queue
        let line = queue.firstIndex { $0.contains("Voy a abrirla") }
        let asking = queue.firstIndex(of: parentQuestion)
        #expect(line != nil && asking != nil && line! < asking!, "the line, then the question: \(queue)")
        _ = await rig.approvals.resolve(requestId: "r1", approved: true)
        await rig.h.session.awaitClassicTurn()
    }

    /// Two sheets in one round: the turn stays at rest until the round ends,
    /// so the second is asked in the same gap, and counts on its own end.
    @Test @MainActor func eachSheetOfARoundIsAskedOnItsOwn() async {
        let second = ToolCallRef(id: "c2", name: "open_url", arguments: #"{"url":"https://example.org"}"#)
        let rig = await parentSheetRig(firstRound: [.toolCalls([parentOpenCall, second])])
        await holdUntilTheParentSheet(rig)
        await pumpUntil("the first question") { timesAsked(rig.h) == 1 }
        rig.h.synth.yield(.finished)
        await pumpUntilAsync("the first counts as said") { await parentAnnouncedAt(rig.h) != nil }

        // Real request ids are unique; a repeat would read as already closed.
        rig.tools.setScriptedApproval(ApprovalRequest(
            requestId: "r2", toolName: "open_url", summary: "open example.org", inputJSON: "{}"))
        _ = await rig.approvals.resolve(requestId: "r1", approved: true)
        await pumpUntil("the second question") { timesAsked(rig.h) == 2 }
        #expect(rig.h.watch.latest.state == .idle, "still at rest between the round's sheets")
        let seen = await rig.h.session.pendingApprovalSeen
        #expect(seen?.requestId == "r2" && seen?.announcedAt == nil, "the second is not said yet")

        rig.h.synth.yield(.finished)
        await pumpUntilAsync("the second counts as said") {
            let seen = await rig.h.session.pendingApprovalSeen
            return seen?.requestId == "r2" && seen?.announcedAt != nil
        }
        _ = await rig.approvals.resolve(requestId: "r2", approved: true)
        await rig.h.session.awaitClassicTurn()
        #expect(rig.tools.executeCalls.count == 2)
    }

    /// A click that denies still gives the turn its voice back: the model
    /// answers the refusal, and nothing ran.
    @Test @MainActor func aDenyingClickResumesTheTurnAndActsOnNothing() async {
        let rig = await parentSheetRig()
        await holdUntilTheParentSheet(rig)
        await pumpUntil("the voice asks") { timesAsked(rig.h) == 1 }
        rig.h.synth.yield(.finished)

        _ = await rig.approvals.resolve(requestId: "r1", approved: false)
        await pumpUntil("the voice is the turn's again") { rig.h.watch.latest.state == .speaking }
        await rig.h.session.awaitClassicTurn()
        #expect(rig.tools.executeCalls.isEmpty)
        #expect(rig.h.synth.queue.contains { $0.contains("Listo") })
    }

    /// A click while the question still sounds: the resume ends the question
    /// and the turn is the only speaker again.
    @Test @MainActor func aClickDuringTheQuestionEndsItAndTheTurnSpeaks() async {
        let rig = await parentSheetRig()
        await holdUntilTheParentSheet(rig)
        await pumpUntil("the voice asks") { timesAsked(rig.h) == 1 }

        _ = await rig.approvals.resolve(requestId: "r1", approved: true)
        await pumpUntil("the voice is the turn's again") { rig.h.watch.latest.state == .speaking }
        #expect(rig.h.synth.stopped, "the question was not cut for the reply")
        await rig.h.session.awaitClassicTurn()
        #expect(rig.tools.executeCalls.count == 1)
        #expect(rig.h.synth.queue.contains { $0.contains("Listo") })
    }

    /// A press over the question cuts its audio: unsaid, so a later yes would
    /// be the click's. Words that are no answer then cut the turn (#87).
    @Test @MainActor func aPressOverTheQuestionLeavesItUnsaidAndWordsCutTheTurn() async {
        let rig = await parentSheetRig()
        let seen = SessionEventBox(rig.h.session.events)
        await holdUntilTheParentSheet(rig)
        await pumpUntil("the voice asks") { timesAsked(rig.h) == 1 }

        rig.h.transcriber.stoppedText = "mejor busca vuelos"
        await rig.h.session.hold()
        await pumpUntil("listening again") { rig.h.watch.latest.state == .listening }
        rig.h.synth.yield(.finished)
        #expect(await parentAnnouncedAt(rig.h) == nil, "a cut question was stamped as said")

        await rig.h.session.release()
        // The scripted actor ignores the cut (brief §8): a late yes stands
        // for the click that arrives after it.
        await pumpUntil("the words opened a new turn") { rig.h.chat.histories.count >= 2 }
        _ = await rig.approvals.resolve(requestId: "r1", approved: true)
        await pumpUntilAsync("the card is withdrawn") {
            seen.events.contains(.approvalWithdrawn(requestId: "r1"))
        }
        #expect(rig.tools.executeCalls.isEmpty, "a late yes acted for the cut turn")
        #expect(rig.h.chat.histories.last?.contains { $0.content.contains("mejor busca vuelos") } == true,
                "the words open the new turn")
    }

    /// Stop at rest still reaches the parked turn: nothing runs, the card goes.
    @Test @MainActor func aStopAtRestActsOnNothingAndWithdrawsTheCard() async {
        let rig = await parentSheetRig()
        let seen = SessionEventBox(rig.h.session.events)
        await holdUntilTheParentSheet(rig)
        await pumpUntil("the voice asks") { timesAsked(rig.h) == 1 }

        await rig.h.session.interrupt()
        _ = await rig.approvals.resolve(requestId: "r1", approved: true)
        await rig.h.session.awaitClassicTurn()

        #expect(rig.tools.executeCalls.isEmpty, "a late yes acted for the stopped turn")
        await pumpUntilAsync("the card is withdrawn") {
            seen.events.contains(.approvalWithdrawn(requestId: "r1"))
        }
        #expect(!rig.h.watch.latest.sheetParked)
    }

    /// At rest the gap is the question's: a work line that comes due then
    /// would talk over it.
    @Test @MainActor func theWorkLineNeverTalksOverTheQuestion() async {
        let slow = TestGate()
        let returned = RaisedFlag()
        let rig = await parentSheetRig(slow: slow, slowReturned: returned)
        await holdUntilTheParentSheet(rig)
        await pumpUntil("the voice asks") { timesAsked(rig.h) == 1 }
        await pumpUntil("the work line's wait began") { slow.entered }

        slow.open()
        await pumpUntil("the work line came due") { returned.isRaised }
        for _ in 0..<20 { await Task.yield() }
        #expect(!rig.h.synth.queue.contains(workLine))
        _ = await rig.approvals.resolve(requestId: "r1", approved: true)
        await rig.h.session.awaitClassicTurn()
        #expect(!rig.h.synth.queue.contains(workLine))
    }

    /// Hands-free keeps its ear shut for the whole wait (brief §9, A3): no
    /// rest and no question nobody could answer, and its work line stays.
    @Test @MainActor func handsFreeNeitherRestsNorAsks() async {
        let slow = TestGate()
        let rig = await parentSheetRig(slow: slow)
        await rig.h.session.start()
        await pumpUntil("listening") { rig.h.watch.latest.state == .listening }
        await rig.h.session.advance()
        await pumpUntilAsync("the sheet is up") { !rig.approvals.requests.isEmpty }
        slow.open()
        await pumpUntil("the work line plays") { rig.h.synth.queue.contains(workLine) }

        #expect(!rig.h.watch.latest.sheetParked)
        #expect(timesAsked(rig.h) == 0)
        _ = await rig.approvals.resolve(requestId: "r1", approved: true)
        await rig.h.session.awaitClassicTurn()
        #expect(rig.tools.executeCalls.count == 1)
        #expect(timesAsked(rig.h) == 0)
    }
}
