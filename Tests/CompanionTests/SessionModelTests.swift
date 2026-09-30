import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing

// Wave 12a. El único objeto que muta la proyección (SessionModel), los
// puertos que sus efectos alcanzan, y la costura con ChatViewModel y
// VoiceSession. La UI pinta; nunca escribe el kind (G2 como test de auditor).

@Test @MainActor func sessionModelTests() async {
    await pinLanguage {
        await testAnsweringResolvesThroughTheActor()
        await testAnsweringFallsBackToTheSubmitter()
        await testCompletedExpiresIntoIdle()
        await testAnEventBeforeExpiryCancelsTheTimer()
        testTransitionsAreLogged()
        await testChatViewModelProjectsTheJob()
        await testChatDenialOfTheFirstActionStopsThroughTheSession()
        await testVoiceSessionPublishesJobEvents()
        await testVoiceSessionPublishesTheParentsHands()
        testTheUIMustNotWriteTheKind()
        await testSwitchingConversationClosesTheTypedTurn()
        await testHoldEffectsReachTheVoicePort()
        await testTheProvisionalPressAndItsConfirmReachTheVoicePort()
        await testTheWarmSessionHangsUpThroughThePort()
        testOnKindChangeFiresOnlyWhenTheKindActuallyMoves()
    }
}

/// Wave 17: `BridgeHost` pauses the bridge for any turn of Karen's own and
/// resumes it at rest by observing `onKindChange` — it must fire exactly
/// once per real move and never on an event that leaves `kind` where it was.
@MainActor func testOnKindChangeFiresOnlyWhenTheKindActuallyMoves() {
    let session = SessionModel(jobs: nil, approvals: nil)
    var seen: [SessionKind] = []
    session.onKindChange = { seen.append($0) }
    session.send(.hoverEntered)
    expectEq(seen, [.hover], "onKindChange: idle -> hover avisa")
    session.send(.hoverEntered)
    expectEq(seen, [.hover], "onKindChange: sin cambio real, sin aviso otra vez")
    session.send(.hoverLeft)
    expectEq(seen, [.hover, .idle], "onKindChange: hover -> idle avisa")
}

/// 21 (12b). Los efectos del hold llegan al puerto de voz.
@MainActor func testHoldEffectsReachTheVoicePort() async {
    let voice = RecordingVoice()
    let session = SessionModel(jobs: nil, approvals: nil, voice: voice)
    session.send(.pressed)
    await pumpUntil("puerto: hold") { voice.calls.contains("hold") }
    session.send(.released)
    await pumpUntil("puerto: release") { voice.calls.contains("release") }
    session.send(.voice(TurnSnapshot(state: .speaking, pipeline: .realtime)))
    session.send(.stop)
    await pumpUntil("puerto: interrupt") { voice.calls.contains("interrupt") }
    session.send(.pressed)
    session.send(.tapped)
    await pumpUntil("puerto: un tap cierra sin enviar") { voice.calls.filter { $0 == "discard" }.count == 1 }
}

/// Code review 2026-09-24: FN's press reaches the port as provisional, and
/// the threshold's confirm as its own call — never as a plain `hold`.
@MainActor func testTheProvisionalPressAndItsConfirmReachTheVoicePort() async {
    let voice = RecordingVoice()
    let session = SessionModel(jobs: nil, approvals: nil, voice: voice)
    session.send(.pressedProvisionally)
    await pumpUntil("provisional: llega") { voice.calls.contains("holdProvisionally") }
    session.send(.holdConfirmed)
    await pumpUntil("provisional: el confirm llega") { voice.calls.contains("confirmHold") }
    expect(!voice.calls.contains("hold"), "provisional: nunca un hold completo")
}

