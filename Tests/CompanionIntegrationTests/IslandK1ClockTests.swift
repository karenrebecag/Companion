import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

/// The settle clock. `now` is injected so a pause can outlast the 0.2 s
/// without the reply closing, and a leave can arm the floor instead of the
/// short remainder.
private final class StepClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t: TimeInterval = 0
    func now() -> TimeInterval { lock.withLock { t } }
    func advance(_ seconds: TimeInterval) { lock.withLock { t += seconds } }
}

@MainActor private func finish(_ session: SessionModel) {
    session.send(.typedSubmitted)
    session.send(.typedReplyFinished)
}

@MainActor private func dictated(_ session: SessionModel) {
    session.send(.pressed)
    session.send(.released)
    session.send(.dictated(app: "Slack", text: "hola"))
}

@Test @MainActor func k1LeaveAppliesTheFloor() async {
    let clock = StepClock()
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep, now: clock.now)
    finish(session)
    await pumpUntil("K1: asentamiento") { sleeper.armed(SessionMachine.settleDelay) == 1 }
    let elapsed: TimeInterval = 0.05
    clock.advance(elapsed)
    session.send(.hoverEntered)
    session.send(.hoverLeft)
    await pumpUntil("K1: al salir queda el piso") {
        sleeper.armed(near: SessionMachine.settleFloor, tolerance: 0.05) == 1
    }
    expectEq(sleeper.armed(near: SessionMachine.settleDelay - elapsed, tolerance: 0.01), 0,
             "K1: salir no reanuda el resto corto")
    expectEq(session.projection.kind, .processing(.completed), "K1: el piso no cierra ya")
    sleeper.fire()
    await pumpUntil("K1: cumplido el piso se cierra") { session.projection.kind == .idle }

    finish(session)
    await pumpUntil("K1: segundo asentamiento") { sleeper.armed(SessionMachine.settleDelay) == 2 }
    session.send(.hoverEntered)
    session.send(.hoverLeft)
    await pumpUntil("K1: primer piso del segundo ciclo") {
        sleeper.armed(near: SessionMachine.settleFloor, tolerance: 0.05) == 2
    }
    clock.advance(0.4)
    session.send(.hoverEntered)
    session.send(.hoverLeft)
    await pumpUntil("K1: un segundo salir vuelve a dejar el piso") {
        sleeper.armed(near: SessionMachine.settleFloor, tolerance: 0.05) == 3
    }
    expectEq(sleeper.armed(near: SessionMachine.settleFloor - 0.4, tolerance: 0.01), 0,
             "K1: el segundo salir no deja el resto por debajo del piso")
}

@Test @MainActor func k1APointerAlreadyTherePausesThenLeavesAtTheFloor() async {
    let clock = StepClock()
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep, now: clock.now)
    session.send(.hoverEntered)
    finish(session)
    expectEq(session.projection.kind, .processing(.completed), "K1: bajo el puntero no se cierra")
    session.send(.hoverLeft)
    await pumpUntil("K1: al salir queda el piso") {
        sleeper.armed(near: SessionMachine.settleFloor, tolerance: 0.05) == 1
    }
}

@MainActor private func pausedSettle(_ session: SessionModel, _ sleeper: ManualSleeper) async {
    finish(session)
    await pumpUntil("K1: asentamiento") { sleeper.armed(SessionMachine.settleDelay) == 1 }
    session.send(.hoverEntered)
}

@Test @MainActor func k1R2ADictationLeaveKeepsTheRemainder() async {
    let clock = StepClock()
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep, now: clock.now)
    session.send(.pressed)
    session.send(.released)
    session.send(.dictated(app: "Slack", text: "hola"))
    await pumpUntil("K1: la tarjeta") { sleeper.armed(SessionMachine.dictationCardDelay) == 1 }
    let elapsed: TimeInterval = 0.4
    clock.advance(elapsed)
    session.send(.dictationCardHover(true))
    session.send(.dictationCardHover(false))
    let left = SessionMachine.dictationCardDelay - elapsed
    await pumpUntil("K1: la tarjeta sigue con su resto") {
        sleeper.armed(near: left, tolerance: 0.05) == 1
    }
    expectEq(sleeper.armed(near: SessionMachine.settleFloor, tolerance: 0.05), 0,
             "K1: salir de la tarjeta no arma el piso")
}

