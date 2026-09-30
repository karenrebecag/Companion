import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing

// Aprobar por voz. La Wave 8 hizo que la voz PREGUNTARA el permiso; la
// decisión de producto de 2026-08-22 lo revierte: el encargo es UI asistiva y
// no habla por su cuenta. La solicitud vive en la hoja y nada más.
//
// `resolve_approval` sigue declarada, pero desde la review 16h-2 ronda 3 un
// "sí" hablado solo resuelve lo que la voz preguntó antes del hold (clásico);
// en realtime siempre pide el clic. Un permiso que nadie mira muere en el
// auto-deny (ApprovalTiming) sin que la voz lo mencione.

@Test @MainActor func voiceApprovalTests() async {
    testApprovalToolIsDeclared()
    await testApprovalNeverReachesTheEar()
    await testARealtimeYesNeverReachesTheJob()
    await testMalformedDecisionResolvesNothing()
    await testNoVoiceSessionMeansNoAnnouncement()
    await testSpokenYesNeverApprovesAnAppWrite()
    await testASpokenNoRefusesAnAppWrite()
}

/// Negar es la dirección segura: un "no" hablado a un write de app se
/// resuelve sin clic; solo el sí lo necesita.
@MainActor func testASpokenNoRefusesAnAppWrite() async {
    let h = makeVoiceHarness(jobs: ApprovingSubmitter())
    await h.session.noteApproval(ApprovalRequest(
        requestId: "r8", toolName: "app:slack_v2:slack_v2-send-message",
        summary: "Send Message · Slack", inputJSON: "{}"))
    let answer = await h.session.answerPendingApproval(false)
    expectEq(answer, .resolved, "app write: el no hablado lo niega sin pedir clic")
    expect(await h.session.pendingApproval == nil, "app write: y deja de estar pendiente")
}

/// 6 (F-D, security review 16k-3): `resolve_approval` la llama el MODELO, y
/// una lectura de Slack puede plantarle palabras. Un write de app pendiente
/// solo se aprueba con el click de la hoja, jamás por esta vía.
@MainActor func testSpokenYesNeverApprovesAnAppWrite() async {
    let jobs = ApprovingSubmitter()
    let h = makeVoiceHarness(jobs: jobs)
    await h.session.noteApproval(ApprovalRequest(
        requestId: "r7", toolName: "app:slack_v2:slack_v2-send-message",
        summary: "Send Message · Slack", inputJSON: "{}"))
    let resolved = await h.session.answerPendingApproval(true)
    expectEq(resolved, .needsClick, "app write: el si hablado no lo resuelve; pide el clic")
}

/// 1. Sin la tool declarada el modelo no puede contestar aunque quiera.
@MainActor func testApprovalToolIsDeclared() {
    let runtime = RealtimeRuntime(
        transport: ScriptedVoiceTransport(), player: ScriptedPlayer(),
        thread: ScriptedThread())
    let config = Config(ownerFirstName: "Karen")

    runtime.prepareSessionUpdate(config: config, history: [], canDelegate: true)
    let withJobs = runtime.pendingUpdate ?? ""
    expect(withJobs.contains("\"delegate\""),
           "tools: delegate sigue declarada")
    expect(withJobs.contains("\"resolve_approval\""),
           "tools: resolve_approval viaja en el session.update")

    runtime.reset()
    runtime.prepareSessionUpdate(config: config, history: [], canDelegate: false)
    let without = runtime.pendingUpdate ?? ""
    expect(!without.contains("resolve_approval"),
           "tools: sin especialista no se ofrece resolver permisos")
}

