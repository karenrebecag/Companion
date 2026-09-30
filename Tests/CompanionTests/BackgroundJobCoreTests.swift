import CompanionCore
import Foundation
import Testing

// Wave 16h-2 (criteria 1 and 2), the pure part: the acknowledgement line,
// when a job's end may sound without talking over anyone, the ack's mark on
// the timeline, and the reducer with a live job while the user keeps talking.

@Test func backgroundJobCoreTests() {
    testTheAckIsOurOwnLineInEachLanguage()
    testEveryAckPassesTheFilterWholeAndFitsTheBudget()
    testAnAckIsOnlyNeededWhileNothingWasSaid()
    testTheAnnouncementWaitsWhileTheUserHoldsOrATurnRuns()
    testTheAnnouncementSoundsAtRest()
    testTheTimelineSaysWhenTheAckLeft()
    testTheTurnEndsAfterTheAckAndTheJobStaysOnTheProjection()
    testANewHoldWhileTheJobRunsNeverStopsIt()
    testTheNewTurnShowsItsOwnPhasesAndThenTheJobAgain()
    testStopStillBrakesTheJobAfterANewTurn()
    testTheJobEndingDuringANewTurnLeavesTheTurnItsPhase()
    testATypedTurnOverTheJobThinksAsItsOwn()
    testAStoppedJobsLateStepDoesNotReopenItsRow()
    testAnotherJobsStepOpensTheRowAfterAStop()
    testASecondStartedFromAnotherJobDoesNotRenameTheActiveCard()
    testAQueuedJobsStepsNeverPaintOnTheActiveRow()
    testWhenTheActiveJobEndsTheQueuedOneTakesTheRow()
    testAQueuedJobThatEndsLeavesTheActiveRowAlone()
    testAnUnknownJobsEndChangesNothing()
    testTheFirstApprovalIsNotInheritedByTheNextJob()
    testALateApprovalOfAStoppedJobIsDenied()
    testDenyingTheBridgeGrantWhileAJobRunsStopsNothing()
    testAnApprovalAnsweredAfterItsJobEndedDoesNotTouchTheNext()
    testAnUntaggedRequestAfterAStopIsNotDenied()
    testTheSheetOfTheActiveJobKeepsItsName()
    testStopClosesTheActiveAndTheQueuedRows()
    testTheParentsHandsInsideAnOwnTurnOverAJobShowTheTurn()
    testACancelledPressOverAJobGoesBackToTheReply()
    testASecondStartedDuringAnOwnTurnKeepsTheTurnInFront()
    testTheTurnFlagDiesWithTheJob()
    testStopAtRestSilencesASoundingNotice()
    testTheWarmSessionWaitsForTheNoticeBeforeHangingUp()
    testASpokenYesNeedsAnAnnouncementBeforeTheHold()
    testAFinishedJobsLateStepOpensNoRow()
    testAFinishedJobsPendingApprovalLeavesTheSheet()
}

/// Review 16h-2 round 3: a job that ended takes its unanswered questions
/// with it; the sheet never shows a question nobody is waiting on.
func testAFinishedJobsPendingApprovalLeavesTheSheet() {
    var m = running(jobA, "vuelos")
    _ = m.handle(.job(.started(goal: "hotel"), from: jobB))
    _ = m.handle(.job(.approvalRequested(ask("a1")), from: jobA))
    _ = m.handle(.job(.approvalRequested(ask("b1")), from: jobB))
    let untagged = ApprovalRequest(requestId: "p1", toolName: "open_url", summary: "", inputJSON: "{}")
    _ = m.handle(.job(.approvalRequested(untagged)))
    let fx = m.handle(.jobFinished(ok: true, from: jobA))
    expect(fx.contains(.resolveApproval(requestId: "a1", approved: false, remember: false)),
           "fin: su permiso pendiente se niega (\(fx))")
    expectEq(m.projection.approvalQueue.map(\.requestId), ["b1", "p1"],
             "fin: sale de la hoja; los de otros siguen")
    let queuedEnd = m.handle(.jobFinished(ok: false, from: jobB))
    expect(queuedEnd.contains(.resolveApproval(requestId: "b1", approved: false, remember: false)),
           "fin: también el de un encargo que termina en cola")
}

