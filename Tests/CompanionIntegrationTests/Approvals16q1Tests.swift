import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing
import CompanionUITestSupport
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// 16q-1 (decisions 1 and 3 of the Incredible audit). An MCP tool's approval
// in the realtime voice is a sheet with Allow / Deny and the 60 s auto-deny,
// like the parent's gates; a spoken "yes" never approves it (Companion has
// no judge model behind the model's word), a spoken "no" may refuse it. In
// classic the voice asks a job's permission in one sentence and marks it
// announced, so `SpokenYes` works as designed; app and MCP writes still need
// the click.

@Test @MainActor func approvals16q1Tests() async {
    await testAnMCPRequestReachesTheSheetAndWaitsForTheClick()
    await testTheSheetsAllowSendsTheApproval()
    await testTheSheetsDenySendsTheRefusal()
    await testAnUnansweredMCPRequestDiesInTheAutoDeny()
    await testWithoutAnApprovalsActorTheMCPRequestFailsClosed()
    await testASpokenYesNeverApprovesAnMCPTool()
    await testASpokenNoRefusesAnMCPTool()
    await testStoppingTheVoiceDeniesThePendingMCPRequest()
    testTheMCPPromptSendsTheUserToTheCard()
    testTheOrbStopsTheVoiceWhileAJobRunsBehindIt()
    testTheJobCardsStopIsThatJobs()
    testWithNoJobTheBrakeIsTheVoices()
    await testCancellingOneJobByIDReachesTheRunnerAndLeavesTheOthers()
    await testTheChatsOwnJobStopLeavesItsRecord()
    await testTheIslandsStopReachesTheRightBrake()
    await testTheClassicVoiceAsksTheJobsPermissionAndMarksItAnnounced()
    await testAQuestionCutByAPressWasNotAnnounced()
    await testAnAppWriteIsAskedAloudButTheYesNeverApproves()
    await testASpokenYesNeverTouchesAnAppWriteThatIsFirstOnTheSheet()
}

// MARK: - MCP approvals in realtime

private struct WireApproval: Equatable {
    let id: String
    let approve: Bool
}

/// What the session sent to the server as an MCP decision, parsed.
private func wireApprovals(_ sent: [String]) -> [WireApproval] {
    sent.compactMap { text in
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = root["item"] as? [String: Any],
              item["type"] as? String == "mcp_approval_response",
              let id = item["approval_request_id"] as? String,
              let approve = item["approve"] as? Bool else { return nil }
        return WireApproval(id: id, approve: approve)
    }
}

private struct MCPRig {
    let harness: VoiceHarness
    let model: SessionModel
    var approvals: [WireApproval] { wireApprovals(harness.transport.sent) }
}

