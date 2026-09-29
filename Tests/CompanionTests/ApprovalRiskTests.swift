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
    for tool in ["open_url", "find_places", "look", "see", "read_focused", "list_apps", "read_skill"] {
        expectEq(ApprovalRisk.of(toolName: tool), .low, "riesgo: \(tool) es bajo")
    }
    let high = [
        "bridge_session", "write_file", "edit_file", "create_document",
        "sheet_write", "run_shell", "click", "type_text", "press_key", "menu",
        "app:slack_v2:slack_v2-send-message", "bash", "delegate", "", "OPEN_URL",
        "totally_new_tool",
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
    for tool in ["write_file", "sheet_write", BridgePolicy.sessionApprovalTool] {
        await h.session.noteApproval(req("r-\(tool)", tool))
        let resolved = await h.session.answerPendingApproval(true)
        expect(!resolved, "alto: \(tool) no se resuelve por voz")
        let still = await h.session.pendingApproval
        expectEq(still?.requestId, "r-\(tool)", "alto: \(tool) sigue pendiente para el clic")
    }
}

@MainActor func testALowRiskRequestStillResolvesByVoice() async {
    let jobs = ApprovingSubmitter()
    let model = SessionModel(jobs: jobs, approvals: nil)
    let h = makeVoiceHarness(jobs: jobs, session: model)
    await h.session.start()
    await pumpUntil("bajo: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.functionCall(
        name: "delegate", arguments: #"{"goal":"buscar cine"}"#, callId: "c1"))
    await pumpUntil("bajo: encargo aceptado") {
        h.transport.sent.contains { $0.contains("function_call_output") }
    }
    jobs.askApproval(req("f1", "find_places"))
    await pumpUntil("bajo: la hoja la tiene") { model.projection.approval?.requestId == "f1" }
    h.transport.yield(.functionCall(
        name: "resolve_approval", arguments: #"{"approved":true}"#, callId: "c2"))
    await pumpUntil("bajo: llega al encargo") {
        jobs.resolutions.contains { $0 == ApprovalVerdict(id: "f1", approved: true) }
    }
}

/// The note must not outlive the sheet: a click closes it, and a later yes
/// finds nothing pending.
@MainActor func testAClickClearsTheVoiceNote() async {
    let jobs = ApprovingSubmitter()
    let model = SessionModel(jobs: jobs, approvals: nil)
    let h = makeVoiceHarness(jobs: jobs, session: model)
    let session = h.session
    model.onApprovalClosed = { id in Task { await session.approvalClosed(id) } }
    await session.noteApproval(req("o1", "open_url"))
    model.send(.job(.started(goal: "x")))
    model.send(.job(.approvalRequested(req("o1", "open_url"))))
    model.send(.approvalAnswered(requestId: "o1", approved: false, remember: false))
    await pumpUntilAsync("clic: la nota se limpia") { await session.pendingApproval == nil }
    let resolved = await session.answerPendingApproval(true)
    expect(!resolved, "clic: un sí posterior no encuentra nada pendiente")
}
