import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Aprobar por voz. La Wave 8 hizo que la voz PREGUNTARA el permiso; la
// decisión de producto de 2026-08-22 lo revierte: el encargo es UI asistiva y
// no habla por su cuenta. La solicitud vive en la hoja y nada más.
//
// Lo que sobrevive es la respuesta: `resolve_approval` sigue declarada, así
// que quien ve la hoja y dice "sí, autorízalo" resuelve sin tocar el trackpad.
// Lo que se pierde, y es el precio elegido: un permiso que nadie mira muere en
// el auto-deny de los 120 s sin que la voz lo mencione.

@Test @MainActor func voiceApprovalTests() async {
    testApprovalToolIsDeclared()
    await testApprovalNeverReachesTheEar()
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
    await pumpUntil("concede: vuelve a escuchar") {
        h.watch.latest.state == .listening
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
    await pumpUntil("roto: vuelve a escuchar") {
        h.watch.latest.state == .listening
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
