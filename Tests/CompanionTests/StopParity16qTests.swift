import CompanionCore
import Foundation
import Testing

// 16q-1 (decision 2 of the Incredible audit): there is no single brake.
// The voice brake cuts the turn (voice, hold, the turn's own approvals) and
// leaves the background jobs alone; each job has its own stop; the total
// `.stop` (menu bar) stays a total. Everything goes through the reducer.

@Test @MainActor func stopParity16qTests() {
    testStopVoiceCutsTheVoiceAndLeavesTheJobs()
    testStopVoiceCutsTheHoldToo()
    testStopVoiceDeniesTheTurnsApprovalsButNotTheJobs()
    testStopVoiceKeepsQueuedJobsAlive()
    testStopVoiceAtRestIsANoOp()
    testStopVoiceWithNothingRunningEndsTheTurn()
    testTheTotalStopStillKillsEverything()
    testStopJobStopsOnlyThatJob()
    testStopJobOfAQueuedJobLeavesTheRunningOne()
    testStopJobDeniesOnlyItsOwnApprovals()
    testStopJobOfAnUnknownJobDoesNothing()
    testALateEventOfAStoppedJobNeverReopensARow()
    testASpokenYesResolvesExactlyTheRequestItNames()
    testASpokenAnswerForARequestNoLongerPendingResolvesNothing()
    testStopVoiceWithAnIdleChromeStillDeniesAnUnownedRequest()
    testTheTotalStopWithAnIdleChromeStillDeniesASheet()
    testStopVoiceWithNothingToCutReportsNoInterruption()
    testEveryRequestThatLeavesTheSheetIsReported()
    testDenyingAJobsFirstActionStopsOnlyThatJob()
}

private let alpha = JobID("alpha")
private let beta = JobID("beta")

private func request(_ id: String) -> ApprovalRequest {
    ApprovalRequest(requestId: id, toolName: "run_shell", summary: "ls", inputJSON: "{}")
}

private func thinking() -> SessionEvent {
    .voice(TurnSnapshot(state: .thinking, pipeline: .realtime))
}

private func running(_ m: inout SessionMachine, _ id: JobID, _ goal: String) {
    _ = m.handle(.job(.started(goal: goal), from: id))
}

private func has(_ effects: [SessionEffect], _ effect: SessionEffect) -> Bool {
    effects.contains(effect)
}

private func cancelsAJob(_ effects: [SessionEffect]) -> Bool {
    effects.contains {
        switch $0 {
        case .cancelJob, .cancelJobByID: true
        default: false
        }
    }
}

/// The orb's brake: the voice goes quiet, the job keeps its row.
@MainActor func testStopVoiceCutsTheVoiceAndLeavesTheJobs() {
    var m = SessionMachine()
    running(&m, alpha, "buscar vuelos")
    _ = m.handle(thinking())
    let fx = m.handle(.stopVoice)
    expect(has(fx, .cancelVoiceOutput), "stopVoice: corta la voz")
    expect(!cancelsAJob(fx), "stopVoice: no cancela ningun encargo")
    expectEq(m.projection.job?.id, alpha, "stopVoice: el encargo sigue en la proyeccion")
    expectEq(m.projection.kind, .processing(.subAgentRunning), "stopVoice: vuelve la fila del encargo")
    expectEq(m.projection.interruption, .userStopped, "stopVoice: queda el motivo")
}

@MainActor func testStopVoiceCutsTheHoldToo() {
    var m = SessionMachine()
    running(&m, alpha, "buscar vuelos")
    _ = m.handle(.pressed)
    let fx = m.handle(.stopVoice)
    expect(has(fx, .stopListening(commit: false)), "stopVoice: descarta el hold en curso")
    expect(!cancelsAJob(fx), "stopVoice: y el hold no mata al encargo")
    expect(!m.projection.holding, "stopVoice: la mano ya no cuenta")
}

/// Security property the audit asks to keep: the brake of the voice still
/// refuses what the voice turn was waiting on (MCP tool, parent gate). A
/// request that belongs to a job stays: it is the job's, and the job lives.
@MainActor func testStopVoiceDeniesTheTurnsApprovalsButNotTheJobs() {
    var m = SessionMachine()
    running(&m, alpha, "limpiar build")
    _ = m.handle(.job(.approvalRequested(request("job-1")), from: alpha))
    _ = m.handle(.job(.approvalRequested(request("mcp-1"))))
    _ = m.handle(thinking())
    let fx = m.handle(.stopVoice)
    expect(has(fx, .resolveApproval(requestId: "mcp-1", approved: false, remember: false)),
           "stopVoice: niega la peticion del turno de voz")
    expect(!has(fx, .resolveApproval(requestId: "job-1", approved: false, remember: false)),
           "stopVoice: la peticion del encargo NO se niega")
    expectEq(m.projection.approvalQueue.map(\.requestId), ["job-1"],
             "stopVoice: solo queda la del encargo en la hoja")
}