@Test @MainActor func k1R2ATextlessCompletedGetsTheFloor() async {
    let clock = StepClock()
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep, now: clock.now)
    finish(session)
    await pumpUntil("K1: asentamiento sin texto") { sleeper.armed(SessionMachine.settleDelay) == 1 }
    clock.advance(0.05)
    session.send(.hoverEntered)
    session.send(.hoverLeft)
    await pumpUntil("K1: sin texto queda el piso") {
        sleeper.armed(near: SessionMachine.settleFloor, tolerance: 0.05) == 1
    }
}

/// After `fire()` the waiters are gone, so `pending == 0` says nothing about
/// whether the cancelled timer task ran. A bounded settle lets it run, and
/// the leave that follows is the positive signal: it must arm nothing.
@MainActor private func assertSettleStaysDead(
    _ session: SessionModel, _ sleeper: ManualSleeper, _ label: String
) async {
    sleeper.fire()
    await settle(0.2)
    expect(session.projection.kind != .idle, "\(label): un turno nuevo no vuelve a idle")
    let delays = sleeper.delays.count
    let left = session.send(.hoverLeft)
    await settle(0.2)
    expect(left.filter { if case .resumeCompletedExpiry = $0 { true } else { false } }.isEmpty,
           "\(label): salir después no reanuda el asentamiento")
    expectEq(sleeper.delays.count, delays, "\(label): salir después no arma ningún plazo")
    expectEq(sleeper.armed(near: SessionMachine.settleFloor, tolerance: 0.05), 0,
             "\(label): ni el piso")
    // Positive control on the same session: the clock machinery is alive, so
    // the silence above was the reducer's decision and not a dead timer.
    finish(session)
    await pumpUntil("\(label): control, el asentamiento se arma") {
        sleeper.armed(SessionMachine.settleDelay) == 2
    }
    sleeper.fire()
    await pumpUntil("\(label): control, cumplido se cierra") { session.projection.kind == .idle }
}

@Test @MainActor func k1R2ANewTurnCancelsAPausedSettle() async {
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep, now: StepClock().now)
    await pausedSettle(session, sleeper)
    session.send(.pressed)
    expectEq(session.projection.kind, .listening, "K1: pulsar abre la escucha")
    await assertSettleStaysDead(session, sleeper, "K1 pulsar")

    let again = ManualSleeper()
    let typed = SessionModel(jobs: nil, approvals: nil, sleep: again.sleep, now: StepClock().now)
    await pausedSettle(typed, again)
    typed.send(.typedSubmitted)
    expectEq(typed.projection.kind, .processing(.thinking), "K1: un envío abre el turno")
    await assertSettleStaysDead(typed, again, "K1 envío")
}

@Test @MainActor func k1R2APauseWithoutLeaveStaysPaused() async {
    let clock = StepClock()
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep, now: clock.now)
    finish(session)
    await pumpUntil("K1: asentamiento") { sleeper.armed(SessionMachine.settleDelay) == 1 }
    let armed = sleeper.delays.count
    session.send(.hoverEntered)
    clock.advance(120)
    await settle(0.2)
    expectEq(sleeper.delays.count, armed, "K1: una pausa sin salida no arma otro plazo")
    expectEq(session.projection.kind, .processing(.completed), "K1: el asentamiento sigue")
    expectEq(sleeper.armed(near: SessionMachine.settleFloor, tolerance: 0.05), 0,
             "K1: sin salir no queda el piso")
    // Positive control: the same pause, once released, does close.
    session.send(.hoverLeft)
    await pumpUntil("K1: control, al salir queda el piso") {
        sleeper.armed(near: SessionMachine.settleFloor, tolerance: 0.05) == 1
    }
    sleeper.fire()
    await pumpUntil("K1: control, cumplido el piso se cierra") { session.projection.kind == .idle }
}

