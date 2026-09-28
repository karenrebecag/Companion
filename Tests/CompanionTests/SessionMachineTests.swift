import CompanionCore
import Foundation
import Testing

// Wave 12a. El reductor de sesión: cuatro kinds, seis fases, una proyección.
// La máquina de voz (TurnMachine) sigue mandando en la captura; ésta la
// observa y decide el chrome. Cancelar y fallar vuelven a Idle con un motivo,
// nunca con un quinto kind (relay-hud-spec/00 G2, G4).

@Test @MainActor func sessionMachineTests() {
    testStartsIdle()
    testConnectingKeepsTheKind()
    testListeningFollowsTheVoice()
    testThinkingAndSpeakingAreProcessing()
    testAJobOutranksThinking()
    testAPermissionFailureIsACardNotAKind()
    testNotHeardIsACouldntHearCard()
    testVoiceIdleKeepsARunningJob()
    testTypedTurnEndsInCompletedThenIdle()
    testTypedTurnWithLiveVoiceReturnsToTheVoice()
    testParentActingIsToolExecuting()
    testJobStartedIsSubAgentRunning()
    testStepsAccumulateOnTheTimeline()
    testApprovalRequestedStaysProcessing()
    testTwoRequestsAnswerInOrder()
    testDenyingTheFirstActionStopsTheJob()
    testACardInIdleStaysIdle()
    testJobFinishedRestsOnTheVoice()
    testStopReturnsToIdleAndKillsTheChildren()
    testStopInIdleIsANoOp()
    testHoverOnlyFromIdle()
    testCardsAreTransient()
    testEveryKindChangeIsLogged()
    testSettledRequestsLeaveTheQueue()
    testAParentsApprovalDoesNotCountForTheJob()
    testTheSpokenAnswerGoesToTheSheetsFirst()
    testALateRequestAfterStopIsDenied()
    testBridgeAskReachesTheSheetAtRest()
    testStopClosesTheTypedTurn()
    testRenamingARunningJobKeepsItsApprovals()
    testPressedStartsListening()
    testClassicArmWhileHoldingKeepsListening()
    testPressedWhileSpeakingIsBargeIn()
    testReleasedIsPending()
    testTappedIsAHintNotATurn()
    testMutedListeningIsRest()
    testAHeldTurnRunsToIdle()
    testNothingHeardAfterAHold()
    testStopCutsTheVoice()
    testAWarmHoldSessionIdlesOut()
    testThePartialIsAFieldNotAKind()
    testDictationIsAForkNotAKind()
    testOnlyListeningAndProcessingAreTheUsersTurn()
}

/// Wave 17 review finding: `BridgeHost` paused the bridge on ANY non-idle
/// kind, including `.hover` (the pointer resting on the island) — a mouse
/// pass would pause a session nobody asked to pause. Spec §3 says the voice
/// wins "al empezar un hold o enviar un chat": only `.listening` and
/// `.processing` are Karen's own turn.
@MainActor func testOnlyListeningAndProcessingAreTheUsersTurn() {
    expect(!SessionKind.idle.isUsersTurn, "turno: reposo no es turno")
    expect(!SessionKind.hover.isUsersTurn, "turno: el puntero encima no es turno")
    expect(SessionKind.listening.isUsersTurn, "turno: escuchar sí es turno")
    for phase: SessionPhase in [.pending, .thinking, .speaking, .toolExecuting, .subAgentRunning, .completed] {
        expect(SessionKind.processing(phase).isUsersTurn, "turno: procesando (\(phase)) sí es turno")
    }
}

// MARK: - Wave 12b: mantener y soltar

/// 2. Pulsar desde reposo: Listening, holding, y la voz abre el micro.
@MainActor func testPressedStartsListening() {
    var m = SessionMachine()
    _ = m.handle(.hoverEntered)
    let fx = m.handle(.pressed)
    expectEq(m.projection.kind, .listening, "pulsar: listening")
    expect(m.projection.holding, "pulsar: holding")
    expectEq(kinds(fx), [.startListening], "pulsar: la voz abre el micro")
    let again = m.handle(.pressed)
    expectEq(kinds(again), [.startListening], "pulsar: repetir es idempotente")
}

/// 14b: el hold de texto arma el oído con la voz aún idle. Ese snapshot
/// no puede tumbar el chrome: si lo hace, FN sigue abajo y `.released` se ignora.
@MainActor func testClassicArmWhileHoldingKeepsListening() {
    var m = SessionMachine()
    _ = m.handle(.pressed)
    _ = m.handle(voice(.idle, pipeline: .classic))
    expectEq(m.projection.kind, .listening, "armar: el chrome sigue listening")
    expect(m.projection.holding, "armar: FN sigue abajo")
    let fx = m.handle(.released)
    expectEq(m.projection.kind, .processing(.pending), "armar: soltar sí commitea")
    expectEq(kinds(fx), [
        .stopListening(commit: true),
        .schedulePendingExpiry(SessionMachine.pendingTimeout)
    ], "armar: ForceEndpoint")
}

/// 3. Pulsar mientras habla: barge-in. La voz corta y abre el micro.
@MainActor func testPressedWhileSpeakingIsBargeIn() {
    var m = SessionMachine()
    _ = m.handle(voice(.listening))
    _ = m.handle(voice(.speaking))
    let fx = m.handle(.pressed)
    expectEq(m.projection.kind, .listening, "barge-in: listening")
    expectEq(kinds(fx), [.startListening], "barge-in: la voz sabe cortar sola al abrir")
}