/// 2. La solicitud no suena. El encargo no interrumpe: la hoja la muestra y
/// ahí se queda.
@MainActor func testApprovalNeverReachesTheEar() async {
    let jobs = ApprovingSubmitter()
    let h = makeVoiceHarness(jobs: jobs)
    await h.session.start()
    await pumpUntil("permiso: listening") { h.watch.latest.state == .listening }

    h.transport.yield(.functionCall(
        name: "delegate", arguments: #"{"goal":"limpiar build"}"#, callId: "c1"))
    await pumpUntil("permiso: encargo aceptado") {
        h.transport.sent.contains { $0.contains("function_call_output") }
    }
    jobs.askApproval(ApprovalRequest(
        requestId: "r1", toolName: "bash", summary: "borrar la carpeta build",
        inputJSON: #"{"command":"rm -rf build"}"#))

    // Vuelve a escuchar: el momento en el que ANTES salía el anuncio.
    h.transport.yield(.responseDone)
    await pumpUntil("permiso: la sesión vuelve a escuchar") {
        h.watch.latest.state == .listening
    }
    try? await Task.sleep(for: .milliseconds(80))
    expect(!h.transport.sent.contains { $0.contains("borrar la carpeta build") },
           "permiso: no se pregunta en voz alta; la hoja es el único canal")
}

/// 3. Review 16h-2 round 3 (HIGH): en realtime no hay hold al que atar un
/// sí, y `resolve_approval` lo llama el MODELO. El sí hablado no llega al
/// encargo; la salida del tool pide el clic de la hoja.
@MainActor func testARealtimeYesNeverReachesTheJob() async {
    let jobs = ApprovingSubmitter()
    let sessionModel = SessionModel(jobs: jobs, approvals: nil)
    let h = makeVoiceHarness(jobs: jobs, session: sessionModel)
    await h.session.start()
    await pumpUntil("concede: listening") { h.watch.latest.state == .listening }

    h.transport.yield(.functionCall(
        name: "delegate", arguments: #"{"goal":"limpiar build"}"#, callId: "c1"))
    await pumpUntil("concede: encargo aceptado") {
        h.transport.sent.contains { $0.contains("function_call_output") }
    }
    jobs.askApproval(ApprovalRequest(
        requestId: "r7", toolName: "find_places", summary: "cines cerca",
        inputJSON: "{}"))
    h.transport.yield(.responseDone)
    await pumpUntil("concede: la hoja tiene la petición") {
        sessionModel.projection.approval?.requestId == "r7"
    }
    await pumpUntilAsync("la sesión vio la hoja") { await h.session.pendingApproval != nil }
    h.clock.now += ApprovalClickGuard.dwell + 0.1
    h.transport.yield(.functionCall(
        name: "resolve_approval", arguments: #"{"approved":true}"#,
        callId: "c2"))
    await pumpUntil("concede: se acusa el tool call") {
        h.transport.sent.contains { $0.contains("function_call_output") && $0.contains("c2") }
    }
    let output = h.transport.sent.last { $0.contains("c2") } ?? ""
    expect(output.contains("clic") || output.contains("click"),
           "realtime: la salida pide el clic (\(output))")
    expect(jobs.resolutions.isEmpty, "realtime: el sí hablado no llega al encargo")
    expectEq(sessionModel.projection.approval?.requestId, "r7", "realtime: la hoja sigue esperando")
}

/// 4. Un JSON roto no concede ni deniega: la solicitud sigue viva.
@MainActor func testMalformedDecisionResolvesNothing() async {
    let jobs = ApprovingSubmitter()
    let sessionModel = SessionModel(jobs: jobs, approvals: nil)
    let h = makeVoiceHarness(jobs: jobs, session: sessionModel)
    await h.session.start()
    await pumpUntil("roto: listening") { h.watch.latest.state == .listening }

    h.transport.yield(.functionCall(
        name: "delegate", arguments: #"{"goal":"algo"}"#, callId: "c1"))
    await pumpUntil("roto: encargo aceptado") {
        h.transport.sent.contains { $0.contains("function_call_output") }
    }
    jobs.askApproval(ApprovalRequest(
        requestId: "r9", toolName: "find_places", summary: "algo delicado",
        inputJSON: "{}"))
    h.transport.yield(.responseDone)
    await pumpUntil("roto: vuelve a escuchar") {
        h.watch.latest.state == .listening
    }
    await pumpUntil("roto: la hoja tiene la petición") {
        sessionModel.projection.approval?.requestId == "r9"
    }

    // 16h-2 (security M1): a spoken yes reaches only a sheet that has been
    // on screen for the click guard's dwell; the test clock has to get there.
    await pumpUntilAsync("la sesión vio la hoja") { await h.session.pendingApproval != nil }
    h.clock.now += ApprovalClickGuard.dwell + 0.1
    // Truncado por el servidor, y el clásico "1" que NO es un booleano.
    h.transport.yield(.functionCall(
        name: "resolve_approval", arguments: #"{"approv"#, callId: "c2"))
    h.transport.yield(.functionCall(
        name: "resolve_approval", arguments: #"{"approved":1}"#, callId: "c3"))
    try? await Task.sleep(for: .milliseconds(80))
    expect(jobs.resolutions.isEmpty,
           "roto: un argumento que no es booleano no resuelve nada")

    // Y la solicitud sigue viva: la negativa buena sí entra. Negar es la
    // dirección segura; solo el sí hablado necesita el clic.
    h.transport.yield(.functionCall(
        name: "resolve_approval", arguments: #"{"approved":false}"#,
        callId: "c4"))
    await pumpUntil("roto: la negativa buena sí resuelve") {
        jobs.resolutions.contains { $0 == ApprovalVerdict(id: "r9", approved: false) }
    }
}

/// 5. Sin sesión de voz viva tampoco cambia nada: solo el hilo.
@MainActor func testNoVoiceSessionMeansNoAnnouncement() async {
    let jobs = ApprovingSubmitter()
    let h = makeVoiceHarness(jobs: jobs)
    // Sin start(): la sesión está en idle, no hay a quién hablarle.
    await h.session.noteApproval(ApprovalRequest(
        requestId: "r1", toolName: "bash", summary: "borrar algo",
        inputJSON: "{}"))
    try? await Task.sleep(for: .milliseconds(50))
    expect(h.transport.sent.isEmpty,
           "sin voz: nada se manda al servidor, el sheet ya lo muestra")
}

// MARK: - Fakes

struct ApprovalVerdict: Equatable, Sendable {
    let id: String
    let approved: Bool
}

/// Encargo que pide permiso a mitad y no termina hasta que lo resuelven.
final class ApprovingSubmitter: JobSubmitter, @unchecked Sendable {
    private let lock = NSLock()
    private var sink: AsyncStream<JobEvent>.Continuation?
    private var verdicts: [ApprovalVerdict] = []

    var resolutions: [ApprovalVerdict] { lock.withLock { verdicts } }

    /// A request asked before `submit` ran is held, not lost: the bridge
    /// starts the job on its own task, so the test can get there first.
    private var early: [ApprovalRequest] = []

    func askApproval(_ request: ApprovalRequest) {
        let sink = lock.withLock { () -> AsyncStream<JobEvent>.Continuation? in
            if self.sink == nil { early.append(request) }
            return self.sink
        }
        sink?.yield(.approvalRequested(request))
    }

    func submit(
        _ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        let held = lock.withLock { () -> [ApprovalRequest] in
            sink = events
            defer { early = [] }
            return early
        }
        for request in held { events.yield(.approvalRequested(request)) }
        // Vive lo suficiente para que el permiso tenga a quién volver.
        try? await Task.sleep(for: .seconds(3))
        return JobResult(output: "hecho", isError: false)
    }

    func cancel() async {}

    func cancel(job id: JobID) async { await cancel() }
    func submit(
        _ handoff: Handoff, as id: JobID, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try await submit(handoff, events: events)
    }
    func resolveApproval(requestId: String, approved: Bool) async {
        lock.withLock {
            verdicts.append(ApprovalVerdict(id: requestId, approved: approved))
        }
    }

    /// Era `true` fijo, de cuando nadie leia esto. Desde Wave 9g-3 el puente
    /// SI lo lee para no arrancar un segundo encargo, asi que un fake que se
    /// declara ocupado desde el principio impide que arranque el primero.
    var isBusy: Bool {
        get async { lock.withLock { sink != nil } }
    }
}
