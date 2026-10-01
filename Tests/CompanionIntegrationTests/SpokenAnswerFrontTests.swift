import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Integration fix round 1, item 2 (C2): the reducer lands a spoken answer
// only on the request the sheet shows. When the voice's pending request is
// queued behind another, a spoken yes or no changes nothing, so the voice
// must ask for the click instead of telling the model it was applied, and
// keep the request armed for when it reaches the front.

@Test @MainActor func spokenAnswerFrontTests() async {
    testTheReducerReportsTheSheetsFront()
    await testTheModelForwardsTheFrontToTheVoice()
    await testASpokenYesForARequestBehindTheFrontAsksForTheClick()
    await testASpokenNoForARequestBehindTheFrontAsksForTheClick()
}

private func request(_ id: String, _ tool: String = "find_places") -> ApprovalRequest {
    ApprovalRequest(requestId: id, toolName: tool, summary: "x", inputJSON: "{}")
}

private func fronts(_ effects: [SessionEffect]) -> [String?] {
    effects.compactMap { if case .approvalFront(let id) = $0 { id } else { nil } }
}

@MainActor func testTheReducerReportsTheSheetsFront() {
    var m = SessionMachine()
    expectEq(fronts(m.handle(.job(.approvalRequested(request("a"))))), ["a"],
             "frente: la primera peticion es la que muestra la hoja")
    expectEq(fronts(m.handle(.job(.approvalRequested(request("b"))))), [],
             "frente: una en cola detras no cambia el frente")
    expectEq(fronts(m.handle(.approvalAnswered(requestId: "a", approved: false, remember: false))), ["b"],
             "frente: al cerrar la primera, la siguiente pasa al frente")
    expectEq(fronts(m.handle(.approvalAnswered(requestId: "b", approved: false, remember: false))), [nil],
             "frente: hoja vacia")
}

@MainActor func testTheModelForwardsTheFrontToTheVoice() async {
    let voice = RecordingVoice()
    let model = SessionModel(jobs: nil, approvals: nil, voice: voice)
    model.send(.job(.approvalRequested(request("a"))))
    await pumpUntil("frente: llega a la voz") { voice.fronts == ["a"] }
}

/// A classic session wired to the reducer: `front` sits first on the sheet,
/// then the job's own request `r1` is asked, announced and answered in a
/// later hold with a clear "yes" or "no".
@MainActor private func answerBehindTheFront(_ approved: Bool, _ label: String) async {
    let jobs = GatedJob()
    let box = Q1SessionVoiceBox()
    let model = SessionModel(jobs: jobs, approvals: nil, voice: box)
    let h = await q1Classic(jobs, model: model)
    box.session = h.session
    model.send(.job(.approvalRequested(request("front", "open_url"))))
    await pumpUntilAsync("\(label): la voz sabe que hoja muestra front") {
        await h.session.sheetFront?.requestId == "front"
    }
    await q1AskedAndSaid(h, jobs, "r1")
    await pumpUntil("\(label): r1 queda detras en la hoja") {
        model.projection.approvalQueue.map(\.requestId) == ["front", "r1"]
    }
    await q1HeldKey(h)
    await h.session.noteHeard(approved ? "sí, dale" : "no", pressed: await h.session.timeline.pressed)
    expectEq(await h.session.answerPendingApproval(approved), .needsClick,
             "\(label): la hoja muestra otra; se pide el clic")
    expectEq(await h.session.pendingApproval?.requestId, "r1", "\(label): r1 sigue armada")
    await settle(0.1)
    expectEq(jobs.resolutions, [], "\(label): nada se resolvio")
    expectEq(model.projection.approvalQueue.map(\.requestId), ["front", "r1"], "\(label): las dos esperan su clic")
    // Positive control: once r1 is what the sheet shows, the same answer lands.
    model.send(.approvalAnswered(requestId: "front", approved: false, remember: false))
    await pumpUntil("\(label): el clic niega front") { jobs.resolutions == [false] }
    await pumpUntilAsync("\(label): r1 pasa al frente") { await h.session.sheetFront?.requestId == "r1" }
    await q1HeldKey(h)
    await h.session.noteHeard(approved ? "sí, dale" : "no", pressed: await h.session.timeline.pressed)
    expectEq(await h.session.answerPendingApproval(approved), .resolved, "\(label): ya al frente, resuelve")
    await pumpUntil("\(label): el reductor resuelve r1") { jobs.resolutions == [false, approved] }
    expect(model.projection.approvalQueue.isEmpty, "\(label): la hoja queda vacia")
    jobs.open()
    await h.session.hangUp()
}

@MainActor func testASpokenYesForARequestBehindTheFrontAsksForTheClick() async {
    await answerBehindTheFront(true, "frente si")
}

@MainActor func testASpokenNoForARequestBehindTheFrontAsksForTheClick() async {
    await answerBehindTheFront(false, "frente no")
}