/// 33b. Security review 2026-09-06 (alto): el plazo de la voz caliente
/// llega al puerto como `hangUp`, y un hold nuevo lo anula.
@MainActor func testTheWarmSessionHangsUpThroughThePort() async {
    let sleeper = ManualSleeper()
    let voice = RecordingVoice()
    let session = SessionModel(jobs: nil, approvals: nil, voice: voice, sleep: sleeper.sleep)
    let warm = TurnSnapshot(state: .listening, pipeline: .realtime, muted: true, holdArmed: true)
    session.send(.voice(warm))
    await pumpUntil("caliente: plazo armado") { sleeper.pending == 1 }
    // A new hold disarms it: firing the old timer hangs nothing up.
    session.send(.pressed)
    sleeper.fire()
    await settle(0.05)
    expectEq(voice.hungUp, 0, "caliente: el plazo anulado no colgó")
    // The turn ends resting warm again: pending's timer (disarmed),
    // Completed's, and the voice's own.
    session.send(.released)
    session.send(.voice(TurnSnapshot(state: .speaking, pipeline: .realtime, holdArmed: true)))
    session.send(.voice(warm))
    await pumpUntil("caliente: re-armado en completed") { sleeper.pending == 3 }
    sleeper.fire()
    await pumpUntil("caliente: cuelga") { voice.hungUp == 1 }
}

/// Code review 2026-09-06 (alto): cambiar de conversación con un turno
/// tecleado en vuelo no avisaba a la sesión; el chrome se quedaba en
/// «thinking» para la conversación siguiente.
@MainActor func testSwitchingConversationClosesTheTypedTurn() async {
    let vm = ChatViewModel(
        chat: HangingChat(), secrets: TestSecretStore([.openAI: "sk-test"]),
        store: MemoryConversationStore(), config: .default)
    vm.onAppear()
    await pumpUntil("cambio: sin onboarding") { !vm.needsOnboarding }
    vm.draft = "algo"
    vm.send()
    await pumpUntil("cambio: pensando") { vm.session.projection.kind == .processing(.thinking) }
    vm.newConversation()
    await pumpUntil("cambio: el turno se cierra") {
        vm.session.projection.kind != .processing(.thinking)
    }
    vm.session.send(.voice(TurnSnapshot(state: .idle)))
    expectEq(vm.session.projection.kind == .idle
             || vm.session.projection.kind == .processing(.completed), true,
             "cambio: reposo, no un turno fantasma")
}

/// Un reloj manual: `sleep` se queda parado hasta que el test lo suelta.
final class ManualSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var armedDelays: [TimeInterval] = []
    var pending: Int { lock.withLock { waiters.count } }

    /// How many waits of this length have registered. `SessionModel` starts its
    /// timers as tasks that hop off the main actor, so `send` returning does not
    /// mean the wait exists yet: `fire()` only wakes registered waiters, and a
    /// fire that runs first is lost for good. Wait on this before firing.
    func armed(_ seconds: TimeInterval) -> Int { lock.withLock { armedDelays.filter { $0 == seconds }.count } }

    func sleep(_ seconds: TimeInterval) async throws {
        await withCheckedContinuation { continuation in
            lock.withLock { armedDelays.append(seconds); waiters.append(continuation) }
        }
        try Task.checkCancellation()
    }

    func fire() {
        let all = lock.withLock { let w = waiters; waiters = []; return w }
        for waiter in all { waiter.resume() }
    }
}

private func request(_ id: String) -> ApprovalRequest {
    ApprovalRequest(requestId: id, toolName: "run_shell", summary: "ls", inputJSON: "{}")
}

/// 24a. La respuesta llega al actor con id, decisión y recordar.
@MainActor func testAnsweringResolvesThroughTheActor() async {
    let approvals = FakeApprovals()
    let session = SessionModel(jobs: nil, approvals: approvals)
    session.send(.job(.started(goal: "x")))
    session.send(.job(.approvalRequested(request("r1"))))
    session.send(.approvalAnswered(requestId: "r1", approved: true, remember: true))
    await pumpUntilAsync("actor: resuelto") { !(await approvals.resolutions).isEmpty }
    let first = await approvals.resolutions.first
    expectEq(first?.id, "r1", "actor: el id")
    expectEq(first?.approved, true, "actor: la decisión")
    expectEq(first?.remember, true, "actor: recordar")
    expect(session.projection.approval == nil, "actor: la cola se vació")
}