/// Review 16h-2 round 3 (SHOULD 2): a step delivered after its job's end is
/// the end's leftover, never a new nameless row.
func testAFinishedJobsLateStepOpensNoRow() {
    var m = running(jobA, "vuelos")
    _ = m.handle(.jobFinished(ok: true, from: jobA))
    _ = m.handle(.job(.stepStarted(tool: "Bash", summary: "ls"), from: jobA))
    _ = m.handle(.job(.thought("sigo"), from: jobA))
    expectEq(m.projection.job, nil, "terminado: su paso tardío no abre fila")
    _ = m.handle(.job(.stepStarted(tool: "Bash", summary: "ls"), from: jobC))
    expectEq(m.projection.job?.id, jobC, "terminado: el de otro encargo sí")
}

/// Review 16h-2 round 3 (HIGH): the one rule every spoken yes goes through.
func testASpokenYesNeedsAnAnnouncementBeforeTheHold() {
    let dwell = ApprovalClickGuard.dwell
    expect(!SpokenYes.admits(realtime: true, announcedAt: 0, holdStartedAt: 5, heard: "sí"),
           "sí hablado: en realtime nunca")
    expect(!SpokenYes.admits(realtime: false, announcedAt: nil, holdStartedAt: 5, heard: "sí"),
           "sí hablado: sin anuncio, no")
    expect(!SpokenYes.admits(realtime: false, announcedAt: 5, holdStartedAt: nil, heard: "sí"),
           "sí hablado: sin hold, no")
    expect(!SpokenYes.admits(realtime: false, announcedAt: 5, holdStartedAt: 4, heard: "sí"),
           "sí hablado: un hold anterior al anuncio, no")
    expect(!SpokenYes.admits(realtime: false, announcedAt: 5, holdStartedAt: 5 + dwell / 2, heard: "sí"),
           "sí hablado: un hold pegado al anuncio, no")
    expect(SpokenYes.admits(realtime: false, announcedAt: 5, holdStartedAt: 5 + dwell, heard: "sí"),
           "sí hablado: anuncio, luego un hold pasado el dwell, sí")
}

// MARK: - ack: the line

func testTheAckIsOurOwnLineInEachLanguage() {
    expectEq(Acknowledgement.delegating(.es), DecisionCopy.delegated(.es),
             "acuse: la misma frase que el router, en español")
    expectEq(Acknowledgement.delegating(.en), DecisionCopy.delegated(.en),
             "acuse: y en inglés")
    expect(Acknowledgement.working(tool: "see", .es) != Acknowledgement.working(tool: "open_app", .es),
           "acuse: mirar la pantalla se nombra aparte")
    expect(Acknowledgement.working(tool: "look", .en).lowercased().contains("screen"),
           "acuse: la vista dice que mira la pantalla (\(Acknowledgement.working(tool: "look", .en)))")
    expect(Acknowledgement.working(tool: "look", .es).lowercased().contains("pantalla"),
           "acuse: y en español")
}

func testEveryAckPassesTheFilterWholeAndFitsTheBudget() {
    let tools = ["see", "look", "open_app", "list_apps", "linear_create_issue"]
    for language in [AppLanguage.es, .en] {
        let lines = [Acknowledgement.delegating(language)]
            + tools.map { Acknowledgement.working(tool: $0, language) }
        for line in lines {
            expectEq(SpeechFilter.clean(line), line, "acuse: el filtro no le quita nada (\(line))")
            var budget = SpeechBudget()
            budget.cardShown = true
            expectEq(budget.admit(line), line, "acuse: cabe en el presupuesto de voz (\(line))")
        }
    }
}

