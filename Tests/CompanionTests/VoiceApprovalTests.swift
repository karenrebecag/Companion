import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Aprobar por voz. El bug que esto repara: `ToolSpec.resolveApproval()` y
// `RealtimeCodec.approvalToolJSON()` existían, estaban probados, y sus únicos
// llamadores eran los tests — la sesión declaraba solo `delegate`. Con las
// manos ocupadas, un permiso del especialista moría en el auto-deny de 120 s
// sin que la voz dijera una palabra.

@Test @MainActor func voiceApprovalTests() async {
    testApprovalToolIsDeclared()
    testApprovalCopyIsForTheEar()
    await testApprovalAnnouncedWhenListening()
    await testVoiceGrantReachesTheJob()
    await testMalformedDecisionResolvesNothing()
    await testNoVoiceSessionMeansNoAnnouncement()
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

/// El copy es Core puro: se lee en voz alta, nunca vuelca el comando crudo.
@MainActor func testApprovalCopyIsForTheEar() {
    let request = ApprovalRequest(
        requestId: "r1", toolName: "bash",
        summary: "borrar la carpeta build",
        inputJSON: #"{"command":"rm -rf build"}"#)
    let ask = Escalation.approvalAnnouncement(request)
    expect(ask.contains("borrar la carpeta build"),
           "copy: la solicitud dice qué se pide")
    expect(!ask.contains("rm -rf"),
           "copy: el comando crudo no se lee en voz alta")
    expect(Escalation.approvalAck(approved: true)
        != Escalation.approvalAck(approved: false),
           "copy: conceder y denegar no suenan igual")

    let bare = ApprovalRequest(
        requestId: "r2", toolName: "write_file", summary: "", inputJSON: "{}")
    expect(Escalation.approvalAnnouncement(bare).contains("write_file"),
           "copy: sin resumen se nombra la herramienta, no queda en blanco")
}

/// 2. La solicitud espera turno como cualquier anuncio: nunca pisa al agente.
@MainActor func testApprovalAnnouncedWhenListening() async {
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

    // El acuse del delegate dejó la sesión pensando: el anuncio espera.
    try? await Task.sleep(for: .milliseconds(80))
    expect(!h.transport.sent.contains { $0.contains("borrar la carpeta build") },
           "permiso: el anuncio no se cuela mientras el agente tiene el turno")

    h.transport.yield(.responseDone)
    await pumpUntil("permiso: la voz lo pregunta al volver a escuchar") {
        h.transport.sent.contains {
            $0.contains("conversation.item.create")
                && $0.contains("borrar la carpeta build")
        }
    }
    let announcements = h.transport.sent.filter {
        $0.contains("borrar la carpeta build")
    }
    expectEq(announcements.count, 1, "permiso: se pregunta una sola vez")
}

/// 3. La respuesta del modelo llega al encargo vivo, con acuse para la voz.
@MainActor func testVoiceGrantReachesTheJob() async {
    let jobs = ApprovingSubmitter()
    let h = makeVoiceHarness(jobs: jobs)
    await h.session.start()
    await pumpUntil("concede: listening") { h.watch.latest.state == .listening }

    h.transport.yield(.functionCall(
        name: "delegate", arguments: #"{"goal":"limpiar build"}"#, callId: "c1"))
    await pumpUntil("concede: encargo aceptado") {
        h.transport.sent.contains { $0.contains("function_call_output") }
    }
    jobs.askApproval(ApprovalRequest(
        requestId: "r7", toolName: "bash", summary: "borrar build",
        inputJSON: "{}"))
    h.transport.yield(.responseDone)
    await pumpUntil("concede: la voz preguntó") {
        h.transport.sent.contains { $0.contains("borrar build") }
    }

    h.transport.yield(.functionCall(
        name: "resolve_approval", arguments: #"{"approved":true}"#,
        callId: "c2"))
    await pumpUntil("concede: el permiso llega al encargo") {
        jobs.resolutions.contains { $0 == ApprovalVerdict(id: "r7", approved: true) }
    }
    expect(h.transport.sent.contains {
        $0.contains("function_call_output") && $0.contains("c2")
    }, "concede: se acusa el tool call para que la voz siga")
}

/// 4. Un JSON roto no concede ni deniega: la solicitud sigue viva.
@MainActor func testMalformedDecisionResolvesNothing() async {
    let jobs = ApprovingSubmitter()
    let h = makeVoiceHarness(jobs: jobs)
    await h.session.start()
    await pumpUntil("roto: listening") { h.watch.latest.state == .listening }

    h.transport.yield(.functionCall(
        name: "delegate", arguments: #"{"goal":"algo"}"#, callId: "c1"))
    await pumpUntil("roto: encargo aceptado") {
        h.transport.sent.contains { $0.contains("function_call_output") }
    }
    jobs.askApproval(ApprovalRequest(
        requestId: "r9", toolName: "bash", summary: "algo delicado",
        inputJSON: "{}"))
    h.transport.yield(.responseDone)
    await pumpUntil("roto: la voz preguntó") {
        h.transport.sent.contains { $0.contains("algo delicado") }
    }

    // Truncado por el servidor, y el clásico "1" que NO es un booleano.
    h.transport.yield(.functionCall(
        name: "resolve_approval", arguments: #"{"approv"#, callId: "c2"))
    h.transport.yield(.functionCall(
        name: "resolve_approval", arguments: #"{"approved":1}"#, callId: "c3"))
    try? await Task.sleep(for: .milliseconds(80))
    expect(jobs.resolutions.isEmpty,
           "roto: un argumento que no es booleano no resuelve nada")

    // Y la solicitud sigue viva: la respuesta buena sí entra.
    h.transport.yield(.functionCall(
        name: "resolve_approval", arguments: #"{"approved":false}"#,
        callId: "c4"))
    await pumpUntil("roto: la negativa buena sí resuelve") {
        jobs.resolutions.contains { $0 == ApprovalVerdict(id: "r9", approved: false) }
    }
}

/// 5. Sin sesión de voz viva la conducta actual no cambia: solo el hilo.
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

    func askApproval(_ request: ApprovalRequest) {
        let sink = lock.withLock { self.sink }
        sink?.yield(.approvalRequested(request))
    }

    func submit(
        _ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        lock.withLock { sink = events }
        // Vive lo suficiente para que el permiso tenga a quién volver.
        try? await Task.sleep(for: .seconds(3))
        return JobResult(output: "hecho", isError: false)
    }

    func cancel() async {}

    func resolveApproval(requestId: String, approved: Bool) async {
        lock.withLock {
            verdicts.append(ApprovalVerdict(id: requestId, approved: approved))
        }
    }

    var isBusy: Bool { get async { true } }
}