/// 24b. Sin actor, el submitter es el camino (cableado viejo, tests).
@MainActor func testAnsweringFallsBackToTheSubmitter() async {
    let submitter = WatchfulSubmitter()
    let session = SessionModel(jobs: submitter, approvals: nil)
    session.send(.job(.started(goal: "x")))
    session.send(.job(.approvalRequested(request("r1"))))
    session.send(.approvalAnswered(requestId: "r1", approved: true, remember: false))
    await pumpUntil("submitter: resuelto") { !submitter.remembered.isEmpty }
    expectEq(submitter.remembered, [false], "submitter: la respuesta llega")
    session.send(.stop)
    await pumpUntil("submitter: cancelado") { submitter.cancelled }
}

/// 25a. Completed → el reloj avanza → Idle.
@MainActor func testCompletedExpiresIntoIdle() async {
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep)
    session.send(.typedSubmitted)
    session.send(.typedReplyFinished)
    expectEq(session.projection.kind, .processing(.completed), "timer: completed")
    await pumpUntil("timer: armado") { sleeper.pending == 1 }
    sleeper.fire()
    await pumpUntil("timer: idle") { session.projection.kind == .idle }
}

/// 25b. Un evento antes de que venza lo anula: no hay un idle tardío que
/// pise al turno nuevo.
@MainActor func testAnEventBeforeExpiryCancelsTheTimer() async {
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep)
    session.send(.typedSubmitted)
    session.send(.typedReplyFinished)
    await pumpUntil("cancela: armado") { sleeper.pending == 1 }
    session.send(.typedSubmitted)
    sleeper.fire()
    await settle(0.05)
    expectEq(session.projection.kind, .processing(.thinking), "cancela: el turno nuevo manda")
}

/// 23 (modelo). Las transiciones salen por el log inyectado.
@MainActor func testTransitionsAreLogged() {
    let lines = TextBox()
    let session = SessionModel(jobs: nil, approvals: nil, log: { lines.append($0) })
    session.send(.voice(TurnSnapshot(state: .listening, pipeline: .realtime)))
    expectEq(lines.all, ["session: idle -> listening"], "log: una línea por transición")
}

/// 26. ChatViewModel ya no guarda el encargo: lo publica y lo lee de la
/// proyección. El registro del hilo sigue saliendo al terminar.
@MainActor func testChatViewModelProjectsTheJob() async {
    let vm = primed(chat: FakeChatProvider())
    let id = vm.startJob(goal: "buscar vuelos")
    vm.receiveJobEvent(.stepStarted(tool: "WebSearch", summary: "x"), from: id)
    expectEq(vm.session.projection.kind, .processing(.subAgentRunning), "chat: el kind sale de la sesión")
    expectEq(vm.job?.goal, "buscar vuelos", "chat: job es la proyección")
    expectEq(vm.session.projection.job?.steps.count, 1, "chat: los pasos también")
    vm.finishJob(ok: true, id: id)
    expect(vm.job == nil, "chat: el resultado cierra la tarjeta")
    expect(vm.messages.contains { $0.isStatus && $0.text.contains("buscar vuelos") },
           "chat: y deja el registro")
}

/// 16 (modelo). Negar el primer paso desde la hoja para el encargo a través
/// del reductor: el efecto llega al runner y el hilo lo dice.
@MainActor func testChatDenialOfTheFirstActionStopsThroughTheSession() async {
    let submitter = WatchfulSubmitter()
    let vm = ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
        store: MemoryConversationStore(), config: .default, jobSubmitter: submitter)
    vm.onAppear()
    Task {
        await vm.runJob(
            preface: "", handoff: Handoff(goal: "revisar el disco", context: ""),
            submitter: submitter)
    }
    await pumpUntil("niega: arranca") { vm.job != nil }
    vm.receiveJobEvent(.approvalRequested(request("a1")), from: vm.chatJobID)
    vm.answerApproval(false)
    await pumpUntil("niega: para") { submitter.cancelled }
    expectEq(vm.session.projection.kind, .idle, "niega: idle")
    expect(vm.messages.contains { $0.text == ChatCopy.jobStopped }, "niega: el hilo dice parado")
}