@MainActor private func liveMCP(
    timeout: TimeInterval = 60, withApprovals: Bool = true
) async -> MCPRig {
    let actor = Approvals(clock: RealtimeClock(), timeout: timeout)
    let model = SessionModel(jobs: nil, approvals: withApprovals ? actor : nil)
    let h = makeVoiceHarness(approvals: withApprovals ? actor : nil, session: model)
    await h.session.start()
    await pumpUntil("mcp: escuchando") { h.watch.latest.state == .listening }
    h.transport.yield(.mcpApprovalRequest(
        id: "req9", server: "docs", tool: "search", argumentsJSON: #"{"q":"x"}"#))
    return MCPRig(harness: h, model: model)
}

/// A request through the same stream: once on the sheet, earlier sends are done.
@MainActor private func passedByABarrier(_ rig: MCPRig) async {
    let before = rig.model.projection.approvalQueue.count
    rig.harness.transport.yield(.mcpApprovalRequest(
        id: "barrera", server: "docs", tool: "search", argumentsJSON: "{}"))
    await pumpUntil("barrera: llega a la hoja") { rig.model.projection.approvalQueue.count == before + 1 }
}

@MainActor func testAnMCPRequestReachesTheSheetAndWaitsForTheClick() async {
    let rig = await liveMCP()
    await pumpUntil("mcp: la hoja tiene la peticion") {
        rig.model.projection.approval?.requestId == "req9"
    }
    expectEq(rig.model.projection.approval?.toolName, "docs/search", "mcp: la hoja dice servidor/tool")
    await passedByABarrier(rig)
    expect(rig.approvals.isEmpty, "mcp: nada viaja al servidor antes del clic")
    await rig.harness.session.hangUp()
}

@MainActor func testTheSheetsAllowSendsTheApproval() async {
    let rig = await liveMCP()
    await pumpUntil("mcp allow: en la hoja") { rig.model.projection.approval?.requestId == "req9" }
    rig.model.send(.approvalAnswered(requestId: "req9", approved: true, remember: false))
    await pumpUntil("mcp allow: viaja aprobada") { rig.approvals == [WireApproval(id: "req9", approve: true)] }
    expect(rig.model.projection.approval == nil, "mcp allow: la hoja se vacia")
    await rig.harness.session.hangUp()
}

@MainActor func testTheSheetsDenySendsTheRefusal() async {
    let rig = await liveMCP()
    await pumpUntil("mcp deny: en la hoja") { rig.model.projection.approval?.requestId == "req9" }
    rig.model.send(.approvalAnswered(requestId: "req9", approved: false, remember: false))
    await pumpUntil("mcp deny: viaja rechazada") { rig.approvals == [WireApproval(id: "req9", approve: false)] }
    await rig.harness.session.hangUp()
}

/// The same actor as the parent's gates, so the same deadline.
@MainActor func testAnUnansweredMCPRequestDiesInTheAutoDeny() async {
    let rig = await liveMCP(timeout: 0.15)
    await pumpUntil("mcp autoDeny: viaja rechazada") {
        rig.approvals == [WireApproval(id: "req9", approve: false)]
    }
    await rig.harness.session.hangUp()
}

@MainActor func testWithoutAnApprovalsActorTheMCPRequestFailsClosed() async {
    let rig = await liveMCP(withApprovals: false)
    await pumpUntil("mcp sin actor: se rechaza sola") {
        rig.approvals == [WireApproval(id: "req9", approve: false)]
    }
    await rig.harness.session.hangUp()
}

/// The invariant this whole item keeps: the model reports the yes, and a
/// server's output can plant words in front of that model.
@MainActor func testASpokenYesNeverApprovesAnMCPTool() async {
    let rig = await liveMCP()
    await pumpUntil("mcp si: en la hoja") { rig.model.projection.approval?.requestId == "req9" }
    let answer = await rig.harness.session.answerPendingApproval(true)
    expectEq(answer, .needsClick, "mcp si: el si hablado pide el clic")
    await passedByABarrier(rig)
    expect(rig.approvals.isEmpty, "mcp si: nada viaja al servidor")
    expectEq(rig.model.projection.approval?.requestId, "req9", "mcp si: la hoja sigue esperando")
    await rig.harness.session.hangUp()
}

@MainActor func testASpokenNoRefusesAnMCPTool() async {
    let rig = await liveMCP()
    await pumpUntil("mcp no: en la hoja") { rig.model.projection.approval?.requestId == "req9" }
    let answer = await rig.harness.session.answerPendingApproval(false)
    expectEq(answer, .resolved, "mcp no: el no hablado se resuelve sin clic")
    await pumpUntil("mcp no: viaja rechazada") { rig.approvals == [WireApproval(id: "req9", approve: false)] }
    await pumpUntil("mcp no: la hoja se vacia") { rig.model.projection.approval == nil }
    await rig.harness.session.hangUp()
}

/// The voice brake refuses what the voice turn was waiting on.
@MainActor func testStoppingTheVoiceDeniesThePendingMCPRequest() async {
    let rig = await liveMCP()
    await pumpUntil("mcp stop: en la hoja") { rig.model.projection.approval?.requestId == "req9" }
    rig.model.send(.voice(TurnSnapshot(state: .thinking, pipeline: .realtime)))
    rig.model.send(.stopVoice)
    await pumpUntil("mcp stop: viaja rechazada") { rig.approvals == [WireApproval(id: "req9", approve: false)] }
    expect(rig.model.projection.approval == nil, "mcp stop: la hoja se vacia")
    await rig.harness.session.hangUp()
}

/// The model says one short sentence; the card carries the detail and the
/// yes is the click's, not a call the model makes.
func testTheMCPPromptSendsTheUserToTheCard() {
    let en = MCPServerConfig.approvalPrompt(server: "docs", tool: "search", .en)
    let es = MCPServerConfig.approvalPrompt(server: "docs", tool: "search", .es)
    expect(en.lowercased().contains("card"), "prompt en: manda a la tarjeta")
    expect(es.lowercased().contains("tarjeta"), "prompt es: manda a la tarjeta")
    expect(!en.contains("with their decision"), "prompt en: ya no pide resolver con su decision")
    expect(!es.contains("con su decisión"), "prompt es: ya no pide resolver con su decision")
}

// MARK: - Which brake the island's stop is

@MainActor private func projection(_ build: (inout SessionMachine) -> Void) -> SessionProjection {
    var m = SessionMachine()
    build(&m)
    return m.projection
}

/// A job behind the user's own turn: the orb is the voice's brake.
@MainActor func testTheOrbStopsTheVoiceWhileAJobRunsBehindIt() {
    let p = projection { m in
        _ = m.handle(.job(.started(goal: "x"), from: JobID("j")))
        _ = m.handle(.voice(TurnSnapshot(state: .speaking, pipeline: .realtime)))
    }
    expectEq(IslandStop.brake(for: p), .voice, "freno: con la voz delante, es el de la voz")
}

/// The job card in front: its stop is that job's.
@MainActor func testTheJobCardsStopIsThatJobs() {
    let p = projection { m in
        _ = m.handle(.job(.started(goal: "x"), from: JobID("j")))
    }
    expectEq(IslandStop.brake(for: p), .job(JobID("j")), "freno: la tarjeta del encargo para ese encargo")
}

@MainActor func testWithNoJobTheBrakeIsTheVoices() {
    let p = projection { m in
        _ = m.handle(.voice(TurnSnapshot(state: .thinking, pipeline: .realtime)))
    }
    expectEq(IslandStop.brake(for: p), .voice, "freno: sin encargo, el de la voz")
}

// MARK: - Per-job stop through the chat and the model

private final class IDRecordingSubmitter: JobSubmitter, @unchecked Sendable {
    private let lock = NSLock()
    private var _byID: [JobID] = []
    private var _total = 0
    var byID: [JobID] { lock.withLock { _byID } }
    var total: Int { lock.withLock { _total } }
    func submit(
        _ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult { JobResult(output: "", isError: false) }
    func cancel() async { lock.withLock { _total += 1 } }
    func cancel(job id: JobID) async { lock.withLock { _byID.append(id) } }
    func submit(
        _ handoff: Handoff, as id: JobID, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try await submit(handoff, events: events)
    }
    func resolveApproval(requestId: String, approved: Bool) async {}
    var isBusy: Bool { get async { false } }
}

@MainActor private func chat(_ jobs: any JobSubmitter) -> ChatViewModel {
    let vm = ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
        store: MemoryConversationStore(), config: .default, jobSubmitter: jobs)
    vm.onAppear()
    return vm
}

@MainActor func testCancellingOneJobByIDReachesTheRunnerAndLeavesTheOthers() async {
    let jobs = IDRecordingSubmitter()
    let vm = chat(jobs)
    vm.receive(.job(.started(goal: "uno"), from: JobID("a")))
    vm.receive(.job(.started(goal: "dos"), from: JobID("b")))
    vm.cancelJob(JobID("a"))
    await pumpUntil("por id: llega al runner") { jobs.byID == [JobID("a")] }
    expectEq(jobs.total, 0, "por id: el freno total no se usa")
    expectEq(vm.session.projection.job?.id, JobID("b"), "por id: el otro encargo sube y sigue")
}

@MainActor func testTheChatsOwnJobStopLeavesItsRecord() async {
    let jobs = IDRecordingSubmitter()
    let vm = chat(jobs)
    let id = vm.startJob(goal: "ordenar Descargas")
    vm.cancelJob(id)
    await pumpUntil("chat propio: llega al runner") { jobs.byID == [id] }
    expect(vm.messages.contains { $0.isStatus && $0.text.contains("ordenar Descargas") },
           "chat propio: deja el registro de lo que hizo")
    expect(vm.cancelledJob, "chat propio: queda marcado como parado")
}

// MARK: - Classic: the voice asks in one sentence

private let flights = Handoff(goal: "busca vuelos en Safari", context: "")

// Low risk (20c D1), so the spoken yes is judged on hold, words and naming alone.
private func sheetRequest(_ id: String, tool: String = "find_places") -> ApprovalRequest {
    ApprovalRequest(requestId: id, toolName: tool, summary: "borrar build", inputJSON: "{}")
}

@MainActor private func classicWithAJob(
    _ jobs: GatedJob
) async -> VoiceHarness {
    let h = makeVoiceHarness(jobs: jobs, language: .es)
    h.transcriber.stoppedText = "limpia el build"
    h.chat.rounds = [[.handoff(flights)], [.text("Resumen.")]]
    await h.session.hold()
    await pumpUntil("clasico: escuchando") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("clasico: el encargo arranco") { jobs.goals.count == 1 }
    h.synth.yield(.finished)
    await pumpUntil("clasico: el turno acabo") { h.watch.latest.state == .idle }
    return h
}

@MainActor private func heldKey(_ h: VoiceHarness) async {
    h.clock.now += 5
    await h.session.hold()
    await pumpUntil("clasico: hold") { h.watch.latest.state == .listening }
    h.clock.now += 1
}

@MainActor func testTheClassicVoiceAsksTheJobsPermissionAndMarksItAnnounced() async {
    let jobs = GatedJob()
    let h = await classicWithAJob(jobs)
    jobs.ask(sheetRequest("r1"))
    let question = Escalation.approvalAskedSpoken(.es)
    await pumpUntil("pregunta: la voz la dice") { h.synth.queue.contains(question) }
    expectEq(h.synth.queue.filter { $0 == question }.count, 1, "pregunta: en una sola frase, una vez")
    expect(await h.session.pendingApprovalSeen?.announcedAt == nil,
           "pregunta: encolada no es dicha; aun no cuenta")
    h.synth.yield(.finished)
    await pumpUntilAsync("pregunta: al terminar de sonar queda anunciada") {
        await h.session.pendingApprovalSeen?.announcedAt != nil
    }
    await heldKey(h)
    await h.session.noteHeard("sí", pressed: await h.session.timeline.pressed)
    let answer = await h.session.answerPendingApproval(true)
    expectEq(answer, .resolved, "pregunta: dicha antes del hold, el si hablado la contesta")
    jobs.open()
    await h.session.hangUp()
}

/// A press over the question cuts it: what was never said cannot be answered.
@MainActor func testAQuestionCutByAPressWasNotAnnounced() async {
    let jobs = GatedJob()
    let h = await classicWithAJob(jobs)
    jobs.ask(sheetRequest("r2"))
    await pumpUntil("cortada: la voz la encola") {
        h.synth.queue.contains(Escalation.approvalAskedSpoken(.es))
    }
    await heldKey(h)
    expect(await h.session.pendingApprovalSeen?.announcedAt == nil, "cortada: el hold la cortó, no se dijo")
    let answer = await h.session.answerPendingApproval(true)
    expectEq(answer, .needsClick, "cortada: el si hablado pide el clic")
    jobs.open()
    await h.session.hangUp()
}

/// Invariant, unchanged by the question: an app write takes the click.
@MainActor func testAnAppWriteIsAskedAloudButTheYesNeverApproves() async {
    let jobs = GatedJob()
    let h = await classicWithAJob(jobs)
    jobs.ask(sheetRequest("r3", tool: "app:slack_v2:slack_v2-send-message"))
    await pumpUntil("app: la voz pregunta") {
        h.synth.queue.contains(Escalation.approvalAskedSpoken(.es))
    }
    h.synth.yield(.finished)
    await pumpUntilAsync("app: queda anunciada") {
        await h.session.pendingApprovalSeen?.announcedAt != nil
    }
    await heldKey(h)
    let answer = await h.session.answerPendingApproval(true)
    expectEq(answer, .needsClick, "app: aunque se pregunto, el si hablado nunca la aprueba")
    let no = await h.session.answerPendingApproval(false)
    expectEq(no, .resolved, "app: el no hablado si la rechaza")
    jobs.open()
    await h.session.hangUp()
}

/// The hole the 16q-3 spec found: the yes is admitted for the job's request
/// (the one the voice asked), but the sheet shows the chat's app write
/// first. The answer must never land on the app write. Merged with 20c D1,
/// it lands only on the request the sheet shows: here it lands on nothing,
/// and both requests wait for their click.
@MainActor func testASpokenYesNeverTouchesAnAppWriteThatIsFirstOnTheSheet() async {
    let jobs = GatedJob()
    let model = SessionModel(jobs: jobs, approvals: nil)
    let h = makeVoiceHarness(jobs: jobs, language: .es, session: model)
    h.transcriber.stoppedText = "limpia el build"
    h.chat.rounds = [[.handoff(flights)], [.text("Resumen.")]]
    await h.session.hold()
    await pumpUntil("primera: escuchando") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("primera: el encargo arranco") { jobs.goals.count == 1 }
    h.synth.yield(.finished)
    await pumpUntil("primera: el turno acabo") { h.watch.latest.state == .idle }
    model.send(.job(.approvalRequested(sheetRequest("chat-app", tool: "app:slack_v2:slack_v2-send-message"))))
    jobs.ask(sheetRequest("job-1"))
    await pumpUntil("primera: la voz pregunta lo del encargo") {
        h.synth.queue.contains(Escalation.approvalAskedSpoken(.es))
    }
    h.synth.yield(.finished)
    await pumpUntilAsync("primera: queda anunciada") { await h.session.pendingApprovalSeen?.announcedAt != nil }
    await heldKey(h)
    await h.session.noteHeard("sí", pressed: await h.session.timeline.pressed)
    let answer = await h.session.answerPendingApproval(true)
    expectEq(answer, .resolved, "primera: la voz admite el si para el encargo")
    await settle(0.2)
    expectEq(model.projection.approvalQueue.map(\.requestId), ["chat-app", "job-1"],
             "primera: la hoja no muestra la del encargo, asi que el si no resuelve nada (20c D1)")
    expect(jobs.resolutions.isEmpty, "primera: ninguna peticion se resolvio por voz")
    expectEq(model.projection.approval?.requestId, "chat-app", "primera: la escritura app: sigue esperando el clic")
    jobs.open()
    await h.session.hangUp()
}

/// The island's chip, end to end: with the voice in front it never touches
/// the jobs; with the job card in front it stops that job by id.
@MainActor func testTheIslandsStopReachesTheRightBrake() async {
    let jobs = IDRecordingSubmitter()
    let vm = chat(jobs)
    vm.receive(.job(.started(goal: "uno"), from: JobID("a")))
    vm.receive(.job(.started(goal: "dos"), from: JobID("b")))
    vm.receive(.voice(TurnSnapshot(state: .speaking, pipeline: .realtime)))
    IslandStop.stop(vm)
    expectEq(vm.session.projection.job?.id, JobID("a"), "isla: los encargos siguen donde estaban")
    expectEq(vm.session.projection.queued.map(\.id), [JobID("b")], "isla: y el encolado tambien")

    vm.receive(.voice(TurnSnapshot(state: .idle, pipeline: .realtime)))
    IslandStop.stop(vm)
    // The second stop is the barrier: effects run in order.
    await pumpUntil("isla: la tarjeta del encargo para ese encargo") { jobs.byID == [JobID("a")] }
    expectEq(jobs.total, 0, "isla: el freno de la voz no usa el total, ni la tarjeta tampoco")
    expectEq(vm.session.projection.job?.id, JobID("b"), "isla: el otro sube a la fila")
}
