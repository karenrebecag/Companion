import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// The classic rig shared by the classic-spoken-yes-parent-sheet suites: a
// hold whose parent tool (`open_url`) waits on a sheet that only the test
// answers, so the turn rests on it for as long as the test needs.

let parentSheetRequest = ApprovalRequest(
    requestId: "r1", toolName: "open_url", summary: "open example.com", inputJSON: "{}")
let parentOpenCall = ToolCallRef(
    id: "c1", name: "open_url", arguments: #"{"url":"https://example.com"}"#)
let parentQuestion = Escalation.approvalAskedSpoken(.es)

struct ParentSheetRig {
    let h: VoiceHarness
    let tools: FakeParentTools
    let approvals: ScriptedApprovals
}

/// Set once the work line's wait has returned, so a negative about the line
/// is read after its racer had the chance to speak.
final class RaisedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    var isRaised: Bool { lock.withLock { raised } }
    func raise() { lock.withLock { raised = true } }
}

/// The work line never races the sheet here: without it the order of the
/// turn's own audio and the park would depend on the machine's load.
/// `slow`, when given, ends the work line's wait; the test must open it
/// before the round ends, since a `TestGate` does not hear the cancel.
@MainActor func parentSheetRig(
    firstRound: [ChatDelta] = [.toolCalls([parentOpenCall])],
    slow: TestGate? = nil, slowReturned: RaisedFlag? = nil
) async -> ParentSheetRig {
    let approvals = ScriptedApprovals(park: true)
    let tools = FakeParentTools(handledNames: ["open_url"])
    tools.setScriptedApproval(parentSheetRequest)
    let h = makeVoiceHarness(key: nil, language: .es, parentTools: tools, approvals: approvals)
    h.chat.rounds = [firstRound, [.text("Listo.")]]
    h.transcriber.stoppedText = "abre la pagina"
    let classic = await h.session.classic
    if let slow {
        classic.slowToolWait = {
            await slow.wait()
            slowReturned?.raise()
        }
    } else {
        classic.slowToolWait = {
            do { try await Task.sleep(for: .seconds(600)) } catch {}
        }
    }
    return ParentSheetRig(h: h, tools: tools, approvals: approvals)
}

@MainActor func holdUntilTheParentSheet(_ rig: ParentSheetRig) async {
    await rig.h.session.hold()
    await pumpUntil("listening") { rig.h.watch.latest.state == .listening }
    await rig.h.session.release()
    await pumpUntilAsync("the sheet is up") { !rig.approvals.requests.isEmpty }
}

@MainActor func timesAsked(_ h: VoiceHarness) -> Int {
    h.synth.queue.filter { $0 == parentQuestion }.count
}

@MainActor func parentAnnouncedAt(_ h: VoiceHarness) async -> TimeInterval? {
    await h.session.pendingApprovalSeen?.announcedAt
}

/// The turn rests, the voice asks, and the question's audio ends.
@MainActor func restWithTheQuestionSaid(_ rig: ParentSheetRig) async {
    await holdUntilTheParentSheet(rig)
    await pumpUntil("the voice asks") { timesAsked(rig.h) == 1 }
    rig.h.synth.yield(.finished)
    await pumpUntilAsync("the question counts as said") { await parentAnnouncedAt(rig.h) != nil }
}

/// One more hold with `words`, past the click guard's dwell.
@MainActor func answerHold(_ rig: ParentSheetRig, _ words: String, dictate: Bool = false) async {
    rig.h.clock.now += 1
    rig.h.transcriber.stoppedText = words
    await rig.h.session.hold(dictate: dictate)
    await pumpUntil("listening for the answer") { rig.h.watch.latest.state == .listening }
    await rig.h.session.release()
}