func testAnAckIsOnlyNeededWhileNothingWasSaid() {
    expect(Acknowledgement.isNeeded(saidSoFar: ""), "acuse: sin nada dicho, hace falta")
    expect(Acknowledgement.isNeeded(saidSoFar: "  \n"), "acuse: blancos no cuentan como frase")
    expect(!Acknowledgement.isNeeded(saidSoFar: "Voy a buscarlo."), "acuse: el modelo ya habló, basta")
}

// MARK: - the job end waits for its gap

func testTheAnnouncementWaitsWhileTheUserHoldsOrATurnRuns() {
    let hold = TurnSnapshot(state: .listening, pipeline: .classic, holdArmed: true)
    expect(!AnnouncementGap.isOpen(hold), "aviso: con la tecla abajo, espera")
    let starting = TurnSnapshot(state: .idle, classicListenPending: true, holdArmed: true)
    expect(!AnnouncementGap.isOpen(starting), "aviso: con el micro arrancando, espera")
    for state in [TurnState.thinking, .speaking, .connecting] {
        let busy = TurnSnapshot(state: state, pipeline: .classic, holdArmed: true)
        expect(!AnnouncementGap.isOpen(busy), "aviso: con un turno en curso (\(state)), espera")
    }
    let speakingOpen = TurnSnapshot(state: .listening, pipeline: .classic, speechOpen: true)
    expect(!AnnouncementGap.isOpen(speakingOpen), "aviso: manos libres con la usuaria hablando, espera")
}

func testTheAnnouncementSoundsAtRest() {
    expect(AnnouncementGap.isOpen(.idle), "aviso: en reposo suena (la voz del hold ya terminó)")
    let warm = TurnSnapshot(state: .listening, pipeline: .classic, muted: true, holdArmed: true)
    expect(AnnouncementGap.isOpen(warm), "aviso: sesión tibia con el micro cerrado, suena")
    let handsFree = TurnSnapshot(state: .listening, pipeline: .classic)
    expect(AnnouncementGap.isOpen(handsFree), "aviso: manos libres en silencio, suena")
    let realtime = TurnSnapshot(state: .listening, pipeline: .realtime)
    expect(AnnouncementGap.isOpen(realtime), "aviso: realtime escuchando, como antes")
    let failed = TurnSnapshot(state: .error, failure: .sessionDropped)
    expect(!AnnouncementGap.isOpen(failed), "aviso: con la voz en error, no")
}

// MARK: - the timeline carries the ack

func testTheTimelineSaysWhenTheAckLeft() {
    var t = TurnTimeline()
    t.mark(.pressed, at: 10)
    t.mark(.committed, at: 10.5)
    t.mark(.acknowledged, at: 11.1)
    t.mark(.acknowledged, at: 12)
    t.mark(.firstAudio, at: 11.4)
    let line = t.line() ?? ""
    expect(line.contains("· commit→ack 600 · commit→audio 900 ·"),
           "acuse: commit→ack se ve, la primera marca gana, junto a commit→audio (\(line))")
}

// MARK: - the reducer: the turn ends, the job goes on

private func voice(
    _ state: TurnState, muted: Bool = false, pipeline: VoicePipeline = .classic
) -> SessionEvent {
    .voice(TurnSnapshot(state: state, pipeline: pipeline, muted: muted, holdArmed: state != .idle))
}

private func real(_ effects: [SessionEffect]) -> [SessionEffect] {
    effects.filter { if case .logTransition = $0 { false } else { true } }
}

/// The delegating hold: press, release, the voice thinks, says the ack, the
/// job starts, the ack ends and the voice goes idle.
private func delegatingTurn() -> SessionMachine {
    var m = SessionMachine()
    _ = m.handle(.pressed)
    _ = m.handle(voice(.listening))
    _ = m.handle(.released)
    _ = m.handle(voice(.thinking))
    _ = m.handle(voice(.speaking))
    _ = m.handle(.job(.started(goal: "busca vuelos en Safari")))
    _ = m.handle(voice(.idle))
    return m
}