@MainActor func testStopVoiceKeepsQueuedJobsAlive() {
    var m = SessionMachine()
    running(&m, alpha, "uno")
    running(&m, beta, "dos")
    _ = m.handle(thinking())
    _ = m.handle(.stopVoice)
    expectEq(m.projection.queued.map(\.id), [beta], "stopVoice: el encolado sigue esperando")
    _ = m.handle(.job(.stepStarted(tool: "Bash", summary: "ls"), from: alpha))
    expectEq(m.projection.job?.steps.count, 1, "stopVoice: los pasos del encargo siguen entrando")
}

@MainActor func testStopVoiceAtRestIsANoOp() {
    var m = SessionMachine()
    let fx = m.handle(.stopVoice)
    expect(fx.isEmpty, "stopVoice en reposo: sin efectos")
    expectEq(m.projection, SessionProjection(), "stopVoice en reposo: sin cambios")
}

/// Nothing to protect: the brake ends the turn exactly as the total one did.
@MainActor func testStopVoiceWithNothingRunningEndsTheTurn() {
    var m = SessionMachine()
    _ = m.handle(.typedSubmitted)
    _ = m.handle(.stopVoice)
    expectEq(m.projection.kind, .idle, "stopVoice sin encargos: idle")
    _ = m.handle(.voice(TurnSnapshot(state: .listening, pipeline: .realtime)))
    _ = m.handle(.voice(TurnSnapshot(state: .speaking, pipeline: .realtime)))
    _ = m.handle(.voice(TurnSnapshot(state: .idle, pipeline: .realtime)))
    expectEq(m.projection.kind, .idle, "stopVoice sin encargos: el turno escrito no sobrevive")
}

/// Mutation guard: the menu bar's brake is still the whole one.
@MainActor func testTheTotalStopStillKillsEverything() {
    var m = SessionMachine()
    running(&m, alpha, "uno")
    running(&m, beta, "dos")
    let fx = m.handle(.stop)
    expect(has(fx, .cancelJob), "stop total: cancela")
    expect(m.projection.job == nil && m.projection.queued.isEmpty, "stop total: sin encargos")
}

/// The job card's own stop: only that job, by id, and the next one moves up.
@MainActor func testStopJobStopsOnlyThatJob() {
    var m = SessionMachine()
    running(&m, alpha, "uno")
    running(&m, beta, "dos")
    let fx = m.handle(.stopJob(alpha))
    expect(has(fx, .cancelJobByID(alpha)), "stopJob: cancela por id")
    expect(!has(fx, .cancelJob), "stopJob: no es el freno total")
    expectEq(m.projection.job?.id, beta, "stopJob: el siguiente sube a la fila")
    expect(m.projection.queued.isEmpty, "stopJob: la cola ya no lo tiene")
}

@MainActor func testStopJobOfAQueuedJobLeavesTheRunningOne() {
    var m = SessionMachine()
    running(&m, alpha, "uno")
    running(&m, beta, "dos")
    let fx = m.handle(.stopJob(beta))
    expect(has(fx, .cancelJobByID(beta)), "stopJob encolado: cancela el suyo")
    expectEq(m.projection.job?.id, alpha, "stopJob encolado: el que corre sigue")
    expect(m.projection.queued.isEmpty, "stopJob encolado: sale de la cola")
}

@MainActor func testStopJobDeniesOnlyItsOwnApprovals() {
    var m = SessionMachine()
    running(&m, alpha, "uno")
    running(&m, beta, "dos")
    _ = m.handle(.job(.approvalRequested(request("a1")), from: alpha))
    _ = m.handle(.job(.approvalRequested(request("b1")), from: beta))
    _ = m.handle(.job(.approvalRequested(request("g1"))))
    let fx = m.handle(.stopJob(alpha))
    expect(has(fx, .resolveApproval(requestId: "a1", approved: false, remember: false)),
           "stopJob: niega lo que pedia el encargo parado")
    expect(!has(fx, .resolveApproval(requestId: "b1", approved: false, remember: false)),
           "stopJob: no toca lo del otro encargo")
    expect(!has(fx, .resolveApproval(requestId: "g1", approved: false, remember: false)),
           "stopJob: ni lo que no es de ningun encargo")
    expectEq(m.projection.approvalQueue.map(\.requestId), ["b1", "g1"], "stopJob: la hoja conserva el resto")
}

