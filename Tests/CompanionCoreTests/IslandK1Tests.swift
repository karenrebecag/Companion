import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// K1: the island closes on Incredible's settle, and the pointer pauses it.
// The reducer has no wall clock, so the pause is an effect the model runs.

private func clockEffects(_ effects: [SessionEffect]) -> [SessionEffect] {
    effects.filter {
        switch $0 {
        case .scheduleCompletedExpiry, .pauseCompletedExpiry, .resumeCompletedExpiry: true
        default: false
        }
    }
}

private func finished() -> (SessionMachine, [SessionEffect]) {
    var machine = SessionMachine()
    let effects = machine.handle(.typedReplyFinished)
    return (machine, effects)
}

@Test func k1AFinishedReplySettlesBriefly() {
    let (machine, effects) = finished()
    expectEq(machine.projection.kind, .processing(.completed), "K1: la respuesta terminó abierta")
    expect(effects.contains(.scheduleCompletedExpiry(SessionMachine.settleDelay, floor: SessionMachine.settleFloor)),
           "K1: el asentamiento es el breve, no el piso")
    expect(!effects.contains(.scheduleCompletedExpiry(SessionMachine.settleFloor, floor: nil)),
           "K1: terminar no arma el piso")
}

@Test func k1HoverPausesTheSettleAndLeaveResumes() {
    var (machine, _) = finished()
    expectEq(clockEffects(machine.handle(.hoverEntered)), [.pauseCompletedExpiry],
             "K1: el puntero pausa el asentamiento")
    expectEq(clockEffects(machine.handle(.hoverEntered)), [],
             "K1: un segundo aviso no rearma la pausa")
    expectEq(clockEffects(machine.handle(.hoverLeft)), [.resumeCompletedExpiry],
             "K1: al salir el plazo sigue")
    expectEq(clockEffects(machine.handle(.hoverLeft)), [],
             "K1: salir otra vez no arma un plazo nuevo")
    expectEq(machine.projection.kind, .processing(.completed), "K1: el hover no cierra la respuesta")
}

@Test func k1AReplyUnderThePointerStartsPaused() {
    var machine = SessionMachine()
    _ = machine.handle(.hoverEntered)
    _ = machine.handle(.typedSubmitted)
    let effects = machine.handle(.typedReplyFinished)
    expectEq(clockEffects(effects),
             [.scheduleCompletedExpiry(SessionMachine.settleDelay, floor: SessionMachine.settleFloor), .pauseCompletedExpiry],
             "K1: si el puntero ya está, el asentamiento nace pausado")
    expectEq(machine.projection.kind, .processing(.completed), "K1: y la isla sigue en la respuesta")
}

@Test func k1ADictationCardDoesNotSettle() {
    var machine = SessionMachine()
    _ = machine.handle(.pressed)
    _ = machine.handle(.released)
    let effects = machine.handle(.dictated(app: "Slack", text: "hola"))
    expect(effects.contains(.scheduleCompletedExpiry(SessionMachine.dictationCardDelay, floor: nil)),
           "K1: la tarjeta de dictado conserva su reloj")
    expect(!effects.contains(.scheduleCompletedExpiry(SessionMachine.settleDelay, floor: SessionMachine.settleFloor)),
           "K1: el asentamiento no corre sobre la tarjeta")
    expectEq(clockEffects(machine.handle(.hoverEntered)), [],
             "K1: el hover del panel no pausa la tarjeta")
}

@Test func k1AnEmptyDictationSettles() {
    var machine = SessionMachine()
    _ = machine.handle(.pressed)
    _ = machine.handle(.released)
    let effects = machine.handle(.dictated(app: "Slack", text: nil))
    expect(effects.contains(.scheduleCompletedExpiry(SessionMachine.settleDelay, floor: SessionMachine.settleFloor)),
           "K1: sin texto el dictado asienta como una respuesta")
    expect(!effects.contains(.scheduleCompletedExpiry(SessionMachine.dictationCardDelay, floor: nil)),
           "K1: sin texto no hay tarjeta")
}