// The pause has no ceiling: an hour under the pointer closes nothing, and the
// pointer leaving is what lets the clock run again.
@Test @MainActor func k1R3ThePausedSettleHasNoCeiling() async {
    let clock = StepClock()
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep, now: clock.now)
    finish(session)
    await pumpUntil("K1: asentamiento") { sleeper.armed(SessionMachine.settleDelay) == 1 }
    session.send(.hoverEntered)
    clock.advance(120)
    sleeper.fire()
    await settle(0.2)
    expectEq(session.projection.kind, .processing(.completed), "K1: la pausa no caduca")
    session.send(.hoverLeft)
    await pumpUntil("K1: al salir se arma el piso") {
        sleeper.armed(near: SessionMachine.settleFloor, tolerance: 0.05) == 1
    }
    sleeper.fire()
    await pumpUntil("K1: cumplido el piso se cierra") { session.projection.kind == .idle }
}

@Test @MainActor func k1R3TheDictationCardHasNoCeilingAndTheLeaveBackstopsIt() async {
    let clock = StepClock()
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep, now: clock.now)
    dictated(session)
    await pumpUntil("K1: la tarjeta") { sleeper.armed(SessionMachine.dictationCardDelay) == 1 }
    session.send(.dictationCardHover(true))
    clock.advance(120)
    sleeper.fire()
    await settle(0.2)
    expectEq(session.projection.kind, .processing(.completed), "K1: la tarjeta pausada no caduca")
    expectEq(session.projection.dictatedText, "hola", "K1: y conserva las palabras")
    session.send(.hoverLeft)
    await pumpUntil("K1: salir del panel reanuda la tarjeta") {
        sleeper.armed(near: SessionMachine.dictationCardDelay, tolerance: 0.05) == 2
    }
    sleeper.fire()
    await pumpUntil("K1: cumplido el plazo se cierra") { session.projection.kind == .idle }
}

@Test @MainActor func k1R3TheNoticeHasNoCeilingAndTheLeaveBackstopsIt() async {
    let clock = StepClock()
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep, now: clock.now)
    session.send(.pressed)
    session.send(.released)
    session.send(.heardNothing)
    await pumpUntil("K1: el aviso") { sleeper.armed(SessionMachine.noticeDelay) == 1 }
    session.send(.noticeCardHover(true))
    clock.advance(120)
    sleeper.fire()
    await settle(0.2)
    expectEq(session.projection.notice, .couldntHear, "K1: el aviso pausado no caduca")
    session.send(.hoverLeft)
    await pumpUntil("K1: salir del panel reanuda el aviso") {
        sleeper.armed(near: SessionMachine.noticeDelay, tolerance: 0.05) == 2
    }
    sleeper.fire()
    await pumpUntil("K1: cumplido el plazo se va") { session.projection.notice == nil }
}

@Test @MainActor func k1R5ANoticeDuringTheSettleIsNotClosedByTheLeave() async {
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep, now: StepClock().now)
    finish(session)
    await pumpUntil("K1: asentamiento") { sleeper.armed(SessionMachine.settleDelay) == 1 }
    session.send(.hoverEntered)
    session.send(.connectAppSuggested(slug: "slack", name: "Slack"))
    let leave = session.send(.hoverLeft)
    expect(leave.filter { if case .scheduleCompletedExpiry = $0 { true } else { false } }.isEmpty,
           "K1: salir con un aviso no arma el piso")
    await settle(0.2)
    expectEq(sleeper.armed(near: SessionMachine.settleFloor, tolerance: 0.05), 0,
             "K1: ningún piso se armó bajo el aviso")
    sleeper.fire()
    await settle(0.2)
    expectEq(session.projection.kind, .processing(.completed), "K1: el aviso sigue sosteniendo la isla")
}
