import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Aprobar por voz. La Wave 8 hizo que la voz PREGUNTARA el permiso; la
// decisión de producto de 2026-08-22 lo revierte: el encargo es UI asistiva y
// no habla por su cuenta. La solicitud vive en la hoja y nada más.
//
// `resolve_approval` sigue declarada, pero desde la review 16h-2 ronda 3 un
// "sí" hablado solo resuelve lo que la voz preguntó antes del hold (clásico);
// en realtime siempre pide el clic. Un permiso que nadie mira muere en el
// auto-deny (ApprovalTiming) sin que la voz lo mencione.

@Test @MainActor func voiceApprovalTests() async {
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