@MainActor func testStopJobOfAnUnknownJobDoesNothing() {
    var m = SessionMachine()
    running(&m, alpha, "uno")
    let fx = m.handle(.stopJob(JobID("fantasma")))
    expect(fx.isEmpty, "stopJob desconocido: sin efectos")
    expectEq(m.projection.job?.id, alpha, "stopJob desconocido: el encargo sigue")
}

/// stopEpoch-equivalent in the reducer: what a stopped id says late is a
/// leftover, and never opens a row or reopens the sheet.
@MainActor func testALateEventOfAStoppedJobNeverReopensARow() {
    var m = SessionMachine()
    running(&m, alpha, "uno")
    running(&m, beta, "dos")
    _ = m.handle(.stopJob(alpha))
    _ = m.handle(.job(.stepStarted(tool: "Bash", summary: "tarde"), from: alpha))
    expectEq(m.projection.job?.id, beta, "tardio: la fila sigue siendo del otro")
    expectEq(m.projection.job?.steps.count, 0, "tardio: ningun paso ajeno en su tarjeta")
    let fx = m.handle(.job(.approvalRequested(request("a9")), from: alpha))
    expect(has(fx, .resolveApproval(requestId: "a9", approved: false, remember: false)),
           "tardio: su peticion muere")
    expect(m.projection.approvalQueue.isEmpty, "tardio: la hoja no se reabre")
}

// MARK: - The spoken answer names its request (found by the 16q-3 spec)

private func appWrite(_ id: String) -> ApprovalRequest {
    ApprovalRequest(
        requestId: id, toolName: "app:slack_v2:slack_v2-send-message",
        summary: "Send Message", inputJSON: "{}")
}

/// Once the voice asks a job's permission (16q-1), a spoken yes admitted for
/// THAT request must not land on whatever the sheet shows first: an app
/// write of the chat would be approved by a word said about something else
/// (F-D). The reducer resolves exactly the request the voice named, and
/// (20c D1) only while the sheet shows it: here neither resolves.
@MainActor func testASpokenYesResolvesExactlyTheRequestItNames() {
    var m = SessionMachine()
    _ = m.handle(.job(.approvalRequested(appWrite("chat-app"))))
    running(&m, alpha, "limpiar build")
    _ = m.handle(.job(.approvalRequested(request("job-1")), from: alpha))
    expectEq(m.projection.approval?.requestId, "chat-app", "previo: la del chat esta primera en la hoja")
    let fx = m.handle(.approvalSpoken(requestId: "job-1", approved: true))
    expect(!has(fx, .resolveApproval(requestId: "job-1", approved: true, remember: false)),
           "hablado: la que la voz nombro no esta en la hoja; espera su clic (20c D1)")
    expect(!has(fx, .resolveApproval(requestId: "chat-app", approved: true, remember: false)),
           "hablado: la escritura app: NO se aprueba")
    expectEq(m.projection.approvalQueue.map(\.requestId), ["chat-app", "job-1"],
             "hablado: la escritura app: sigue pendiente y pide el clic")
    _ = m.handle(.approvalAnswered(requestId: "chat-app", approved: false, remember: false))
    let shown = m.handle(.approvalSpoken(requestId: "job-1", approved: true))
    expect(has(shown, .resolveApproval(requestId: "job-1", approved: true, remember: false)),
           "hablado: ya en la hoja, resuelve la que la voz nombro")
}

@MainActor func testASpokenAnswerForARequestNoLongerPendingResolvesNothing() {
    var m = SessionMachine()
    _ = m.handle(.job(.approvalRequested(appWrite("chat-app"))))
    let fx = m.handle(.approvalSpoken(requestId: "job-1", approved: true))
    expect(fx.isEmpty, "hablado: una peticion que ya no esta no resuelve nada")
    expectEq(m.projection.approvalQueue.map(\.requestId), ["chat-app"], "hablado: la cola queda intacta")
}

// MARK: - Review round (security M1, M2; code M2, LOW)