@Test func k1ANewTurnCancelsTheSettle() {
    var pressed = finished().0
    let press = pressed.handle(.pressed)
    expectEq(pressed.projection.kind, .listening, "K1: pulsar abre la escucha")
    expect(clockEffects(press).isEmpty, "K1: pulsar no rearma el asentamiento")
    expect(!press.contains(.scheduleCompletedExpiry(SessionMachine.settleDelay, floor: SessionMachine.settleFloor)),
           "K1: pulsar no programa el asentamiento")

    var typed = finished().0
    let send = typed.handle(.typedSubmitted)
    expectEq(typed.projection.kind, .processing(.thinking), "K1: un envío abre el turno")
    expect(clockEffects(send).isEmpty, "K1: el turno empieza y el asentamiento no se arma")

    var thinking = finished().0
    let thought = thinking.handle(.voice(
        TurnSnapshot(state: .thinking, pipeline: .realtime, muted: false)))
    expectEq(thinking.projection.kind, .processing(.thinking), "K1: pensar abre")
    expect(clockEffects(thought).isEmpty, "K1: pensar no rearma el asentamiento")

    var speaking = finished().0
    let spoke = speaking.handle(.voice(
        TurnSnapshot(state: .speaking, pipeline: .realtime, muted: false)))
    expectEq(speaking.projection.kind, .processing(.speaking), "K1: hablar abre")
    expect(clockEffects(spoke).isEmpty, "K1: hablar no rearma el asentamiento")

    var acting = finished().0
    let act = acting.handle(.parentActing(targets: ["Notes"]))
    expectEq(acting.projection.kind, .processing(.toolExecuting), "K1: actuar abre")
    expect(clockEffects(act).isEmpty, "K1: actuar no rearma el asentamiento")
}

@Test func k1HoverWhileListeningDoesNotPause() {
    var machine = SessionMachine()
    _ = machine.handle(.pressed)
    expectEq(clockEffects(machine.handle(.hoverEntered)), [],
             "K1: escuchar no tiene asentamiento que pausar")
    expectEq(machine.projection.kind, .listening, "K1: el hover no cambia la escucha")
    expectEq(clockEffects(machine.handle(.hoverLeft)), [],
             "K1: salir mientras se escucha no reanuda un reloj")
}

@Test func k1R2TypedSendOpensTheIslandInTheSameReduce() {
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    expectEq(machine.projection.kind, .processing(.thinking), "K1: el envío abre el turno ya")
    expect(IslandState.from(machine.projection, pebbleHidden: true).size != .hidden,
           "K1: la isla está abierta en el mismo reduce, sin retener nada")
}

@Test func k1R2ANoticeBlocksTheSettle() {
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    _ = machine.handle(.connectAppSuggested(slug: "slack", name: "Slack"))
    let effects = machine.handle(.typedReplyFinished)
    expect(machine.projection.notice != nil, "K1: el aviso sigue en pantalla")
    expectEq(machine.projection.kind, .processing(.completed), "K1: la respuesta terminó")
    expect(!effects.contains(.scheduleCompletedExpiry(SessionMachine.settleDelay, floor: SessionMachine.settleFloor)),
           "K1: con un aviso no se arma el asentamiento")
}

@Test func k1R2ASheetBlocksTheSettle() {
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    let request = ApprovalRequest(
        requestId: "r", toolName: "run_shell", summary: "ls", inputJSON: "{}")
    _ = machine.handle(.job(.approvalRequested(request)))
    let effects = machine.handle(.typedReplyFinished)
    expect(machine.projection.approval != nil, "K1: la hoja sigue en pantalla")
    expectEq(machine.projection.kind, .processing(.completed), "K1: la respuesta terminó")
    expect(!effects.contains(.scheduleCompletedExpiry(SessionMachine.settleDelay, floor: SessionMachine.settleFloor)),
           "K1: con una hoja no se arma el asentamiento")
}