func testTheTurnEndsAfterTheAckAndTheJobStaysOnTheProjection() {
    let m = delegatingTurn()
    expectEq(m.projection.kind, .processing(.subAgentRunning), "fondo: el turno acabó, la fila del encargo queda")
    expectEq(m.projection.job?.goal, "busca vuelos en Safari", "fondo: el encargo sigue en la proyección")
    expect(!m.projection.holding, "fondo: nadie tiene la tecla")
}

func testANewHoldWhileTheJobRunsNeverStopsIt() {
    var m = delegatingTurn()
    let press = m.handle(.pressed)
    expect(!press.contains(.cancelJob), "hold nuevo: no mata el encargo")
    expectEq(m.projection.kind, .listening, "hold nuevo: la usuaria habla")
    _ = m.handle(voice(.listening))
    let release = m.handle(.released)
    expect(!release.contains(.cancelJob), "hold nuevo: soltar tampoco")
    expectEq(m.projection.kind, .processing(.pending), "hold nuevo: pending")
    expect(m.projection.job != nil, "hold nuevo: el encargo sigue vivo")
}

func testTheNewTurnShowsItsOwnPhasesAndThenTheJobAgain() {
    var m = delegatingTurn()
    _ = m.handle(.pressed)
    _ = m.handle(voice(.listening))
    _ = m.handle(.released)
    _ = m.handle(voice(.thinking))
    expectEq(m.projection.kind, .processing(.thinking),
             "turno nuevo: piensa como turno suyo, no como la fila del encargo")
    _ = m.handle(voice(.speaking))
    expectEq(m.projection.kind, .processing(.speaking), "turno nuevo: habla")
    _ = m.handle(voice(.idle))
    expectEq(m.projection.kind, .processing(.subAgentRunning), "turno nuevo: al acabar vuelve el encargo")
    _ = m.handle(voice(.thinking))
    expectEq(m.projection.kind, .processing(.subAgentRunning),
             "sin turno nuevo, la voz pensando no pisa la fila del encargo")
}

func testStopStillBrakesTheJobAfterANewTurn() {
    var m = delegatingTurn()
    _ = m.handle(.pressed)
    _ = m.handle(voice(.listening))
    _ = m.handle(.released)
    _ = m.handle(voice(.thinking))
    let stop = m.handle(.stop)
    expect(real(stop).contains(.cancelJob), "parar: el freno del encargo sigue funcionando (9g)")
    expectEq(m.projection.job, nil, "parar: la fila se va")
    expectEq(m.projection.kind, .idle, "parar: reposo")
}

func testTheJobEndingDuringANewTurnLeavesTheTurnItsPhase() {
    var m = delegatingTurn()
    _ = m.handle(.pressed)
    _ = m.handle(voice(.listening))
    _ = m.handle(.released)
    _ = m.handle(voice(.thinking))
    _ = m.handle(.jobFinished(ok: true))
    expectEq(m.projection.job, nil, "fin del encargo: la fila se va")
    expectEq(m.projection.kind, .processing(.thinking), "fin del encargo: el turno de la usuaria sigue el suyo")
}

func testATypedTurnOverTheJobThinksAsItsOwn() {
    var m = delegatingTurn()
    _ = m.handle(.typedSubmitted)
    expectEq(m.projection.kind, .processing(.thinking), "tecleado: su fase")
    _ = m.handle(voice(.thinking))
    expectEq(m.projection.kind, .processing(.thinking), "tecleado: la voz pensando no lo tapa")
    _ = m.handle(.typedReplyFinished)
    expectEq(m.projection.kind, .processing(.subAgentRunning), "tecleado: al acabar, el encargo")
}


// MARK: - identity: events carry the job they come from

private let jobA = JobID("a")
private let jobB = JobID("b")
private let jobC = JobID("c")

private func running(_ id: JobID, _ goal: String) -> SessionMachine {
    var m = SessionMachine()
    _ = m.handle(.job(.started(goal: goal), from: id))
    return m
}

