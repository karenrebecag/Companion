import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// P1: Incredible's presence (referencia local: `passive_after_secs`, default 600, and
// `presence` active/passive in its session state). After that long with no interaction
// the companion goes passive; any interaction brings it back. 0 means never.

private func armed(_ effects: [SessionEffect]) -> (TimeInterval, Int)? {
    for effect in effects {
        if case .schedulePassive(let delay, let armedFor) = effect { return (delay, armedFor) }
    }
    return nil
}

/// A machine that has already gone passive, with the arm it went passive on.
private func passiveMachine() -> SessionMachine {
    var machine = SessionMachine()
    let arm = armed(machine.handle(.passiveAfterChanged(SessionMachine.defaultPassiveAfter)))
    _ = machine.handle(.passiveExpired(armedFor: arm?.1 ?? -1))
    return machine
}

@Test func theCompanionStartsActiveAndWaitsTenMinutesByDefault() {
    expectEq(SessionMachine().projection.presence, .active, "arranca activo")
    expectEq(SessionMachine.defaultPassiveAfter, 600, "como Incredible: 600 s")
}

@Test func theSettingArmsTheWaitAndItsEndMakesThePassive() {
    var machine = SessionMachine()
    let arm = armed(machine.handle(.passiveAfterChanged(600)))
    expectEq(arm?.0, 600, "el ajuste arma la espera")
    expectEq(machine.projection.presence, .active, "armar no cambia nada todavia")
    _ = machine.handle(.passiveExpired(armedFor: arm?.1 ?? -1))
    expectEq(machine.projection.presence, .passive, "sin interaccion, pasivo")
}

@Test func anyInteractionBringsItBackAndWaitsAgain() {
    let interactions: [SessionEvent] = [
        .pressed, .pressedProvisionally, .tapped, .hoverEntered, .typedSubmitted,
        .stop, .stopVoice, .noticeDismissed, .dictationCardHover(true), .dictationCardCopied,
        // Review (P1): answering a sheet by click or out loud, undoing, waving the card
        // away, the hold's own edges and the user's words in the ear are all the user.
        .approvalAnswered(requestId: "r", approved: true, remember: false),
        .approvalSpoken(requestId: "r", approved: false), .undoPressed(id: UUID()),
        .dictationHidden, .released, .holdConfirmed, .holdCancelled, .partialTranscript("hola"),
    ]
    for interaction in interactions {
        var machine = passiveMachine()
        expectEq(machine.projection.presence, .passive, "\(interaction): partia pasivo")
        let arm = armed(machine.handle(interaction))
        expectEq(machine.projection.presence, .active, "\(interaction): vuelve a activo")
        expectEq(arm?.0, SessionMachine.defaultPassiveAfter, "\(interaction): y la espera empieza de nuevo")
    }
}

@Test func whatTheCompanionDoesOnItsOwnIsNotAnInteraction() {
    let ownActivity: [SessionEvent] = [
        .typedReplyFinished, .completedTimerExpired, .handsWorking(target: nil), .handsActed,
        .voiceIdleExpired, .job(.stepStarted(tool: "buscar", summary: "busca")), .jobFinished(ok: true),
        .parentActed, .approvalSettled(requestId: "r"),
    ]
    for event in ownActivity {
        var machine = passiveMachine()
        let arm = armed(machine.handle(event))
        expectEq(machine.projection.presence, .passive, "\(event): sigue pasivo")
        expect(arm == nil, "\(event): no rearma la espera")
    }
}

@Test func aWaitThatAnInteractionReplacedNeverMakesItPassive() {
    var machine = SessionMachine()
    let first = armed(machine.handle(.passiveAfterChanged(600)))
    let second = armed(machine.handle(.tapped))
    expect(first?.1 != second?.1, "cada espera tiene su propia marca")
    _ = machine.handle(.passiveExpired(armedFor: first?.1 ?? -1))
    expectEq(machine.projection.presence, .active, "la espera vieja llega tarde y no cuenta")
    _ = machine.handle(.passiveExpired(armedFor: second?.1 ?? -1))
    expectEq(machine.projection.presence, .passive, "la vigente si")
}

@Test func zeroMeansNever() {
    var machine = SessionMachine()
    let pending = armed(machine.handle(.passiveAfterChanged(600)))
    let effects = machine.handle(.passiveAfterChanged(0))
    expect(armed(effects) == nil, "con 0 no se arma nada")
    _ = machine.handle(.passiveExpired(armedFor: pending?.1 ?? -1))
    expectEq(machine.projection.presence, .active, "y la espera que habia ya no cuenta")
    expect(armed(machine.handle(.tapped)) == nil, "ni una interaccion la arma")
}

@Test func turningItOffWhilePassiveComesBack() {
    var machine = passiveMachine()
    _ = machine.handle(.passiveAfterChanged(0))
    expectEq(machine.projection.presence, .active, "con 0 nunca esta pasivo")
}

// QA review (P1): a new wait replaces the running one, and changing it wakes.
@Test func aNewWaitReplacesTheOneRunning() {
    var machine = SessionMachine()
    let long = armed(machine.handle(.passiveAfterChanged(600)))
    let short = armed(machine.handle(.passiveAfterChanged(30)))
    expectEq(short?.0, 30, "la espera nueva")
    expect(long?.1 != short?.1, "con su propia marca")
    _ = machine.handle(.passiveExpired(armedFor: long?.1 ?? -1))
    expectEq(machine.projection.presence, .active, "la de 600 ya no cuenta")
    _ = machine.handle(.passiveExpired(armedFor: short?.1 ?? -1))
    expectEq(machine.projection.presence, .passive, "la de 30 si")
    _ = machine.handle(.passiveAfterChanged(120))
    expectEq(machine.projection.presence, .active, "cambiar el ajuste es una interaccion: despierta")
}

// Security and QA review (P1): what reaches the reducer is bounded there too: nothing
// negative or undefined arms a wait, and nothing longer than a day reaches the clock.
@Test func theWaitIsNeverNegativeUndefinedOrEndless() {
    for never in [-5.0, .nan, .infinity, -.infinity] {
        var machine = SessionMachine()
        expect(armed(machine.handle(.passiveAfterChanged(never))) == nil, "\(never): nunca")
    }
    var machine = SessionMachine()
    expectEq(armed(machine.handle(.passiveAfterChanged(1e308)))?.0, SessionMachine.maxPassiveAfter,
             "una espera enorme se corta a un dia")
    expectEq(SessionMachine.maxPassiveAfter, 86_400, "un dia")
}

// Code review (P2): a turn in progress is never collapsed by the wait running out; the
// wait starts over and the user's turn keeps its island.
@Test func theWaitNeverEndsDuringATurn() {
    var machine = SessionMachine()
    _ = machine.handle(.passiveAfterChanged(30))
    let current = armed(machine.handle(.typedSubmitted))
    let during = armed(machine.handle(.passiveExpired(armedFor: current?.1 ?? -1)))
    expectEq(machine.projection.presence, .active, "con un turno en curso sigue activo")
    expectEq(during?.0, 30, "y la espera vuelve a empezar")
}

// QA review (P2): the same while the user is still talking.
@Test func theWaitNeverEndsWhileListening() {
    var machine = SessionMachine()
    _ = machine.handle(.passiveAfterChanged(30))
    let current = armed(machine.handle(.pressed))
    let during = armed(machine.handle(.passiveExpired(armedFor: current?.1 ?? -1)))
    expectEq(machine.projection.presence, .active, "escuchando, sigue activo")
    expectEq(during?.0, 30, "y la espera vuelve a empezar")
}
