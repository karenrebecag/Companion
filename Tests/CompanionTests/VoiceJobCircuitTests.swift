import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// El circuito de vuelta del encargo por voz. El bug que esto reemplaza: el
// resultado solo se pegaba al hilo visual y la voz seguía diciendo "voy en
// camino" después de que el encargo ya había muerto — estaba ciega.
//
// Decisión de producto (2026-08-22), a la manera de OpenAI: el resultado
// vuelve UNA vez. El texto del especialista es el mensaje del hilo — ahí
// viven el código, las rutas y las cards — y la voz solo acusa que terminó,
// sin releerlo. Dos mensajes por un resultado era la duplicación a matar.
// El fallo es la excepción: su motivo es una línea que cambia lo que haces
// después, y viaja.

@Test @MainActor func voiceJobCircuitTests() async {
    await testBridgeAnnouncesSuccess()
    await testTheArtifactStaysInTheThreadNotInTheVoice()
    await testBridgeHumanizesFailure()
    await testBridgeForwardsEvents()
    await testTheEndTravelsAfterTheLastStep()
    await testAnnouncementFlowsWhenListening()
    await testAnnouncementWaitsForListening()
}

@MainActor func testBridgeAnnouncesSuccess() async {
    let thread = ScriptedThread()
    let announced = TextBox()
    await VoiceJobBridge.run(
        Handoff(goal: "crear prueba1.md", context: ""),
        jobs: FixedSubmitter(result: JobResult(output: "# listo", isError: false)),
        thread: thread,
        announce: { announced.append($0.instruction) })

    expectEq(thread.turns.last?.content, "# listo",
             "circuito: el resultado aterriza en el hilo, íntegro")
    expect(announced.all.contains { $0.contains("crear prueba1.md") },
           "circuito: la voz se entera de que terminó, con el goal")
    expect(!announced.all.contains { $0.contains("listo") },
           "circuito: la voz NO relee el resultado; ya está en pantalla")
}

/// El caso que la regla protege: un encargo cuyo resultado es una card o un
/// bloque de código no se puede "resumir" a la voz sin perderlo. El mensaje
/// del hilo es el artefacto; la voz solo avisa.
@MainActor func testTheArtifactStaysInTheThreadNotInTheVoice() async {
    let thread = ScriptedThread()
    let announced = TextBox()
    let card = "```companion:locations\n[{\"name\":\"Cabo\"}]\n```"
    await VoiceJobBridge.run(
        Handoff(goal: "buscar hoteles", context: ""),
        jobs: FixedSubmitter(result: JobResult(output: card, isError: false)),
        thread: thread,
        announce: { announced.append($0.instruction) })

    expectEq(thread.turns.last?.content, card,
             "artefacto: la card llega entera al hilo")
    expect(!announced.all.contains { $0.contains("companion:locations") },
           "artefacto: la voz no intenta leer una card en voz alta")
}

@MainActor func testBridgeHumanizesFailure() async {
    let thread = ScriptedThread()
    let announced = TextBox()
    await VoiceJobBridge.run(
        Handoff(goal: "lo imposible", context: ""),
        jobs: FixedSubmitter(result: JobResult(output: "", isError: true)),
        thread: thread,
        announce: { announced.append($0.instruction) })

    let status = thread.status.joined(separator: " ")
    expect(status.contains("lo imposible"),
           "circuito: el fallo se narra con el goal, no con el error crudo")
    expect(!status.contains("Job failed"),
           "circuito: nada de errores internos en pantalla")
    expect(announced.all.contains { $0.contains("lo imposible") },
           "circuito: la voz se entera del fallo")
}

@MainActor func testBridgeForwardsEvents() async {
    let seen = EventTextBox()
    await VoiceJobBridge.run(
        Handoff(goal: "leer algo", context: ""),
        jobs: SteppingSubmitter(),
        thread: ScriptedThread(),
        onEvent: { seen.append($0) })

    expect(seen.all.contains {
        if case .job(.stepStarted, _) = $0 { return true }
        return false
    }, "circuito: los pasos del especialista llegan a quien pinta")
}

/// Review 16h-2 round 3 (SHOULD 2): the pump drains before the end goes
/// out. A step still in flight behind the end opened an orphan row.
@MainActor func testTheEndTravelsAfterTheLastStep() async {
    for jobs in [FixedSteppingSubmitter(throwing: false), FixedSteppingSubmitter(throwing: true)] {
        let seen = EventTextBox()
        await VoiceJobBridge.run(
            Handoff(goal: "leer algo", context: ""), jobs: jobs, thread: ScriptedThread(),
            onEvent: { event in
                // A slow reader of the step: the end must still wait for it.
                if case .job(.stepStarted, _) = event { Thread.sleep(forTimeInterval: 0.05) }
                seen.append(event)
            })
        let last = seen.all.last
        var isEnd = false
        if case .jobFinished = last { isEnd = true }
        expect(isEnd, "fin: el fin sale después del último paso (throwing=\(jobs.throwing), \(seen.all))")
    }
}