/// The stopped job's own step, delivered late (its events travel on their
/// own task), must not bring back a row the user just closed.
func testAStoppedJobsLateStepDoesNotReopenItsRow() {
    var m = running(jobA, "vuelos")
    _ = m.handle(.stop)
    _ = m.handle(.job(.stepStarted(tool: "run_shell", summary: "df -h"), from: jobA))
    _ = m.handle(.job(.thought("sigo"), from: jobA))
    _ = m.handle(.job(.started(goal: "vuelos"), from: jobA))
    expectEq(m.projection.job, nil, "parar: nada tardío del encargo parado reabre la fila")
    expectEq(m.projection.kind, .idle, "parar: sigue en reposo")
}

func testAnotherJobsStepOpensTheRowAfterAStop() {
    var m = running(jobA, "vuelos")
    _ = m.handle(.stop)
    _ = m.handle(.job(.stepStarted(tool: "run_shell", summary: "ls"), from: jobC))
    expectEq(m.projection.job?.id, jobC, "otro encargo: su paso sí abre su fila")
}

func testASecondStartedFromAnotherJobDoesNotRenameTheActiveCard() {
    var m = running(jobA, "vuelos")
    _ = m.handle(.job(.started(goal: "hotel"), from: jobB))
    expectEq(m.projection.job?.goal, "vuelos", "cola: la tarjeta activa conserva su nombre")
    expectEq(m.projection.job?.id, jobA, "cola: y su identidad")
    expectEq(m.projection.queued.map(\.goal), ["hotel"], "cola: el segundo espera aparte")
}

func testAQueuedJobsStepsNeverPaintOnTheActiveRow() {
    var m = running(jobA, "vuelos")
    _ = m.handle(.job(.started(goal: "hotel"), from: jobB))
    _ = m.handle(.job(.stepStarted(tool: "Bash", summary: "ls"), from: jobB))
    expectEq(m.projection.job?.steps.count, 0, "cola: el paso de B no se pinta en la fila de A")
    expectEq(m.projection.queued.first?.steps.count, 1, "cola: va a la suya")
}

func testWhenTheActiveJobEndsTheQueuedOneTakesTheRow() {
    var m = running(jobA, "vuelos")
    _ = m.handle(.job(.started(goal: "hotel"), from: jobB))
    _ = m.handle(.jobFinished(ok: true, from: jobA))
    expectEq(m.projection.job?.id, jobB, "cola: al acabar A, B toma la fila")
    expectEq(m.projection.job?.goal, "hotel", "cola: con su nombre")
    expect(m.projection.queued.isEmpty, "cola: vacía")
    expectEq(m.projection.kind, .processing(.subAgentRunning), "cola: la fila sigue viva")
}

func testAQueuedJobThatEndsLeavesTheActiveRowAlone() {
    var m = running(jobA, "vuelos")
    _ = m.handle(.job(.started(goal: "hotel"), from: jobB))
    _ = m.handle(.jobFinished(ok: false, from: jobB))
    expectEq(m.projection.job?.id, jobA, "cola: el fin de B no cierra la fila de A")
    expect(m.projection.queued.isEmpty, "cola: B sale de la cola")
}

func testAnUnknownJobsEndChangesNothing() {
    var m = running(jobA, "vuelos")
    let fx = m.handle(.jobFinished(ok: true, from: jobC))
    expectEq(fx, [], "fin ajeno: sin efectos")
    expectEq(m.projection.job?.id, jobA, "fin ajeno: la fila sigue")
}

private func ask(_ id: String) -> ApprovalRequest {
    ApprovalRequest(requestId: id, toolName: "run_shell", summary: "ls", inputJSON: "{}")
}

