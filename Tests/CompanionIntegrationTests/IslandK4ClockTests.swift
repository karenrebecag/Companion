import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

/// The session clock the reducer pauses. `now` is injected so a pause can
/// outlast the delay without the card expiring, and a resume can arm only
/// what was left.
private final class StepClock: @unchecked Sendable {
    private let lock = NSLock()
    private var t: TimeInterval = 0
    func now() -> TimeInterval { lock.withLock { t } }
    func advance(_ seconds: TimeInterval) { lock.withLock { t += seconds } }
}

@MainActor private func dictated(_ session: SessionModel) {
    session.send(.pressed)
    session.send(.released)
    session.send(.dictated(app: "Slack", text: "hola"))
}

@Test @MainActor func k4PausedDictationClockKeepsItsRemainder() async {
    let clock = StepClock()
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep, now: clock.now)
    dictated(session)
    await pumpUntil("K4: reloj del dictado") { sleeper.armed(SessionMachine.dictationCardDelay) == 1 }
    let elapsed: TimeInterval = 1
    clock.advance(elapsed)
    session.send(.dictationCardHover(true))
    await pumpUntil("K4: la pausa armó su techo") {
        sleeper.armed(SessionMachine.countdownPauseCeiling) == 1
    }
    expectEq(session.projection.kind, .processing(.completed), "K4: en pausa el dictado no caduca")
    expectEq(session.projection.dictatedText, "hola", "K4: y conserva las palabras")
    session.send(.dictationCardHover(false))
    let left = SessionMachine.dictationCardDelay - elapsed
    await pumpUntil("K4: sigue con lo que quedaba") { sleeper.armed(near: left, tolerance: 0.05) == 1 }
    sleeper.fire()
    await pumpUntil("K4: al cumplirse lo que quedaba se va") { session.projection.kind == .idle }
    expectEq(session.projection.dictatedText, nil, "K4: y suelta las palabras")
}

@Test @MainActor func k4PausedNoticeClockKeepsItsRemainder() async {
    let clock = StepClock()
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep, now: clock.now)
    session.send(.pressed)
    session.send(.released)
    session.send(.heardNothing)
    await pumpUntil("K4: reloj de «no te oí»") { sleeper.armed(SessionMachine.noticeDelay) == 1 }
    let elapsed: TimeInterval = 2
    clock.advance(elapsed)
    session.send(.noticeCardHover(true))
    await pumpUntil("K4: la pausa del aviso armó su techo") {
        sleeper.armed(SessionMachine.countdownPauseCeiling) == 1
    }
    expectEq(session.projection.notice, .couldntHear, "K4: en pausa el aviso sigue")
    session.send(.noticeCardHover(false))
    let left = SessionMachine.noticeDelay - elapsed
    await pumpUntil("K4: el aviso sigue con lo que quedaba") {
        sleeper.armed(near: left, tolerance: 0.05) == 1
    }
    sleeper.fire()
    await pumpUntil("K4: al cumplirse lo que quedaba se va") { session.projection.notice == nil }
}

@Test @MainActor func k4ANewNoticeDoesNotInheritAPausedClock() async {
    let clock = StepClock()
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep, now: clock.now)
    session.send(.pressed)
    session.send(.released)
    session.send(.heardNothing)
    await pumpUntil("K4: primer aviso") { sleeper.armed(SessionMachine.noticeDelay) == 1 }
    clock.advance(2)
    session.send(.noticeCardHover(true))
    clock.advance(100)
    session.send(.pressed)
    session.send(.released)
    session.send(.heardNothing)
    await pumpUntil("K4: el aviso nuevo arma 6 s") { sleeper.armed(SessionMachine.noticeDelay) == 2 }
    expectEq(sleeper.armed(SessionMachine.noticeDelay - 2), 0,
             "K4: no hereda el resto del aviso pausado")
}

@Test @MainActor func k4R2ALostHoverResumesAfterThePauseCeiling() async {
    let clock = StepClock()
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep, now: clock.now)
    dictated(session)
    await pumpUntil("K4: reloj del dictado") { sleeper.armed(SessionMachine.dictationCardDelay) == 1 }
    let elapsed: TimeInterval = 1
    clock.advance(elapsed)
    session.send(.dictationCardHover(true))
    await pumpUntil("K4: techo del dictado") { sleeper.armed(SessionMachine.countdownPauseCeiling) == 1 }
    clock.advance(SessionMachine.countdownPauseCeiling)
    sleeper.fire()
    let left = SessionMachine.dictationCardDelay - elapsed
    await pumpUntil("K4: el techo reanuda lo que quedaba") { sleeper.armed(near: left, tolerance: 0.05) == 1 }
    expectEq(session.projection.kind, .processing(.completed), "K4: el techo no tira las palabras")
    sleeper.fire()
    await pumpUntil("K4: lo que quedaba sí las retira") { session.projection.kind == .idle }

    session.send(.pressed)
    session.send(.released)
    session.send(.heardNothing)
    await pumpUntil("K4: reloj del aviso") { sleeper.armed(SessionMachine.noticeDelay) >= 1 }
    clock.advance(2)
    session.send(.noticeCardHover(true))
    let ceilings = sleeper.armed(SessionMachine.countdownPauseCeiling)
    await pumpUntil("K4: techo del aviso") { sleeper.armed(SessionMachine.countdownPauseCeiling) > ceilings }
    clock.advance(SessionMachine.countdownPauseCeiling)
    sleeper.fire()
    await pumpUntil("K4: el aviso sigue con su resto") {
        sleeper.armed(near: SessionMachine.noticeDelay - 2, tolerance: 0.05) == 1
    }
    expectEq(session.projection.notice, .couldntHear, "K4: el techo no borra el aviso")
}