@Test func k1R2AnAnswerNeverOpenedDoesNotBlockTheSettle() {
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    let card = Card(payload: .gallery(GalleryBlock(images: [])), source: .tool)
    _ = machine.handle(.job(.card(card)))
    let effects = machine.handle(.typedReplyFinished)
    expectEq(machine.projection.kind, .processing(.completed), "K1: la respuesta terminó")
    expect(effects.contains(settle),
           "K1: una respuesta que nadie abrió no sostiene la isla (solo la tarjeta expandida)")
}

@Test func k1R2AnOpenAnswerBlocksTheSettle() {
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    _ = machine.handle(.answerOpened)
    let effects = machine.handle(.typedReplyFinished)
    expect(!effects.contains(settle), "K1: con la respuesta abierta no se arma el asentamiento")
}

@Test func k1R2IdleClosedNegatives() {
    func closed(_ size: IslandState.Size) -> Bool { size == .hidden || size == .pebble }
    let idle = SessionProjection()
    expect(closed(IslandState.from(idle, pebbleHidden: true).size),
           "K1: idle, sin aviso, hoja, adjuntos ni turno, escondida está cerrada")
    expect(closed(IslandState.from(idle, pebbleHidden: false).size),
           "K1: idle, sin aviso, hoja, adjuntos ni turno, el pebble está cerrado")

    var notice = idle
    notice.notice = .couldntHear
    expect(!closed(IslandState.from(notice, pebbleHidden: true).size),
           "K1: un aviso no está cerrado")

    var sheet = idle
    sheet.approvalQueue = [ApprovalRequest(
        requestId: "r", toolName: "run_shell", summary: "ls", inputJSON: "{}")]
    expect(!closed(IslandState.from(sheet, pebbleHidden: true).size),
           "K1: una hoja no está cerrada")

    expect(!closed(IslandState.from(idle, pebbleHidden: true, composing: true).size),
           "K1: unos adjuntos no están cerrados")

    var turn = idle
    turn.kind = .processing(.thinking)
    expect(!closed(IslandState.from(turn, pebbleHidden: true).size),
           "K1: un turno no está cerrado")
}

private let settle = SessionEffect.scheduleCompletedExpiry(
    SessionMachine.settleDelay, floor: SessionMachine.settleFloor)

private func sheet() -> ApprovalRequest {
    ApprovalRequest(requestId: "r", toolName: "run_shell", summary: "ls", inputJSON: "{}")
}

@Test func k1R3TheSettleRearmsWhenTheNoticeExpires() {
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    _ = machine.handle(.connectAppSuggested(slug: "slack", name: "Slack"))
    _ = machine.handle(.typedReplyFinished)
    let effects = machine.handle(.noticeExpired(.connectApp(slug: "slack", name: "Slack")))
    expectEq(machine.projection.notice, nil, "K1: el aviso se fue")
    expect(effects.contains(settle), "K1: al irse el último bloqueo el asentamiento se arma")
}

@Test func k1R3TheSettleRearmsWhenTheNoticeIsDismissed() {
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    _ = machine.handle(.connectAppSuggested(slug: "slack", name: "Slack"))
    _ = machine.handle(.typedReplyFinished)
    let effects = machine.handle(.noticeDismissed)
    expect(effects.contains(settle), "K1: cerrar el aviso arma el asentamiento")
}

@Test func k1R3TheSettleRearmsWhenTheSheetIsAnswered() {
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    _ = machine.handle(.job(.approvalRequested(sheet())))
    _ = machine.handle(.typedReplyFinished)
    let effects = machine.handle(.approvalAnswered(requestId: "r", approved: true, remember: false))
    expect(effects.contains(settle), "K1: contestar la hoja arma el asentamiento")
}

@Test func k1R3TheSettleRearmsWhenTheAnswerCloses() {
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    _ = machine.handle(.answerOpened)
    _ = machine.handle(.typedReplyFinished)
    let effects = machine.handle(.answerClosed)
    expect(effects.contains(settle), "K1: cerrar la respuesta arma el asentamiento")
    expect(machine.handle(.answerClosed).isEmpty, "K1: cerrarla otra vez no arma otro reloj")
}