func testTheFirstApprovalIsNotInheritedByTheNextJob() {
    var m = running(jobA, "vuelos")
    _ = m.handle(.job(.started(goal: "hotel"), from: jobB))
    _ = m.handle(.job(.approvalRequested(ask("a1")), from: jobA))
    _ = m.handle(.approvalAnswered(requestId: "a1", approved: true, remember: false))
    _ = m.handle(.jobFinished(ok: true, from: jobA))
    _ = m.handle(.job(.approvalRequested(ask("b1")), from: jobB))
    let fx = m.handle(.approvalAnswered(requestId: "b1", approved: false, remember: false))
    expect(fx.contains(.cancelJobByID(jobB)), "permiso: negar la primera acción de B para B; el sí de A no cuenta")
}

func testALateApprovalOfAStoppedJobIsDenied() {
    var m = running(jobA, "vuelos")
    _ = m.handle(.stop)
    _ = m.handle(.pressed)
    let fx = m.handle(.job(.approvalRequested(ask("late")), from: jobA))
    expectEq(fx, [.resolveApproval(requestId: "late", approved: false, remember: false)],
             "parado: su permiso tardío se niega, aunque ya haya otro turno")
    expectEq(m.projection.approval, nil, "parado: y no abre la hoja")
}

/// Review 16h-2 round 3 (BLOCKER 1): the grant of a new bridge session is
/// nobody's job; refusing it while a job waits on its first approval must not
/// read as refusing that job's first action.
func testDenyingTheBridgeGrantWhileAJobRunsStopsNothing() {
    var m = running(jobA, "vuelos")
    let grant = ApprovalRequest(requestId: "g1", toolName: BridgePolicy.sessionApprovalTool,
                                summary: "Claude Code", inputJSON: "{}")
    _ = m.handle(.job(.approvalRequested(grant)))
    let fx = m.handle(.approvalAnswered(requestId: "g1", approved: false, remember: false))
    expect(!fx.contains(.cancelJob), "puente: negar la sesión no para el encargo (\(fx))")
    expectEq(m.projection.job?.id, jobA, "puente: la fila del encargo sigue")
}

/// X's request answered after Y took the row is X's, not Y's first action.
func testAnApprovalAnsweredAfterItsJobEndedDoesNotTouchTheNext() {
    var m = running(jobA, "vuelos")
    _ = m.handle(.job(.started(goal: "hotel"), from: jobB))
    _ = m.handle(.job(.approvalRequested(ask("a1")), from: jobA))
    _ = m.handle(.jobFinished(ok: true, from: jobA))
    let fx = m.handle(.approvalAnswered(requestId: "a1", approved: false, remember: false))
    expect(!fx.contains(.cancelJob), "dueño: negar lo de A no para a B (\(fx))")
    expectEq(m.projection.job?.id, jobB, "dueño: B sigue en la fila")
    _ = m.handle(.job(.approvalRequested(ask("b1")), from: jobB))
    let own = m.handle(.approvalAnswered(requestId: "b1", approved: false, remember: false))
    expect(own.contains(.cancelJobByID(jobB)), "dueño: la primera acción de B sigue siendo suya")
}

/// A request with no id is never a job's: a Stop left behind must not deny it.
func testAnUntaggedRequestAfterAStopIsNotDenied() {
    var m = running(jobA, "vuelos")
    _ = m.handle(.stop)
    let fx = m.handle(.job(.approvalRequested(ask("u1"))))
    expectEq(fx, [], "sin dueño: tras parar no se niega solo")
    expectEq(m.projection.approval?.requestId, "u1", "sin dueño: abre la hoja")
}

func testTheSheetOfTheActiveJobKeepsItsName() {
    var m = running(jobA, "vuelos")
    _ = m.handle(.job(.started(goal: "borrar la carpeta"), from: jobB))
    _ = m.handle(.job(.approvalRequested(ask("a1")), from: jobA))
    expectEq(m.projection.job?.goal, "vuelos", "hoja: el permiso de A aparece bajo el nombre de A")
}