@Test @MainActor func k4R2PauseBudgetIsTotalPerClock() async {
    let clock = StepClock()
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep, now: clock.now)
    dictated(session)
    await pumpUntil("K4: reloj") { sleeper.armed(SessionMachine.dictationCardDelay) == 1 }
    session.send(.dictationCardHover(true))
    await pumpUntil("K4: primer techo") { sleeper.armed(SessionMachine.countdownPauseCeiling) == 1 }
    clock.advance(40)
    let armedBeforeLeaving = sleeper.delays.count
    session.send(.dictationCardHover(false))
    // Cancelled waits stay pending, so `pending` says nothing about the resume.
    // Each timer registers from its own task off the main actor: if the resume
    // timer lands after the next ceiling, `delays.last` is not the ceiling.
    await pumpUntil("K4: salió") { sleeper.delays.count > armedBeforeLeaving }
    session.send(.dictationCardHover(true))
    await pumpUntil("K4: el segundo tramo es lo que quedaba del techo") {
        sleeper.armed(near: SessionMachine.countdownPauseCeiling - 40, tolerance: 0.05) == 1
    }
}

@Test @MainActor func k4R2SecondIdenticalNoticeStaysPaused() async {
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep)
    session.send(.pressed)
    session.send(.released)
    session.send(.heardNothing)
    await pumpUntil("K4: primer aviso") { sleeper.armed(SessionMachine.noticeDelay) == 1 }
    session.send(.noticeCardHover(true))
    let ceilings = sleeper.armed(SessionMachine.countdownPauseCeiling)
    let second = session.send(.heardNothing)
    expect(second.contains(.pauseNoticeExpiry), "K4: el modelo recibe la pausa del aviso nuevo")
    guard second.contains(.pauseNoticeExpiry) else { return }
    await pumpUntil("K4: el aviso nuevo también tiene techo") {
        sleeper.armed(SessionMachine.countdownPauseCeiling) > ceilings
    }
    sleeper.fire()
    await pumpUntil("K4: el aviso sigue en pantalla") { session.projection.notice == .couldntHear }
}

@Test @MainActor func k4R2DoublePauseKeepsTheFirstRemainder() async {
    let clock = StepClock()
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep, now: clock.now)
    dictated(session)
    await pumpUntil("K4: reloj") { sleeper.armed(SessionMachine.dictationCardDelay) == 1 }
    clock.advance(1)
    session.send(.dictationCardHover(true))
    clock.advance(2)
    session.send(.dictationCardHover(true))
    session.send(.dictationCardHover(false))
    let first = SessionMachine.dictationCardDelay - 1
    await pumpUntil("K4: queda el primer resto") { sleeper.armed(near: first, tolerance: 0.05) == 1 }
    expectEq(sleeper.armed(near: SessionMachine.dictationCardDelay - 3, tolerance: 0.05), 0,
             "K4: la segunda pausa no vuelve a medir")
}

@Test @MainActor func k4R2ResumeWithoutAPauseLeavesTheTimer() async {
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep)
    dictated(session)
    await pumpUntil("K4: reloj") { sleeper.armed(SessionMachine.dictationCardDelay) == 1 }
    let armed = sleeper.delays.count
    session.send(.dictationCardHover(false))
    expectEq(session.projection.kind, .processing(.completed), "K4: salir sin haber entrado no caduca")
    expectEq(sleeper.delays.count, armed, "K4: ni arma otro plazo")
    sleeper.fire()
    await pumpUntil("K4: el plazo original sí caduca") { session.projection.kind == .idle }
}

@Test @MainActor func k4R2PauseAfterTheTimerDoesNothing() async {
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep)
    dictated(session)
    await pumpUntil("K4: reloj") { sleeper.armed(SessionMachine.dictationCardDelay) == 1 }
    sleeper.fire()
    await pumpUntil("K4: caducó") { session.projection.kind == .idle }
    let armed = sleeper.delays.count
    session.send(.dictationCardHover(true))
    session.send(.dictationCardHover(false))
    expectEq(session.projection.kind, .idle, "K4: la tarjeta ya no está")
    expectEq(sleeper.delays.count, armed, "K4: pausar o reanudar después no arma nada")
}

@Test @MainActor func k4R2CopyUnderThePointerFreezesAFullDelay() async {
    let clock = StepClock()
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep, now: clock.now)
    dictated(session)
    await pumpUntil("K4: reloj") { sleeper.armed(SessionMachine.dictationCardDelay) == 1 }
    clock.advance(1)
    session.send(.dictationCardHover(true))
    session.send(.dictationCardCopied)
    expectEq(session.projection.dictatedText, "hola", "K4: copiar deja las palabras")
    session.send(.dictationCardHover(false))
    await pumpUntil("K4: al salir el plazo es el entero") {
        guard let last = sleeper.delays.last else { return false }
        return abs(last - SessionMachine.dictationCardDelay) <= 0.05
    }
    expectEq(sleeper.armed(near: SessionMachine.dictationCardDelay - 1, tolerance: 0.05), 0,
             "K4: no reanuda el resto del reloj que copiar reemplazó")
}