@Test func k1R3AnotherBlockerKeepsTheSettleDisarmed() {
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    _ = machine.handle(.connectAppSuggested(slug: "slack", name: "Slack"))
    _ = machine.handle(.job(.approvalRequested(sheet())))
    _ = machine.handle(.typedReplyFinished)
    let effects = machine.handle(.noticeDismissed)
    expect(!effects.contains(settle), "K1: la hoja sigue bloqueando")
}

@Test func k1R3TheRearmedSettleUnderThePointerStartsPaused() {
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    _ = machine.handle(.connectAppSuggested(slug: "slack", name: "Slack"))
    _ = machine.handle(.typedReplyFinished)
    _ = machine.handle(.hoverEntered)
    let effects = machine.handle(.noticeDismissed)
    expectEq(clockEffects(effects), [settle, .pauseCompletedExpiry],
             "K1: con el puntero encima el asentamiento nace pausado")
}

@Test func k1R3ALostCardHoverOutIsRecoveredByThePanelLeave() {
    var notice = SessionMachine()
    _ = notice.handle(.connectAppSuggested(slug: "slack", name: "Slack"))
    _ = notice.handle(.noticeCardHover(true))
    expect(notice.handle(.hoverLeft).contains(.resumeNoticeExpiry),
           "K1: salir del panel reanuda el aviso")
    expect(!notice.handle(.hoverLeft).contains(.resumeNoticeExpiry), "K1: solo una vez")

    var card = SessionMachine()
    _ = card.handle(.pressed)
    _ = card.handle(.released)
    _ = card.handle(.dictated(app: "Slack", text: "hola"))
    _ = card.handle(.dictationCardHover(true))
    expect(card.handle(.hoverLeft).contains(.resumeCompletedExpiry),
           "K1: salir del panel reanuda la tarjeta de dictado")
}

@Test func k1R3AnApprovalArrivingDuringTheSettleKeepsTheIslandOpen() {
    var machine = finished().0
    _ = machine.handle(.job(.approvalRequested(sheet())))
    _ = machine.handle(.completedTimerExpired)
    expectEq(machine.projection.kind, .processing(.completed),
             "K1: la hoja pendiente no se cierra por el temporizador")
    let effects = machine.handle(.approvalAnswered(requestId: "r", approved: true, remember: false))
    expect(effects.contains(settle), "K1: contestar la hoja rearma el asentamiento")
}

private func completedBehindASheet(owner: JobID? = nil) -> SessionMachine {
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    _ = machine.handle(.job(.approvalRequested(sheet()), from: owner))
    _ = machine.handle(.typedReplyFinished)
    return machine
}

@Test func k1R3TheSettleRearmsWhenTheSheetIsSettledElsewhere() {
    var machine = completedBehindASheet()
    let effects = machine.handle(.approvalSettled(requestId: "r"))
    expect(effects.contains(settle), "K1: una hoja contestada en otra parte arma el asentamiento")
}

@Test func k1R3TheSettleRearmsWhenTheSheetIsDropped() {
    var machine = completedBehindASheet()
    let effects = machine.handle(.approvalDropped(requestId: "r"))
    expect(effects.contains(settle), "K1: una hoja abandonada arma el asentamiento")
}

@Test func k1R3TheSettleRearmsWhenTheJobThatAskedFinishes() {
    let owner = JobID("j")
    var machine = completedBehindASheet(owner: owner)
    let effects = machine.handle(.jobFinished(ok: true, from: owner))
    expectEq(machine.projection.approval, nil, "K1: la hoja del encargo se fue")
    expect(effects.contains(settle), "K1: terminar el encargo que preguntaba arma el asentamiento")
}

// Round 4.

private func dictationCard() -> SessionMachine {
    var machine = SessionMachine()
    _ = machine.handle(.pressed)
    _ = machine.handle(.released)
    _ = machine.handle(.dictated(app: "Slack", text: "hola"))
    return machine
}