/// 27a. `VoiceSession.events`: lo que el especialista pide sale por el stream.
@MainActor func testVoiceSessionPublishesJobEvents() async {
    let jobs = ApprovingSubmitter()
    let h = makeVoiceHarness(jobs: jobs)
    let seen = SessionEventBox(h.session.events)
    await h.session.start()
    await pumpUntil("stream: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.functionCall(
        name: "delegate", arguments: #"{"goal":"limpiar build"}"#, callId: "c1"))
    await pumpUntil("stream: el encargo se anuncia") {
        seen.events.contains { if case .job(.started(let goal), _) = $0 { goal == "limpiar build" } else { false } }
    }
    jobs.askApproval(ApprovalRequest(requestId: "r7", toolName: "find_places", summary: "ls", inputJSON: "{}"))
    await pumpUntil("stream: la petición viaja") {
        seen.events.contains { if case .job(.approvalRequested(let r), _) = $0 { r.requestId == "r7" } else { false } }
    }
    // Review 16h-2 round 3 (HIGH): realtime has no hold to tie a yes to, so
    // the spoken one asks for the click and never reaches the reducer.
    await pumpUntilAsync("la sesión vio la hoja") { await h.session.pendingApproval != nil }
    h.clock.now += ApprovalClickGuard.dwell + 0.1
    h.transport.yield(.functionCall(
        name: "resolve_approval", arguments: #"{"approved":true}"#, callId: "c2"))
    await pumpUntil("stream: el sí hablado recibe su salida") {
        h.transport.sent.contains { $0.contains("function_call_output") && $0.contains("c2") }
    }
    expect(!seen.events.contains { if case .approvalSpoken = $0 { true } else { false } },
           "stream: en realtime el sí hablado no llega al reductor")
}

/// 27b. Las manos del padre en voz: `parentActing` / `parentActed` salen
/// por el mismo stream, con el objetivo.
@MainActor func testVoiceSessionPublishesTheParentsHands() async {
    let opener = FakeWorkspaceOpener()
    let h = makeVoiceHarness(parentTools: ParentToolRunner(workspace: opener))
    let seen = SessionEventBox(h.session.events)
    await h.session.start()
    await pumpUntil("manos: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.functionCall(
        name: "open_app", arguments: #"{"name":"Safari"}"#, callId: "c1"))
    await pumpUntil("manos: acting") {
        seen.events.contains { if case .parentActing(let t) = $0 { t == ["Safari"] } else { false } }
    }
    await pumpUntil("manos: acted") { seen.events.contains { $0 == .parentActed } }
}

/// 29. La regla de conformidad atrapa una vista que escribe el kind y deja
/// pasar la asignación de la proyección entera que hace el modelo.
@MainActor func testTheUIMustNotWriteTheKind() {
    guard let root = Conformance.repoRoot(),
          let contract = try? Conformance.contract(at: root),
          let rule = contract.rules["session-kind-write"] else {
        expect(false, "regla: session-kind-write existe en el contrato")
        return
    }
    let bad = [
        "session.projection.kind = .idle",
        "chat.session.projection.approvalQueue.append(request)",
        "projection.job = nil",
        "projection.cards.removeAll()",
    ]
    for line in bad {
        expectEq(Conformance.count(rule.pattern, in: [line]), 1, "regla: atrapa «\(line)»")
    }
    let fine = ["projection = machine.projection", "if projection.kind == .idle {"]
    for line in fine {
        expectEq(Conformance.count(rule.pattern, in: [line]), 0, "regla: deja pasar «\(line)»")
    }
}

final class SessionEventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [SessionEvent] = []
    var events: [SessionEvent] { lock.withLock { _events } }

    init(_ stream: AsyncStream<SessionEvent>) {
        Task { [weak self] in
            for await event in stream { self?.append(event) }
        }
    }

    private func append(_ event: SessionEvent) { lock.withLock { _events.append(event) } }
}

/// A provider whose stream never answers: the turn stays in flight until
/// the view model cancels it.
struct HangingChat: ChatProvider {
    func stream(_ history: [Turn], tools: [ToolSpec]) -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { continuation in
            let work = Task.detached {
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    continuation.finish(throwing: CancellationError())
                    return
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }
    func verify(_ key: String, provider: ProviderDescriptor) async throws {}
}