/// 4 y 5. Soltar con hold: Pending y ForceEndpoint. Sin hold: nada.
@MainActor func testReleasedIsPending() {
    var m = SessionMachine()
    _ = m.handle(.pressed)
    let fx = m.handle(.released)
    expectEq(m.projection.kind, .processing(.pending), "soltar: pending")
    expect(!m.projection.holding, "soltar: ya no holding")
    expectEq(kinds(fx), [.stopListening(commit: true), .schedulePendingExpiry(SessionMachine.pendingTimeout)],
             "soltar: cierra el micro y envía; y arma el plazo")
    var idle = SessionMachine()
    let none = idle.handle(.released)
    expect(none.isEmpty, "soltar sin hold: nada")
}

/// 6. Un tap no es un turno: cierra el micro sin enviar y enseña el hold.
@MainActor func testTappedIsAHintNotATurn() {
    var m = SessionMachine()
    _ = m.handle(.pressed)
    let fx = m.handle(.tapped)
    expectEq(m.projection.kind, .idle, "tap: vuelve al reposo")
    expectEq(m.projection.notice, .holdHint, "tap: la pista se queda")
    expectEq(kinds(fx), [.stopListening(commit: false), .scheduleNoticeExpiry(SessionMachine.noticeDelay)],
             "tap: cierra sin enviar; la pista se irá sola")
    _ = m.handle(voice(.listening, muted: true))
    expectEq(m.projection.notice, .holdHint, "tap: la voz cerrando el micro no borra la pista")
    _ = m.handle(.pressed)
    expect(m.projection.notice == nil, "tap: pulsar de verdad la borra")
}

/// 7, 8, 9. La voz caliente con el micro cerrado es reposo, salvo en Pending.
@MainActor func testMutedListeningIsRest() {
    var m = SessionMachine()
    _ = m.handle(voice(.listening, muted: true))
    expectEq(m.projection.kind, .idle, "muted: desde idle sigue idle")
    expectEq(m.projection.voice, .muted, "muted: la voz lo dice")

    var spoke = SessionMachine()
    _ = spoke.handle(voice(.listening))
    _ = spoke.handle(voice(.speaking))
    let fx = spoke.handle(voice(.listening, muted: true))
    expectEq(spoke.projection.kind, .processing(.completed), "muted: tras hablar, completed")
    expect(fx.contains(.scheduleCompletedExpiry(SessionMachine.completedDelay)), "muted: con timer")

    var pending = SessionMachine()
    _ = pending.handle(.pressed)
    _ = pending.handle(.released)
    _ = pending.handle(voice(.listening, muted: true))
    expectEq(pending.projection.kind, .processing(.pending), "muted: en pending espera el texto")

    var live = SessionMachine()
    _ = live.handle(voice(.listening))
    expectEq(live.projection.kind, .listening, "vivo: con el micro abierto sí es listening")
}

/// 10 y 11. Un hold completo: pending → thinking → speaking → completed →
/// idle. Y el plazo de pending que vence vuelve al reposo.
@MainActor func testAHeldTurnRunsToIdle() {
    var m = SessionMachine()
    _ = m.handle(.pressed)
    _ = m.handle(voice(.connecting))
    expectEq(m.projection.kind, .listening, "hold: conectando sigue listening")
    _ = m.handle(voice(.listening))
    _ = m.handle(.released)
    _ = m.handle(voice(.listening, muted: true))
    _ = m.handle(voice(.thinking, muted: true))
    expectEq(m.projection.kind, .processing(.thinking), "hold: thinking")
    _ = m.handle(voice(.speaking, muted: true))
    expectEq(m.projection.kind, .processing(.speaking), "hold: speaking")
    _ = m.handle(voice(.listening, muted: true))
    expectEq(m.projection.kind, .processing(.completed), "hold: completed")
    _ = m.handle(.completedTimerExpired)
    expectEq(m.projection.kind, .idle, "hold: idle")

    var stuck = SessionMachine()
    _ = stuck.handle(.pressed)
    _ = stuck.handle(.released)
    _ = stuck.handle(.pendingTimedOut)
    expectEq(stuck.projection.kind, .idle, "hold: un pending sin respuesta no se queda para siempre")
    _ = stuck.handle(.pressed)
    _ = stuck.handle(.pendingTimedOut)
    expectEq(stuck.projection.kind, .listening, "hold: el plazo tardío no toca otro estado")
}

/// 11. Soltar sin haber dicho nada: «no te oí», reposo.
@MainActor func testNothingHeardAfterAHold() {
    var m = SessionMachine()
    _ = m.handle(.pressed)
    _ = m.handle(.released)
    _ = m.handle(.heardNothing)
    expectEq(m.projection.kind, .idle, "nada: idle")
    expectEq(m.projection.notice, .couldntHear, "nada: la card")
    expectEq(m.projection.cards, [.couldntHear], "nada: y en este paso")
}