private let bridgeGrant = ApprovalRequest(
    requestId: "b1", toolName: BridgePolicy.sessionApprovalTool,
    summary: "claude-code pide las manos", inputJSON: #"{"client":"claude-code"}"#)

/// A grant or an MCP request can sit on the sheet while the chrome rests:
/// the brake must still refuse it.
@MainActor func testStopVoiceWithAnIdleChromeStillDeniesAnUnownedRequest() {
    var m = SessionMachine()
    _ = m.handle(.job(.approvalRequested(bridgeGrant)))
    expectEq(m.projection.kind, .idle, "previo: la isla en reposo")
    let fx = m.handle(.stopVoice)
    expect(has(fx, .resolveApproval(requestId: "b1", approved: false, remember: false)),
           "stopVoice en reposo: niega la concesion sin dueno")
    expect(m.projection.approvalQueue.isEmpty, "stopVoice en reposo: la hoja se vacia")
}

@MainActor func testTheTotalStopWithAnIdleChromeStillDeniesASheet() {
    var m = SessionMachine()
    _ = m.handle(.job(.approvalRequested(bridgeGrant)))
    let fx = m.handle(.stop)
    expect(has(fx, .resolveApproval(requestId: "b1", approved: false, remember: false)),
           "stop total en reposo: tambien niega lo que espera la hoja")
}

/// The job row in front and no voice to cut: nothing was interrupted, and
/// the model must not be told the user cut anything.
@MainActor func testStopVoiceWithNothingToCutReportsNoInterruption() {
    var m = SessionMachine()
    running(&m, alpha, "uno")
    let fx = m.handle(.stopVoice)
    expect(!has(fx, .islandEvent(.interrupted)), "stopVoice sin voz: no hay interrupcion que contar")
    expect(!has(fx, .cancelVoiceOutput), "stopVoice sin voz: nada que cortar")
    expect(!cancelsAJob(fx), "stopVoice sin voz: y el encargo sigue")
}

/// The voice session mirrors what is on the sheet: every request that leaves
/// it, by any road, is reported so a stale one is never announced or answered.
@MainActor func testEveryRequestThatLeavesTheSheetIsReported() {
    func closed(_ fx: [SessionEffect]) -> [String] {
        fx.compactMap { if case .approvalClosed(let id) = $0 { id } else { nil } }
    }
    var click = SessionMachine()
    _ = click.handle(.job(.approvalRequested(request("c1"))))
    expectEq(closed(click.handle(.approvalAnswered(requestId: "c1", approved: true, remember: false))), ["c1"],
             "cierra: el clic")
    var settled = SessionMachine()
    _ = settled.handle(.job(.approvalRequested(request("s1"))))
    expectEq(closed(settled.handle(.approvalSettled(requestId: "s1"))), ["s1"], "cierra: resuelta en otro sitio")
    var dropped = SessionMachine()
    _ = dropped.handle(.job(.approvalRequested(request("d1"))))
    expectEq(closed(dropped.handle(.approvalDropped(requestId: "d1"))), ["d1"], "cierra: descartada")
    var job = SessionMachine()
    running(&job, alpha, "uno")
    _ = job.handle(.job(.approvalRequested(request("j1")), from: alpha))
    _ = job.handle(.job(.approvalRequested(request("g1"))))
    expectEq(closed(job.handle(.stopJob(alpha))), ["j1"], "cierra: el stop del encargo, solo lo suyo")
    var finished = SessionMachine()
    running(&finished, alpha, "uno")
    _ = finished.handle(.job(.approvalRequested(request("f1")), from: alpha))
    expectEq(closed(finished.handle(.jobFinished(ok: true, from: alpha))), ["f1"], "cierra: el fin del encargo")
    var total = SessionMachine()
    running(&total, alpha, "uno")
    _ = total.handle(.job(.approvalRequested(request("t1")), from: alpha))
    _ = total.handle(.job(.approvalRequested(request("t2"))))
    expectEq(closed(total.handle(.stop)), ["t1", "t2"], "cierra: el stop total")
    var spoken = SessionMachine()
    _ = spoken.handle(.job(.approvalRequested(request("v1"))))
    expectEq(closed(spoken.handle(.approvalSpoken(requestId: "v1", approved: false))), ["v1"],
             "cierra: el no hablado, una sola vez")
}

/// Incredible stops per task: refusing a job's first action stops THAT job,
/// not the line.
@MainActor func testDenyingAJobsFirstActionStopsOnlyThatJob() {
    var m = SessionMachine()
    running(&m, alpha, "uno")
    running(&m, beta, "dos")
    _ = m.handle(.job(.approvalRequested(request("a1")), from: alpha))
    let fx = m.handle(.approvalAnswered(requestId: "a1", approved: false, remember: false))
    expect(has(fx, .cancelJobByID(alpha)), "negar 1o: para ese encargo por id")
    expect(!has(fx, .cancelJob), "negar 1o: no es el freno total")
    expectEq(m.projection.job?.id, beta, "negar 1o: el encolado sube y sigue")
}