/// Encargo termina con la sesión escuchando: el anuncio sale de inmediato
/// como system item + response.create — la voz lo narra.
@MainActor func testAnnouncementFlowsWhenListening() async {
    let gated = GatedSubmitter()
    let h = makeVoiceHarness(jobs: gated)
    await h.session.start()
    await pumpUntil("announce: listening") { h.watch.latest.state == .listening }

    h.transport.yield(.functionCall(
        name: "delegate", arguments: #"{"goal":"crear archivo"}"#, callId: "c1"))
    await pumpUntil("announce: encargo aceptado") {
        h.transport.sent.contains { $0.contains("function_call_output") }
    }
    // El turno del acuse cierra y la sesión vuelve a escuchar.
    h.transport.yield(.responseDone)
    await pumpUntil("announce: de vuelta en listening") {
        h.watch.latest.state == .listening
    }

    let before = h.transport.sent.count
    gated.finish()
    await pumpUntil("announce: el sistema narra el cierre") {
        h.transport.sent.dropFirst(before).contains {
            $0.contains("conversation.item.create") && $0.contains("crear archivo")
        }
    }
    let added = Array(h.transport.sent.dropFirst(before))
    expect(hasMessage(added, type: "response.create"),
           "announce: response.create para que la voz lo diga")
}

/// Encargo termina con el agente hablando: el anuncio espera su turno y sale
/// al volver a listening — nunca se pisa la frase en curso.
@MainActor func testAnnouncementWaitsForListening() async {
    let gated = GatedSubmitter()
    let h = makeVoiceHarness(jobs: gated)
    await h.session.start()
    await pumpUntil("cola: listening") { h.watch.latest.state == .listening }

    h.transport.yield(.functionCall(
        name: "delegate", arguments: #"{"goal":"buscar vuelos"}"#, callId: "c2"))
    await pumpUntil("cola: encargo aceptado") {
        h.transport.sent.contains { $0.contains("function_call_output") }
    }
    h.transport.yield(.agentAudioStarted)
    await pumpUntil("cola: hablando") { h.watch.latest.state == .speaking }

    let before = h.transport.sent.count
    gated.finish()
    // Ventana corta: si el anuncio se colara aquí, pisaría la frase.
    try? await Task.sleep(for: .milliseconds(80))
    expect(!h.transport.sent.dropFirst(before).contains {
        $0.contains("conversation.item.create")
    }, "cola: el anuncio no interrumpe al agente")

    h.transport.yield(.agentAudioStopped)
    await pumpUntil("cola: el anuncio sale al escuchar de nuevo") {
        h.transport.sent.dropFirst(before).contains {
            $0.contains("conversation.item.create") && $0.contains("buscar vuelos")
        }
    }
}

// MARK: - Fakes

final class TextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var texts: [String] = []
    func append(_ text: String) { lock.withLock { texts.append(text) } }
    var all: [String] { lock.withLock { texts } }
}

final class EventTextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [SessionEvent] = []
    func append(_ event: SessionEvent) { lock.withLock { events.append(event) } }
    var all: [SessionEvent] { lock.withLock { events } }
}

struct FixedSubmitter: JobSubmitter {
    let result: JobResult
    func submit(
        _ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult { result }
    func cancel() async {}
    func cancel(job id: JobID) async { await cancel() }
    func submit(
        _ handoff: Handoff, as id: JobID, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try await submit(handoff, events: events)
    }
    func resolveApproval(requestId: String, approved: Bool) async {}
    var isBusy: Bool { get async { false } }
}

struct SteppingSubmitter: JobSubmitter {
    func submit(
        _ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        events.yield(.stepStarted(tool: "read_file", summary: "leyendo"))
        events.yield(.stepFinished(tool: "read_file", ok: true))
        // El puente drena en paralelo; un respiro para que le lleguen.
        try? await Task.sleep(for: .milliseconds(10))
        return JobResult(output: "ok", isError: false)
    }
    func cancel() async {}
    func cancel(job id: JobID) async { await cancel() }
    func submit(
        _ handoff: Handoff, as id: JobID, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try await submit(handoff, events: events)
    }
    func resolveApproval(requestId: String, approved: Bool) async {}
    var isBusy: Bool { get async { false } }
}

/// One step and an immediate end, or an immediate throw.
struct FixedSteppingSubmitter: JobSubmitter {
    let throwing: Bool
    func submit(
        _ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        events.yield(.stepStarted(tool: "read_file", summary: "leyendo"))
        if throwing { throw ChatError.unreachable }
        return JobResult(output: "ok", isError: false)
    }
    func cancel() async {}
    func cancel(job id: JobID) async { await cancel() }
    func submit(
        _ handoff: Handoff, as id: JobID, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try await submit(handoff, events: events)
    }
    func resolveApproval(requestId: String, approved: Bool) async {}
    var isBusy: Bool { get async { false } }
}

/// El encargo no termina hasta que el test lo suelta.
final class GatedSubmitter: JobSubmitter, @unchecked Sendable {
    private let lock = NSLock()
    private var released = false
    private var waiter: CheckedContinuation<Void, Never>?

    func finish() {
        let pending = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            released = true
            defer { waiter = nil }
            return waiter
        }
        pending?.resume()
    }

    func submit(
        _ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        await withCheckedContinuation { cont in
            let done = lock.withLock { () -> Bool in
                if released { return true }
                waiter = cont
                return false
            }
            if done { cont.resume() }
        }
        return JobResult(output: "hecho", isError: false)
    }
    func cancel() async {}
    func cancel(job id: JobID) async { await cancel() }
    func submit(
        _ handoff: Handoff, as id: JobID, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try await submit(handoff, events: events)
    }
    func resolveApproval(requestId: String, approved: Bool) async {}
    var isBusy: Bool { get async { false } }
}