/// 12. Stop mientras la voz piensa o habla la corta; y suelta el hold.
@MainActor func testStopCutsTheVoice() {
    var m = SessionMachine()
    _ = m.handle(voice(.listening))
    _ = m.handle(voice(.speaking))
    let fx = m.handle(.stop)
    expectEq(m.projection.kind, .idle, "stop: idle")
    expect(fx.contains(.cancelVoiceOutput), "stop: corta la voz")
    var held = SessionMachine()
    _ = held.handle(.pressed)
    let released = held.handle(.stop)
    expect(!held.projection.holding, "stop: suelta el hold")
    expect(released.contains(.stopListening(commit: false)), "stop: cierra el micro sin enviar")
}

private func parentRequest(_ id: String) -> ApprovalRequest {
    ApprovalRequest(requestId: id, toolName: "open_url", summary: "", inputJSON: #"{"url":"https://evil.example"}"#)
}

/// Security review 2026-09-06 (crítico): una petición del padre (`open_url`)
/// contestada mientras corre un encargo no es "la primera acción del
/// encargo". Ni aprobarla desarma la regla, ni negarla para el encargo.
@MainActor func testAParentsApprovalDoesNotCountForTheJob() {
    var m = SessionMachine()
    _ = m.handle(.job(.started(goal: "limpiar Descargas")))
    _ = m.handle(.job(.approvalRequested(parentRequest("p1"))))
    _ = m.handle(.approvalAnswered(requestId: "p1", approved: true, remember: false))
    _ = m.handle(.job(.approvalRequested(request("a1"))))
    let fx = m.handle(.approvalAnswered(requestId: "a1", approved: false, remember: false))
    expect(fx.contains(.cancelJob), "padre: aprobar open_url no desarma «negar el primer paso»")

    var other = SessionMachine()
    _ = other.handle(.job(.started(goal: "x")))
    _ = other.handle(.job(.approvalRequested(parentRequest("p2"))))
    let denied = other.handle(.approvalAnswered(requestId: "p2", approved: false, remember: false))
    expect(!denied.contains(.cancelJob), "padre: negar open_url no para el encargo")
    expect(other.projection.job != nil, "padre: el encargo sigue")
}

/// Security review 2026-09-06 (crítico): el "sí" hablado contesta lo que la
/// hoja muestra (la primera de la cola), por el mismo camino que la hoja, con
/// las mismas reglas. Sin nada pendiente no resuelve nada.
@MainActor func testTheSpokenAnswerGoesToTheSheetsFirst() {
    var m = SessionMachine()
    _ = m.handle(.job(.started(goal: "x")))
    _ = m.handle(.job(.approvalRequested(request("a1"))))
    _ = m.handle(.job(.approvalRequested(parentRequest("p1"))))
    let fx = m.handle(.approvalSpoken(approved: true))
    expect(fx.contains(.resolveApproval(requestId: "a1", approved: true, remember: false)),
           "hablado: resuelve la primera, la que la hoja enseña")
    expectEq(m.projection.approval?.requestId, "p1", "hablado: la siguiente pasa al frente")

    var first = SessionMachine()
    _ = first.handle(.job(.started(goal: "x")))
    _ = first.handle(.job(.approvalRequested(request("a1"))))
    let no = first.handle(.approvalSpoken(approved: false))
    expect(no.contains(.cancelJob), "hablado: negar el primer paso por voz también para el encargo")

    var empty = SessionMachine()
    let none = empty.handle(.approvalSpoken(approved: true))
    expect(none.isEmpty, "hablado: sin nada pendiente no concede nada")
}

/// Security review 2026-09-06 (plausible): una petición que llega después
/// de Stop, del encargo que acabas de parar, no reabre la cola: se niega.
@MainActor func testALateRequestAfterStopIsDenied() {
    var m = SessionMachine()
    _ = m.handle(.job(.started(goal: "x")))
    _ = m.handle(.stop)
    let fx = m.handle(.job(.approvalRequested(request("late"))))
    expect(m.projection.approvalQueue.isEmpty, "tardía: no entra en la cola")
    expect(fx.contains(.resolveApproval(requestId: "late", approved: false, remember: false)),
           "tardía: se niega sola")
    expectEq(m.projection.kind, .idle, "tardía: sigue idle")
}

/// Code review 2026-09-06 (alto): Stop cierra también el turno tecleado; si
/// no, la voz que vuelve a reposo se queda pintando «speaking» para siempre.
@MainActor func testStopClosesTheTypedTurn() {
    var m = SessionMachine()
    _ = m.handle(.typedSubmitted)
    _ = m.handle(.stop)
    _ = m.handle(voice(.listening))
    _ = m.handle(voice(.speaking))
    _ = m.handle(voice(.idle))
    expectEq(m.projection.kind, .idle, "stop: el turno tecleado no sobrevive al stop")
}

/// Code review 2026-09-06 (medio): un `.started` repetido solo renombra; no
/// reinicia la cuenta de acciones aprobadas.
@MainActor func testRenamingARunningJobKeepsItsApprovals() {
    var m = SessionMachine()
    _ = m.handle(.job(.started(goal: "x")))
    _ = m.handle(.job(.approvalRequested(request("a1"))))
    _ = m.handle(.approvalAnswered(requestId: "a1", approved: true, remember: false))
    _ = m.handle(.job(.started(goal: "x, con nombre")))
    _ = m.handle(.job(.approvalRequested(request("a2"))))
    let fx = m.handle(.approvalAnswered(requestId: "a2", approved: false, remember: false))
    expect(!fx.contains(.cancelJob), "renombrar: la segunda negación no es la primera")
}

private func voice(
    _ state: TurnState, muted: Bool = false, failure: TurnFailure? = nil,
    pipeline: VoicePipeline = .realtime
) -> SessionEvent {
    .voice(TurnSnapshot(state: state, pipeline: pipeline, muted: muted, failure: failure))
}

private func request(_ id: String) -> ApprovalRequest {
    ApprovalRequest(requestId: id, toolName: "run_shell", summary: "ls", inputJSON: "{}")
}

private func kinds(_ effects: [SessionEffect]) -> [SessionEffect] {
    effects.filter { if case .logTransition = $0 { false } else { true } }
}

/// 1. Nace en reposo, sin voz, sin encargo, sin cola.
@MainActor func testStartsIdle() {
    let m = SessionMachine()
    expectEq(m.projection, SessionProjection(), "arranque: la proyección vacía")
    expectEq(m.projection.kind, .idle, "arranque: idle")
    expectEq(m.projection.voice, .off, "arranque: voz apagada")
}

/// 2. Conectar no cambia el kind: la voz aún no escucha.
@MainActor func testConnectingKeepsTheKind() {
    var m = SessionMachine()
    let fx = m.handle(voice(.connecting))
    expectEq(m.projection.kind, .idle, "conectando: sigue idle")
    expectEq(m.projection.voice, .connecting, "conectando: la voz lo dice")
    expect(fx.isEmpty, "conectando: sin efectos ni transición")
}

/// 3. Escuchar es Listening; el silencio del micro es un estado de la voz.
@MainActor func testListeningFollowsTheVoice() {
    var m = SessionMachine()
    _ = m.handle(voice(.listening))
    expectEq(m.projection.kind, .listening, "escucha: listening")
    expectEq(m.projection.voice, .live, "escucha: voz viva")
    expectEq(m.projection.pipeline, .realtime, "escucha: el pipeline viaja")
    _ = m.handle(voice(.listening, muted: true))
    expectEq(m.projection.voice, .muted, "escucha: silenciada")
    expectEq(m.projection.kind, .idle, "escucha: con el micro cerrado el chrome descansa (12b)")
}

/// 4. Pensar y hablar son fases de Processing.
@MainActor func testThinkingAndSpeakingAreProcessing() {
    var m = SessionMachine()
    _ = m.handle(voice(.listening))
    _ = m.handle(voice(.thinking))
    expectEq(m.projection.kind, .processing(.thinking), "fase: thinking")
    _ = m.handle(voice(.speaking))
    expectEq(m.projection.kind, .processing(.speaking), "fase: speaking")
}

/// 5. Con un encargo vivo, la voz pensando no pisa la fila del hijo.
@MainActor func testAJobOutranksThinking() {
    var m = SessionMachine()
    _ = m.handle(voice(.listening))
    _ = m.handle(.job(.started(goal: "buscar vuelos")))
    _ = m.handle(voice(.thinking))
    expectEq(m.projection.kind, .processing(.subAgentRunning), "encargo: manda sobre thinking")
}

/// 6. Micrófono denegado: Idle, motivo y card con enlace. Nunca un kind error.
@MainActor func testAPermissionFailureIsACardNotAKind() {
    var m = SessionMachine()
    _ = m.handle(voice(.connecting))
    _ = m.handle(voice(.error, failure: .micDenied))
    expectEq(m.projection.kind, .idle, "permiso: vuelve a idle")
    expectEq(m.projection.voice, .off, "permiso: la voz está apagada")
    expectEq(m.projection.interruption, .failure(.micDenied), "permiso: el motivo queda")
    expectEq(m.projection.cards, [.permission(.micDenied)], "permiso: la card con enlace")
    _ = m.handle(voice(.error, failure: .speechDenied))
    expectEq(m.projection.cards, [.permission(.speechDenied)], "permiso: el habla también")
    _ = m.handle(voice(.error, failure: .sessionDropped))
    expectEq(m.projection.cards, [.failure(.sessionDropped)], "fallo: el resto es una línea")
}

/// 7. No se oyó nada: card de "no te oí", no un modo.
@MainActor func testNotHeardIsACouldntHearCard() {
    var m = SessionMachine()
    _ = m.handle(voice(.listening))
    _ = m.handle(voice(.error, failure: .notHeard))
    expectEq(m.projection.kind, .idle, "no oí: idle")
    expectEq(m.projection.cards, [.couldntHear], "no oí: la card")
    _ = m.handle(voice(.error, failure: .micSilent))
    expectEq(m.projection.cards, [.couldntHear], "micro mudo: la misma card")
}

/// 8. Colgar la voz no mata al hijo: el encargo sigue en su fila.
@MainActor func testVoiceIdleKeepsARunningJob() {
    var m = SessionMachine()
    _ = m.handle(voice(.listening))
    _ = m.handle(.job(.started(goal: "x")))
    _ = m.handle(voice(.idle))
    expectEq(m.projection.kind, .processing(.subAgentRunning), "colgar: el encargo sigue")
    expectEq(m.projection.voice, .off, "colgar: la voz sí se apaga")
}

/// 9. Turno tecleado con la voz apagada: thinking → speaking → completed →
/// timer → idle.
@MainActor func testTypedTurnEndsInCompletedThenIdle() {
    var m = SessionMachine()
    _ = m.handle(.typedSubmitted)
    expectEq(m.projection.kind, .processing(.thinking), "tecleado: thinking")
    _ = m.handle(.typedReplyStreaming)
    expectEq(m.projection.kind, .processing(.speaking), "tecleado: tokens en pantalla")
    let fx = m.handle(.typedReplyFinished)
    expectEq(m.projection.kind, .processing(.completed), "tecleado: completed")
    expect(fx.contains(.scheduleCompletedExpiry(SessionMachine.completedDelay)),
           "tecleado: se arma el timer")
    _ = m.handle(.completedTimerExpired)
    expectEq(m.projection.kind, .idle, "tecleado: el timer devuelve a idle")
}

/// 10. Con la voz viva no hay Completed: vuelve al kind de la voz.
@MainActor func testTypedTurnWithLiveVoiceReturnsToTheVoice() {
    var m = SessionMachine()
    _ = m.handle(voice(.listening))
    _ = m.handle(.typedSubmitted)
    let fx = m.handle(.typedReplyFinished)
    expectEq(m.projection.kind, .listening, "tecleado+voz: vuelve a listening")
    expect(!fx.contains(.scheduleCompletedExpiry(SessionMachine.completedDelay)),
           "tecleado+voz: sin timer")
    _ = m.handle(.completedTimerExpired)
    expectEq(m.projection.kind, .listening, "tecleado+voz: un timer tardío no hace nada")
}

/// 11. Las manos del padre: ToolExecuting mientras duran.
@MainActor func testParentActingIsToolExecuting() {
    var m = SessionMachine()
    _ = m.handle(.typedSubmitted)
    _ = m.handle(.parentActing(targets: ["Safari"]))
    expectEq(m.projection.kind, .processing(.toolExecuting), "padre: tool executing")
    _ = m.handle(.parentActed)
    expectEq(m.projection.kind, .processing(.thinking), "padre: el turno sigue pensando")
    _ = m.handle(.typedReplyFinished)
    expectEq(m.projection.kind, .processing(.completed), "padre: y termina")
}

/// 12. Un encargo desde idle: el hijo tiene fila.
@MainActor func testJobStartedIsSubAgentRunning() {
    var m = SessionMachine()
    _ = m.handle(.job(.started(goal: "crear prueba.md")))
    expectEq(m.projection.kind, .processing(.subAgentRunning), "encargo: sub-agent running")
    expectEq(m.projection.job?.goal, "crear prueba.md", "encargo: con nombre")
}

/// 13. Los pasos se acumulan; la fase no cambia; un paso sin encargo lo crea.
@MainActor func testStepsAccumulateOnTheTimeline() {
    var m = SessionMachine()
    _ = m.handle(.job(.stepStarted(tool: "Write", summary: "prueba1.md")))
    expect(m.projection.job != nil, "pasos: un paso huérfano abre la tarjeta")
    _ = m.handle(.job(.started(goal: "crear")))
    expectEq(m.projection.job?.goal, "crear", "pasos: el nombre llega después")
    _ = m.handle(.job(.stepFinished(tool: "Write", ok: true)))
    _ = m.handle(.job(.thought("reviso")))
    _ = m.handle(.job(.stepStarted(tool: "Bash", summary: "")))
    let steps = m.projection.job?.steps ?? []
    expectEq(steps.count, 3, "pasos: uno por herramienta y uno por pensamiento")
    expectEq(steps.first?.label, "Write: prueba1.md", "pasos: la etiqueta lleva la ruta")
    expectEq(steps[1].tool, JobSteps.Thinking.tool, "pasos: el pensamiento es un paso")
    expectEq(steps.last?.label, "Bash", "pasos: sin resumen queda la herramienta")
    expectEq(m.projection.kind, .processing(.subAgentRunning), "pasos: la fase no cambia")
}

/// 14. Un permiso pedido no es un estado: es la primera de la cola y una card.
@MainActor func testApprovalRequestedStaysProcessing() {
    var m = SessionMachine()
    _ = m.handle(.job(.started(goal: "x")))
    _ = m.handle(.job(.approvalRequested(request("r1"))))
    expectEq(m.projection.kind, .processing(.subAgentRunning), "permiso: sigue processing")
    expectEq(m.projection.approval?.requestId, "r1", "permiso: al frente de la cola")
    expectEq(m.projection.cards, [.approval(request("r1"))], "permiso: la card")
}

/// 15. Dos peticiones se contestan en orden y con el id correcto.
@MainActor func testTwoRequestsAnswerInOrder() {
    var m = SessionMachine()
    _ = m.handle(.job(.started(goal: "x")))
    _ = m.handle(.job(.approvalRequested(request("r1"))))
    _ = m.handle(.job(.approvalRequested(request("r2"))))
    expectEq(m.projection.approvalQueue.count, 2, "cola: dos")
    let fx = m.handle(.approvalAnswered(requestId: "r1", approved: true, remember: true))
    expectEq(kinds(fx), [.resolveApproval(requestId: "r1", approved: true, remember: true)],
             "cola: se resuelve la primera, con recordar")
    expectEq(m.projection.approval?.requestId, "r2", "cola: la segunda pasa al frente")
    let late = m.handle(.approvalAnswered(requestId: "nadie", approved: true, remember: false))
    expect(late.isEmpty, "cola: contestar lo que no está pendiente no resuelve nada")
}

/// 16. Negar la PRIMERA acción para el encargo entero (regla 10c); negar una
/// posterior solo la niega. Un no que para no se recuerda.
@MainActor func testDenyingTheFirstActionStopsTheJob() {
    var m = SessionMachine()
    _ = m.handle(.job(.started(goal: "revisar el disco")))
    _ = m.handle(.job(.approvalRequested(request("a1"))))
    let fx = m.handle(.approvalAnswered(requestId: "a1", approved: false, remember: true))
    expect(fx.contains(.resolveApproval(requestId: "a1", approved: false, remember: false)),
           "negar 1º: se resuelve sin recordar")
    expect(fx.contains(.cancelJob), "negar 1º: para el encargo")
    expectEq(m.projection.kind, .idle, "negar 1º: idle")
    expectEq(m.projection.interruption, .userStopped, "negar 1º: el motivo")
    expect(m.projection.job == nil, "negar 1º: sin tarjeta")

    var later = SessionMachine()
    _ = later.handle(.job(.started(goal: "x")))
    _ = later.handle(.job(.approvalRequested(request("a1"))))
    _ = later.handle(.approvalAnswered(requestId: "a1", approved: true, remember: false))
    _ = later.handle(.job(.approvalRequested(request("a2"))))
    let fx2 = later.handle(.approvalAnswered(requestId: "a2", approved: false, remember: true))
    expectEq(kinds(fx2), [.resolveApproval(requestId: "a2", approved: false, remember: true)],
             "negar 2º: solo esa acción, y se recuerda")
    expect(later.projection.job != nil, "negar 2º: el encargo sigue")
}

/// 17. Una card del padre en reposo no cambia el kind.
@MainActor func testACardInIdleStaysIdle() {
    var m = SessionMachine()
    let card = Card(payload: .gallery(GalleryBlock(images: [])), source: .tool)
    _ = m.handle(.job(.card(card)))
    expectEq(m.projection.kind, .idle, "card: sigue idle")
    expectEq(m.projection.cards, [.answer(card)], "card: se proyecta")
}

/// 18. El encargo termina: Completed con la voz apagada, la voz si está viva.
@MainActor func testJobFinishedRestsOnTheVoice() {
    var m = SessionMachine()
    _ = m.handle(.job(.started(goal: "x")))
    let fx = m.handle(.jobFinished(ok: true))
    expectEq(m.projection.kind, .processing(.completed), "fin: completed")
    expect(fx.contains(.scheduleCompletedExpiry(SessionMachine.completedDelay)), "fin: timer")
    expect(m.projection.job == nil, "fin: sin tarjeta")

    var live = SessionMachine()
    _ = live.handle(voice(.listening))
    _ = live.handle(.job(.started(goal: "x")))
    _ = live.handle(.jobFinished(ok: false))
    expectEq(live.projection.kind, .listening, "fin+voz: vuelve a listening")
    let idle = live.handle(.jobFinished(ok: true))
    expect(idle.isEmpty, "fin: terminar dos veces no hace nada")
}

/// 19. Stop: Idle, motivo, el hijo muere y las peticiones pendientes se niegan.
@MainActor func testStopReturnsToIdleAndKillsTheChildren() {
    var m = SessionMachine()
    _ = m.handle(.job(.started(goal: "x")))
    _ = m.handle(.job(.approvalRequested(request("r1"))))
    _ = m.handle(.job(.approvalRequested(request("r2"))))
    let fx = m.handle(.stop)
    expectEq(m.projection.kind, .idle, "stop: idle")
    expectEq(m.projection.interruption, .userStopped, "stop: el motivo")
    expect(m.projection.job == nil, "stop: sin encargo")
    expect(m.projection.approvalQueue.isEmpty, "stop: cola vacía")
    expectEq(kinds(fx), [
        .cancelJob,
        .resolveApproval(requestId: "r1", approved: false, remember: false),
        .resolveApproval(requestId: "r2", approved: false, remember: false),
    ], "stop: mata al hijo y niega lo pendiente")
}

/// 20. Stop en reposo no hace nada.
@MainActor func testStopInIdleIsANoOp() {
    var m = SessionMachine()
    let fx = m.handle(.stop)
    expect(fx.isEmpty, "stop idle: sin efectos")
    expectEq(m.projection, SessionProjection(), "stop idle: sin cambios")
}

/// 21. Hover solo existe desde reposo.
@MainActor func testHoverOnlyFromIdle() {
    var m = SessionMachine()
    _ = m.handle(.hoverEntered)
    expectEq(m.projection.kind, .hover, "hover: desde idle")
    _ = m.handle(.hoverLeft)
    expectEq(m.projection.kind, .idle, "hover: y vuelve")
    _ = m.handle(voice(.listening))
    _ = m.handle(.hoverEntered)
    expectEq(m.projection.kind, .listening, "hover: escuchando no hay hover")
}

/// 22. Las cards son de ESTE paso: el siguiente evento las borra.
@MainActor func testCardsAreTransient() {
    var m = SessionMachine()
    _ = m.handle(voice(.error, failure: .micDenied))
    expect(!m.projection.cards.isEmpty, "cards: hay una")
    _ = m.handle(.hoverEntered)
    expect(m.projection.cards.isEmpty, "cards: el siguiente evento la retira")
    expectEq(m.projection.interruption, .failure(.micDenied), "cards: el motivo sí se queda")
    _ = m.handle(voice(.listening))
    expect(m.projection.interruption == nil, "cards: escuchar de nuevo limpia el motivo")
}

/// 23. Cada cambio de kind se loguea; un evento sin cambio, no.
@MainActor func testEveryKindChangeIsLogged() {
    var m = SessionMachine()
    let fx = m.handle(voice(.listening))
    expectEq(fx, [.logTransition(from: .idle, to: .listening)], "log: la transición")
    let again = m.handle(voice(.listening))
    expect(again.isEmpty, "log: sin cambio no hay línea")
}

/// 24. Una petición resuelta por otra vía (el "sí" hablado, el actor al
/// contestar) sale de la cola sin volver a resolverse.
@MainActor func testSettledRequestsLeaveTheQueue() {
    var m = SessionMachine()
    _ = m.handle(.job(.started(goal: "x")))
    _ = m.handle(.job(.approvalRequested(request("r1"))))
    let fx = m.handle(.approvalSettled(requestId: "r1"))
    expect(m.projection.approvalQueue.isEmpty, "settled: fuera de la cola")
    expect(kinds(fx).isEmpty, "settled: sin resolver otra vez")
    _ = m.handle(.job(.approvalRequested(request("p1"))))
    let dropped = m.handle(.approvalDropped(requestId: "p1"))
    expectEq(kinds(dropped), [.resolveApproval(requestId: "p1", approved: false, remember: false)],
             "dropped: se niega sin parar el encargo")
    expect(m.projection.job != nil, "dropped: el encargo sigue")
}

/// 33. Security review 2026-09-06 (alto): entre holds la sesión seguía
/// abierta con el micro físico tomado, sin ventana ni indicador. Un reposo
/// con la voz caliente por un hold arma un plazo; vencido, cuelga. La
/// manos libres silenciada desde la ventana no cuelga sola.
@MainActor func testAWarmHoldSessionIdlesOut() {
    var m = SessionMachine()
    _ = m.handle(.pressed)
    _ = m.handle(.released)
    _ = m.handle(voice(.speaking))
    let fx = m.handle(.voice(TurnSnapshot(state: .listening, pipeline: .realtime, muted: true, holdArmed: true)))
    expect(fx.contains(.scheduleVoiceIdleExpiry(SessionMachine.voiceIdleTimeout)),
           "caliente: el reposo arma el plazo")
    _ = m.handle(.completedTimerExpired)
    expectEq(m.projection.kind, .idle, "caliente: idle")
    expect(m.handle(.voiceIdleExpired).contains(.hangUpVoice), "caliente: vencido, cuelga")

    var pressed = SessionMachine()
    _ = pressed.handle(.voice(TurnSnapshot(state: .listening, pipeline: .realtime, muted: true, holdArmed: true)))
    _ = pressed.handle(.pressed)
    expect(!pressed.handle(.voiceIdleExpired).contains(.hangUpVoice),
           "caliente: un plazo que vence durante un hold no cuelga")

    var handsFree = SessionMachine()
    let hf = handsFree.handle(voice(.listening, muted: true))
    expect(!hf.contains { if case .scheduleVoiceIdleExpiry = $0 { true } else { false } },
           "manos libres: silenciar desde la ventana no arma el plazo")
}

/// 34 (12c). El parcial del oído es un campo de la proyección: solo se
/// escribe en Listening, sobrevive a Pending y se borra cuando algo nuevo
/// empieza o la fase cambia.
@MainActor func testThePartialIsAFieldNotAKind() {
    var m = SessionMachine()
    _ = m.handle(.partialTranscript("hola"))
    expect(m.projection.partial == nil, "parcial: en idle se ignora")
    _ = m.handle(.pressed)
    let fx = m.handle(.partialTranscript("hola"))
    expectEq(m.projection.partial, "hola", "parcial: en listening se escribe")
    expectEq(m.projection.kind, .listening, "parcial: el kind no se mueve")
    expect(!fx.contains { if case .logTransition = $0 { true } else { false } }, "parcial: sin transición")
    _ = m.handle(.partialTranscript("hola mundo"))
    _ = m.handle(.released)
    expectEq(m.projection.partial, "hola mundo", "parcial: sigue en pending")
    _ = m.handle(voice(.thinking))
    expect(m.projection.partial == nil, "parcial: se borra al pensar")

    var tapped = SessionMachine()
    _ = tapped.handle(.pressed)
    _ = tapped.handle(.partialTranscript("eh"))
    _ = tapped.handle(.tapped)
    expect(tapped.projection.partial == nil, "parcial: un tap lo borra")

    var nothing = SessionMachine()
    _ = nothing.handle(.pressed)
    _ = nothing.handle(.partialTranscript("eh"))
    _ = nothing.handle(.released)
    _ = nothing.handle(.heardNothing)
    expect(nothing.projection.partial == nil, "parcial: «no te oí» lo borra")

    var stopped = SessionMachine()
    _ = stopped.handle(.pressed)
    _ = stopped.handle(.partialTranscript("eh"))
    _ = stopped.handle(.stop)
    expect(stopped.projection.partial == nil, "parcial: stop lo borra")

    var again = SessionMachine()
    _ = again.handle(.pressed)
    _ = again.handle(.partialTranscript("uno"))
    _ = again.handle(.released)
    _ = again.handle(.pressed)
    expect(again.projection.partial == nil, "parcial: pulsar de nuevo empieza limpio")
}

/// 35 (12e). El dictado es una bifurcación del hold, no un kind: la app
/// enfocada viaja en un campo; pegar termina en Completed y vuelve a Idle;
/// un fallo de permiso es un aviso; todo se borra al empezar algo nuevo.
@MainActor func testDictationIsAForkNotAKind() {
    var m = SessionMachine()
    _ = m.handle(.dictating(app: "Slack"))
    expect(m.projection.dictation == nil, "dictado: en idle se ignora")
    _ = m.handle(.pressed)
    let fx = m.handle(.dictating(app: "Slack"))
    expectEq(m.projection.dictation, "Slack", "dictado: en listening se anota la app")
    expectEq(m.projection.kind, .listening, "dictado: el kind no se mueve")
    expect(!fx.contains { if case .logTransition = $0 { true } else { false } }, "dictado: sin transición")
    _ = m.handle(.partialTranscript("hola"))
    _ = m.handle(.released)
    expectEq(m.projection.dictation, "Slack", "dictado: sigue en pending")
    let done = m.handle(.dictated(app: "Slack"))
    expectEq(m.projection.kind, .processing(.completed), "dictado: pegar es Completed")
    expect(!m.projection.holding, "dictado: la mano ya no está")
    expect(m.projection.partial == nil, "dictado: el parcial se fue con el texto")
    expectEq(m.projection.dictation, "Slack", "dictado: Completed aún dice dónde")
    expect(done.contains { if case .scheduleCompletedExpiry = $0 { true } else { false } },
           "dictado: Completed tiene su temporizador")
    _ = m.handle(.completedTimerExpired)
    expectEq(m.projection.kind, .idle, "dictado: y vuelve a idle")
    expect(m.projection.dictation == nil, "dictado: idle no recuerda la app")

    var forked = SessionMachine()
    _ = forked.handle(.pressed)
    _ = forked.handle(.dictating(app: "Slack"))
    _ = forked.handle(.released)
    _ = forked.handle(.voice(TurnSnapshot(state: .thinking, pipeline: .realtime)))
    expect(forked.projection.dictation == nil, "dictado: si cae al agente, pensar lo borra")

    var denied = SessionMachine()
    _ = denied.handle(.pressed)
    _ = denied.handle(.released)
    _ = denied.handle(.dictationFailed(.needsAccessibility))
    expectEq(denied.projection.kind, .processing(.pending), "aviso: el kind no se toca")
    expectEq(denied.projection.notice, .permission(.accessibilityDenied), "aviso: el permiso queda anotado")
    _ = denied.handle(.voice(TurnSnapshot(state: .thinking, pipeline: .realtime)))
    _ = denied.handle(.voice(TurnSnapshot(state: .listening, pipeline: .realtime, muted: true)))
    expectEq(denied.projection.notice, .permission(.accessibilityDenied), "aviso: sigue ahí en reposo")
    _ = denied.handle(.pressed)
    expect(denied.projection.notice == nil, "aviso: empezar algo nuevo lo borra")

    var stopped = SessionMachine()
    _ = stopped.handle(.pressed)
    _ = stopped.handle(.dictating(app: "Slack"))
    _ = stopped.handle(.stop)
    expect(stopped.projection.dictation == nil, "dictado: Stop lo borra")
    _ = stopped.handle(.dictated(app: "Slack"))
    expectEq(stopped.projection.kind, .idle, "dictado: un pegado tardío tras Stop no es Completed")
}

/// 36 (fix puente). La hoja del puente llega en reposo: el guard del
/// 2026-09-06 mata la petición tardía del encargo recién parado, no la
/// sesión nueva del puente. Visto en vivo 2026-09-28: tras cualquier Stop
/// la proyección quedaba envenenada (`userStopped` solo se limpia al abrir
/// turno) y toda petición `bridge_session` se negaba sola, sin hoja.
@MainActor func testBridgeAskReachesTheSheetAtRest() {
    var m = SessionMachine()
    _ = m.handle(.job(.started(goal: "x")))
    _ = m.handle(.stop)
    expectEq(m.projection.interruption, .userStopped, "previo: el reposo envenenado")

    let bridge = ApprovalRequest(
        requestId: "b1", toolName: BridgePolicy.sessionApprovalTool,
        summary: "claude-code pide las manos", inputJSON: #"{"client":"claude-code"}"#)
    let fx = m.handle(.job(.approvalRequested(bridge)))
    expect(!fx.contains(.resolveApproval(requestId: "b1", approved: false, remember: false)),
           "puente: no se niega solo")
    expectEq(m.projection.approvalQueue, [bridge], "puente: entra a la cola")
    expectEq(m.projection.cards, [.approval(bridge)], "puente: la hoja se proyecta")

    // La protección original sigue: una petición del encargo parado muere.
    var late = SessionMachine()
    _ = late.handle(.job(.started(goal: "x")))
    _ = late.handle(.stop)
    let fx2 = late.handle(.job(.approvalRequested(request("r9"))))
    expect(fx2.contains(.resolveApproval(requestId: "r9", approved: false, remember: false)),
           "encargo parado: la tardía sigue muriendo")
    expect(late.projection.approvalQueue.isEmpty, "encargo parado: nada en cola")
}