@Test func k1R4TheDictationCardStillExpiresBehindASheet() {
    var machine = dictationCard()
    _ = machine.handle(.job(.approvalRequested(sheet())))
    _ = machine.handle(.completedTimerExpired)
    expectEq(machine.projection.kind, .idle, "K1: la tarjeta caduca aunque haya una hoja")
    expectEq(machine.projection.dictatedText, nil, "K1: y suelta las palabras")

    var copied = dictationCard()
    _ = copied.handle(.dictationCardCopied)
    _ = copied.handle(.job(.approvalRequested(sheet())))
    _ = copied.handle(.completedTimerExpired)
    expectEq(copied.projection.kind, .idle, "K1: copiar y una hoja no dejan la tarjeta permanente")
}

@Test func k1R4ANoticeDuringTheSettleKeepsTheIslandOpen() {
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    _ = machine.handle(.typedReplyFinished)
    _ = machine.handle(.hoverEntered)
    _ = machine.handle(.connectAppSuggested(slug: "slack", name: "Slack"))
    _ = machine.handle(.hoverLeft)
    _ = machine.handle(.completedTimerExpired)
    expectEq(machine.projection.kind, .processing(.completed), "K1: el aviso sostiene la isla")
    expect(machine.projection.notice != nil, "K1: y el aviso sigue a la vista")
}

@Test func k1R4AnOpenAnswerSurvivesTheSettleTimer() {
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    _ = machine.handle(.typedReplyFinished)
    _ = machine.handle(.answerOpened)
    _ = machine.handle(.completedTimerExpired)
    expectEq(machine.projection.kind, .processing(.completed), "K1: la respuesta abierta sostiene la isla")
    expect(machine.handle(.answerClosed).contains(settle), "K1: cerrarla arma el asentamiento")
}

@Test func k1R4AJobFinishingBehindASheetArmsTheSettleOnce() {
    let owner = JobID("j")
    var machine = SessionMachine()
    _ = machine.handle(.job(.started(goal: "x"), from: owner))
    _ = machine.handle(.job(.approvalRequested(sheet()), from: owner))
    let effects = machine.handle(.jobFinished(ok: true, from: owner))
    expectEq(effects.filter { $0 == settle }.count, 1, "K1: un solo asentamiento")
}

@Test func k1R4AForeignJobFinishedDoesNotDisturbTheTurn() {
    let running = JobID("a")
    let foreign = JobID("b")
    let phases: [(String, (inout SessionMachine) -> Void)] = [
        ("listening", { _ = $0.handle(.pressed) }),
        ("thinking", { _ = $0.handle(.typedSubmitted) }),
        ("speaking", { m in
            _ = m.handle(.typedSubmitted)
            _ = m.handle(.typedReplyStreaming)
        }),
    ]
    for (name, enter) in phases {
        var machine = SessionMachine()
        _ = machine.handle(.job(.started(goal: "x"), from: running))
        enter(&machine)
        let kind = machine.projection.kind
        let job = machine.projection.job
        let effects = machine.handle(.jobFinished(ok: true, from: foreign))
        expectEq(machine.projection.kind, kind, "K1: \(name): el tipo no cambia")
        expectEq(machine.projection.job, job, "K1: \(name): el encargo en curso sigue")
        expectEq(effects, [], "K1: \(name): un fin ajeno no emite nada")
    }

    var armed = finished().0
    let again = armed.handle(.jobFinished(ok: true, from: foreign))
    expect(!again.contains(settle), "K1: con el asentamiento armado no hay un segundo")

    var behind = SessionMachine()
    _ = behind.handle(.typedSubmitted)
    _ = behind.handle(.connectAppSuggested(slug: "slack", name: "Slack"))
    _ = behind.handle(.typedReplyFinished)
    let quiet = behind.handle(.jobFinished(ok: true, from: foreign))
    expect(behind.projection.notice != nil, "K1: el aviso sigue")
    expect(!quiet.contains(settle), "K1: tras un aviso no se arma el asentamiento")
}