func testStopClosesTheActiveAndTheQueuedRows() {
    var m = running(jobA, "vuelos")
    _ = m.handle(.job(.started(goal: "hotel"), from: jobB))
    let fx = m.handle(.stop)
    expect(fx.contains(.cancelJob), "parar: el freno")
    expectEq(m.projection.job, nil, "parar: sin fila activa")
    expect(m.projection.queued.isEmpty, "parar: ni en cola")
    _ = m.handle(.job(.stepStarted(tool: "Bash", summary: "rm"), from: jobB))
    expectEq(m.projection.job, nil, "parar: el encolado parado tampoco reabre nada")
}

// MARK: - one rule for what is in front: the job row or her turn

/// A turn of hers over a running job, up to thinking.
private func ownTurnOverJob() -> SessionMachine {
    var m = delegatingTurn()
    _ = m.handle(.pressed)
    _ = m.handle(voice(.listening))
    _ = m.handle(.released)
    _ = m.handle(voice(.thinking))
    return m
}

func testTheParentsHandsInsideAnOwnTurnOverAJobShowTheTurn() {
    var m = ownTurnOverJob()
    _ = m.handle(.parentActing(targets: ["Safari"]))
    expectEq(m.projection.kind, .processing(.toolExecuting), "manos: su turno actúa")
    _ = m.handle(.parentActed)
    expectEq(m.projection.kind, .processing(.thinking), "manos: vuelve a su turno, no a la fila del encargo")
}

func testACancelledPressOverAJobGoesBackToTheReply() {
    var m = delegatingTurn()
    _ = m.handle(.pressed)
    _ = m.handle(voice(.listening))
    _ = m.handle(.released)
    _ = m.handle(voice(.thinking))
    _ = m.handle(voice(.speaking))
    _ = m.handle(.pressedProvisionally)
    _ = m.handle(.holdCancelled)
    expectEq(m.projection.kind, .processing(.speaking), "tap cancelado: vuelve a la respuesta de su turno")
}

func testASecondStartedDuringAnOwnTurnKeepsTheTurnInFront() {
    var m = ownTurnOverJob()
    _ = m.handle(.job(.started(goal: "busca vuelos baratos en Safari")))
    expectEq(m.projection.kind, .processing(.thinking), "renombrar: su turno sigue delante")
    expectEq(m.projection.job?.goal, "busca vuelos baratos en Safari", "renombrar: el nombre sí cambia")
}

func testTheTurnFlagDiesWithTheJob() {
    var m = ownTurnOverJob()
    _ = m.handle(.jobFinished(ok: true))
    _ = m.handle(voice(.idle))
    _ = m.handle(.job(.started(goal: "otro")))
    _ = m.handle(voice(.thinking))
    expectEq(m.projection.kind, .processing(.subAgentRunning),
             "sin turno suyo abierto, un encargo nuevo manda sobre la voz pensando")
}

// MARK: - the reducer sees a notice (S2)

func testStopAtRestSilencesASoundingNotice() {
    var m = SessionMachine()
    _ = m.handle(.announcing(true))
    expect(m.projection.announcing, "aviso: la proyección sabe que suena")
    let fx = m.handle(.stop)
    expect(fx.contains(.cancelVoiceOutput), "aviso: Esc/botón en reposo callan el resumen (\(fx))")
    _ = m.handle(.announcing(false))
    expectEq(m.handle(.stop), [], "sin aviso, parar en reposo sigue sin hacer nada")
}

func testTheWarmSessionWaitsForTheNoticeBeforeHangingUp() {
    var m = SessionMachine()
    _ = m.handle(.voice(TurnSnapshot(state: .listening, pipeline: .realtime, muted: true, holdArmed: true)))
    _ = m.handle(.announcing(true))
    let fx = m.handle(.voiceIdleExpired)
    expect(!fx.contains(.hangUpVoice), "tibia: no cuelga mientras suena el aviso")
    expect(fx.contains(.scheduleVoiceIdleExpiry(SessionMachine.voiceIdleTimeout)), "tibia: lo vuelve a intentar después")
    _ = m.handle(.announcing(false))
    expect(m.handle(.voiceIdleExpired).contains(.hangUpVoice), "tibia: sin aviso, cuelga")
}
