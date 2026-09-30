import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing

// Wave 20c D1 (H1). `resolve_approval` is a call the MODEL makes, so what a
// spoken yes may settle is an allowlist of low-risk requests, always the exact
// request that was noted, and never one already answered by a click.

@Test @MainActor func approvalRiskTests() async {
    testRiskIsAnAllowlistOfReadOnlyAndSeparatelyGatedTools()
    testTheSpokenAnswerIsBoundToTheNotedRequest()
    testAClickedRequestCannotBeAnsweredAgainByVoice()
    await testAHighRiskRequestIsRefusedAndStaysPending()
    await testALowRiskRequestStillResolvesByVoice()
    await testAClickClearsTheVoiceNote()
}

private func req(_ id: String, _ tool: String) -> ApprovalRequest {
    ApprovalRequest(requestId: id, toolName: tool, summary: "", inputJSON: "{}")
}

@MainActor func testRiskIsAnAllowlistOfReadOnlyAndSeparatelyGatedTools() {
    for tool in ["find_places", "look", "see", "read_focused", "list_apps", "read_skill"] {
        expectEq(ApprovalRisk.of(toolName: tool), .low, "riesgo: \(tool) es bajo")
    }
    let high = [
        "bridge_session", "write_file", "edit_file", "create_document",
        "sheet_write", "run_shell", "click", "type_text", "press_key", "menu",
        "app:slack_v2:slack_v2-send-message", "bash", "delegate", "", "OPEN_URL",
        "totally_new_tool",
        // A pending open_url is for a host the user never said (the gate only
        // asks then), so the model must not settle it: it is the exfil sink.
        "open_url",
    ]
    for tool in high {
        expectEq(ApprovalRisk.of(toolName: tool), .high, "riesgo: \(tool) es alto")
    }
}

/// The note said "o1"; the sheet shows "w1". Answering the first of the queue
/// would approve a write nobody noted.
@MainActor func testTheSpokenAnswerIsBoundToTheNotedRequest() {
    var m = SessionMachine()
    _ = m.handle(.job(.started(goal: "x")))
    _ = m.handle(.job(.approvalRequested(req("w1", "write_file"))))
    _ = m.handle(.job(.approvalRequested(req("o1", "open_url"))))
    let fx = m.handle(.approvalSpoken(requestId: "o1", approved: true))
    expect(fx.isEmpty, "hablado: lo que la hoja muestra no es lo anotado, no resuelve")
    expectEq(m.projection.approval?.requestId, "w1", "hablado: la hoja conserva la escritura")

    let ok = m.handle(.approvalSpoken(requestId: "w1", approved: false))
    expect(ok.contains(.resolveApproval(requestId: "w1", approved: false, remember: false)),
           "hablado: la petición exacta que muestra la hoja sí se resuelve")
}

@MainActor func testAClickedRequestCannotBeAnsweredAgainByVoice() {
    var m = SessionMachine()
    _ = m.handle(.job(.started(goal: "x")))
    _ = m.handle(.job(.approvalRequested(req("o1", "open_url"))))
    _ = m.handle(.approvalAnswered(requestId: "o1", approved: false, remember: false))
    _ = m.handle(.job(.approvalRequested(req("b1", BridgePolicy.sessionApprovalTool))))
    let fx = m.handle(.approvalSpoken(requestId: "o1", approved: true))
    expect(fx.isEmpty, "clic: un sí hablado tardío no resuelve nada de la cola")
    expectEq(m.projection.approval?.requestId, "b1", "clic: la hoja del puente sigue esperando")
}

@MainActor func testAHighRiskRequestIsRefusedAndStaysPending() async {
    let h = makeVoiceHarness(jobs: ApprovingSubmitter())
    for tool in ["write_file", "sheet_write", "open_url", BridgePolicy.sessionApprovalTool] {
        await h.session.noteApproval(req("r-\(tool)", tool))
        let resolved = await h.session.answerPendingApproval(true)
        expectEq(resolved, .needsClick, "alto: \(tool) no se resuelve por voz")
        let still = await h.session.pendingApproval
        expectEq(still?.requestId, "r-\(tool)", "alto: \(tool) sigue pendiente para el clic")
    }
}

/// Merged with 16q-1: realtime has no hold to bind a yes to, so it always
/// takes the click there. A low-risk request still resolves by voice in
/// classic, once the voice asked it and she said a clear yes in a later hold.
@MainActor func testALowRiskRequestStillResolvesByVoice() async {
    let jobs = GatedJob()
    let model = SessionModel(jobs: jobs, approvals: nil)
    let h = await q1Classic(jobs, model: model, rounds: [[.handoff(q1Flights)], q1SaysYes])
    await q1AskedAndSaid(h, jobs, "f1", tool: "find_places")
    h.clock.now += 5
    h.transcriber.stoppedText = "sí, dale"
    await h.session.hold()
    await pumpUntil("bajo: hold") { h.watch.latest.state == .listening }
    await h.session.release()
    await h.session.awaitClassicTurn()
    await pumpUntil("bajo: llega al encargo") { jobs.resolutions == [true] }
    jobs.open()
    await h.session.hangUp()
}

/// The note must not outlive the sheet: a click closes it, and a later yes
/// finds nothing pending.
@MainActor func testAClickClearsTheVoiceNote() async {
    let jobs = ApprovingSubmitter()
    // The close reaches the session through the voice port (16q-1's
    // `approvalClosed` effect), where 20c wired `onApprovalClosed`.
    let port = Q1SessionVoiceBox()
    let model = SessionModel(jobs: jobs, approvals: nil, voice: port)
    let h = makeVoiceHarness(jobs: jobs, session: model)
    let session = h.session
    port.session = session
    await session.noteApproval(req("o1", "open_url"))
    model.send(.job(.started(goal: "x")))
    model.send(.job(.approvalRequested(req("o1", "open_url"))))
    model.send(.approvalAnswered(requestId: "o1", approved: false, remember: false))
    await pumpUntilAsync("clic: la nota se limpia") { await session.pendingApproval == nil }
    let resolved = await session.answerPendingApproval(true)
    expectEq(resolved, .nothingPending, "clic: un sí posterior no encuentra nada pendiente")
}