@Test func k1R4AHoverLeaveWithoutEnterIsHarmless() {
    var machine = SessionMachine()
    let effects = machine.handle(.hoverLeft)
    expectEq(machine.projection.kind, .idle, "K1: salir sin haber entrado no cambia el tipo")
    expectEq(effects, [], "K1: ni emite ningún efecto")

    var card = dictationCard()
    _ = card.handle(.dictationCardHover(true))
    expect(card.handle(.hoverLeft).contains(.resumeCompletedExpiry),
           "K1: ese mismo salir libera una tarjeta retenida")
}

@Test func k1R4TheDictationLeaveResumesOnlyOnce() {
    var machine = dictationCard()
    _ = machine.handle(.dictationCardHover(true))
    expect(machine.handle(.hoverLeft).contains(.resumeCompletedExpiry), "K1: la primera reanuda")
    expect(!machine.handle(.hoverLeft).contains(.resumeCompletedExpiry), "K1: la segunda no")
    expect(!machine.handle(.dictationCardHover(false)).contains(.resumeCompletedExpiry),
           "K1: el aviso de la tarjeta después tampoco reanuda otra vez")
}

@Test func k1R4ANoticeIsWhatCompletedShows() {
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    _ = machine.handle(.connectAppSuggested(slug: "slack", name: "Slack"))
    _ = machine.handle(.typedReplyFinished)
    _ = machine.handle(.completedTimerExpired)
    expectEq(machine.projection.kind, .processing(.completed), "K1: el aviso sostiene la isla")
    let state = IslandState.from(machine.projection, pebbleHidden: false)
    expectEq(state.line, .connectApp(slug: "slack", name: "Slack"),
             "K1: sosteniéndola, la isla muestra el aviso y no un «listo» que lo tape")
}

// Round 5.

@Test func k1R5TheReceiptSurvivesAJobDuringCompleted() {
    let receipt = ActionReceipt(lines: ["Abrí Safari."])!
    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    _ = machine.handle(.parentActing(targets: ["Safari"]))
    _ = machine.handle(.receipt(receipt))
    _ = machine.handle(.parentActed)
    _ = machine.handle(.typedReplyFinished)
    _ = machine.handle(.job(.started(goal: "ordenar")))
    _ = machine.handle(.jobFinished(ok: true))
    _ = machine.handle(.completedTimerExpired)
    expectEq(machine.projection.notice, .receipt(receipt),
             "K1: el recibo del turno sale aunque un encargo corriera en Completed")
}

@Test func k1R5OnlyAnOpenIslandPlaysTheBridgeOut() {
    expect(!SessionKind.processing(.completed).isUsersTurn,
           "K1: Completed es asentarse, no un turno: no pausa el puente")
    for phase: SessionPhase in [.pending, .thinking, .speaking, .toolExecuting, .subAgentRunning] {
        expect(SessionKind.processing(phase).isUsersTurn, "K1: \(phase) sigue siendo turno")
    }
}

@Test func k1R5ACardOutranksTheNoticeAndTheSheetOutranksBoth() {
    var card = dictationCard()
    _ = card.handle(.connectAppSuggested(slug: "slack", name: "Slack"))
    let shown = IslandState.from(card.projection, pebbleHidden: false)
    expectEq(shown.line, .dictationResult(app: "Slack", text: card.projection.dictatedText!),
             "K1: la tarjeta de dictado se muestra, no el aviso")

    var machine = SessionMachine()
    _ = machine.handle(.typedSubmitted)
    _ = machine.handle(.connectAppSuggested(slug: "slack", name: "Slack"))
    _ = machine.handle(.job(.approvalRequested(sheet())))
    _ = machine.handle(.typedReplyFinished)
    let state = IslandState.from(machine.projection, pebbleHidden: false)
    expect(state.approval != nil, "K1: la hoja manda sobre el aviso")
}

@Test func k1R5CompletedWithNothingHeldIsHarmlessToLeave() {
    var machine = finished().0
    expectEq(machine.handle(.hoverLeft), [], "K1: salir en Completed sin puntero ni bloqueo no emite nada")
}
