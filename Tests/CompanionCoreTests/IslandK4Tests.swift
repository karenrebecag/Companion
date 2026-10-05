import CompanionCore
import CompanionTestKit
import Foundation
import Testing

// K4: countdown cards pause under the pointer and continue, and the
// dictation card uses Incredible's dismiss. The reducer has no wall clock,
// so the pause is an effect the model performs.

private func card(_ text: DictatedText = "hola") -> SessionMachine {
    var machine = SessionMachine()
    _ = machine.handle(.pressed)
    _ = machine.handle(.dictating(app: "Slack"))
    _ = machine.handle(.released)
    _ = machine.handle(.dictated(app: "Slack", text: text))
    return machine
}

private func clockEffects(_ effects: [SessionEffect]) -> [SessionEffect] {
    effects.filter {
        switch $0 {
        case .scheduleCompletedExpiry, .pauseCompletedExpiry, .resumeCompletedExpiry,
             .scheduleNoticeExpiry, .pauseNoticeExpiry, .resumeNoticeExpiry:
            true
        default:
            false
        }
    }
}

@Test func k4DictationCardUsesIncredibleTiming() {
    expectEq(SessionMachine.dictationCardDelay, 4.9, "K4: el dictado dura lo de Incredible")
    expect(SessionMachine.dictationCardDelay > SessionMachine.settleDelay,
           "K4: sigue siendo más largo que el asentamiento")
    let (_, effects) = dictatedCard()
    expect(effects.contains(.scheduleCompletedExpiry(SessionMachine.dictationCardDelay, floor: nil)),
           "K4: la tarjeta arma ese plazo, entero")
}

@Test func k4HoverPausesAndLeaveResumes() {
    var machine = card()
    expectEq(machine.handle(.dictationCardHover(true)), [.pauseCompletedExpiry],
             "K4: el puntero pausa, no reinicia")
    expectEq(machine.handle(.dictationCardHover(true)), [],
             "K4: un segundo aviso de pausa no rearma")
    expectEq(machine.handle(.dictationCardHover(false)), [.resumeCompletedExpiry],
             "K4: al salir sigue donde iba")
    expectEq(machine.handle(.dictationCardHover(false)), [],
             "K4: salir otra vez no arma un plazo nuevo")
}

@Test func k4RestUnderThePointerDoesNotRestart() {
    var machine = card()
    _ = machine.handle(.dictationCardHover(true))
    let rested = machine.handle(.voice(
        TurnSnapshot(state: .listening, pipeline: .realtime, muted: true, holdArmed: true)))
    expectEq(clockEffects(rested), [.pauseCompletedExpiry],
             "K4: rest() con el puntero encima no cambia el reloj")
}

@Test func k4CopyRearmsUnlessThePointerIsOverTheCard() {
    var machine = card()
    expectEq(machine.handle(.dictationCardCopied),
             [.scheduleCompletedExpiry(SessionMachine.dictationCardDelay, floor: nil)],
             "K4: copiar, con el puntero fuera, arma el plazo entero")
    _ = machine.handle(.dictationCardHover(true))
    expectEq(machine.handle(.dictationCardCopied),
             [.scheduleCompletedExpiry(SessionMachine.dictationCardDelay, floor: nil), .pauseCompletedExpiry],
             "K4: copiar con el puntero encima deja el plazo nuevo en pausa")
}

@Test func k4ANewDictationArmsItsOwnClock() {
    var machine = card()
    _ = machine.handle(.dictationCardHover(true))
    _ = machine.handle(.pressed)
    _ = machine.handle(.dictating(app: "Slack"))
    _ = machine.handle(.released)
    let effects = machine.handle(.dictated(app: "Slack", text: "otra"))
    expect(effects.contains(.scheduleCompletedExpiry(SessionMachine.dictationCardDelay, floor: nil)),
           "K4: un dictado nuevo arma su plazo entero")
    expect(!effects.contains(.pauseCompletedExpiry), "K4: y no hereda la pausa")
}

@Test func k4CouldntHearAndTheHintLiveSixSeconds() {
    expectEq(SessionMachine.noticeDelay, 6, "K4: «no te oí» y la pista viven 6 s")
    var heard = SessionMachine()
    _ = heard.handle(.pressed)
    _ = heard.handle(.released)
    expectEq(clockEffects(heard.handle(.heardNothing)),
             [.scheduleNoticeExpiry(SessionMachine.noticeDelay)],
             "K4: «no te oí» arma sus 6 s")
    var hint = SessionMachine()
    _ = hint.handle(.pressed)
    expect(clockEffects(hint.handle(.tapped)).contains(.scheduleNoticeExpiry(SessionMachine.noticeDelay)),
           "K4: la pista arma sus 6 s")
}

@Test func k4NoticeHoverPausesAndANewNoticeRearms() {
    var machine = SessionMachine()
    _ = machine.handle(.pressed)
    _ = machine.handle(.released)
    _ = machine.handle(.heardNothing)
    expectEq(machine.handle(.noticeCardHover(true)), [.pauseNoticeExpiry],
             "K4: el puntero pausa el aviso")
    expectEq(machine.handle(.noticeCardHover(true)), [],
             "K4: el reducer recuerda que el puntero ya está encima")
    expectEq(machine.handle(.noticeCardHover(false)), [.resumeNoticeExpiry],
             "K4: al salir el aviso sigue donde iba")
    _ = machine.handle(.pressed)
    _ = machine.handle(.released)
    expectEq(clockEffects(machine.handle(.heardNothing)),
             [.scheduleNoticeExpiry(SessionMachine.noticeDelay)],
             "K4: un aviso nuevo arma su reloj completo")
}

@Test func k4APermissionDoesNotPause() {
    var denied = SessionMachine()
    _ = denied.handle(.voice(TurnSnapshot(state: .error, failure: .micDenied)))
    expectEq(denied.handle(.noticeCardHover(true)), [],
             "K4: un permiso no tiene cuenta atrás")
    expectEq(denied.handle(.noticeCardHover(false)), [],
             "K4: ni al salir el puntero")
}

@Test func k4R2ASecondIdenticalNoticeUnderThePointerStartsPaused() {
    var machine = SessionMachine()
    _ = machine.handle(.pressed)
    _ = machine.handle(.released)
    _ = machine.handle(.heardNothing)
    _ = machine.handle(.noticeCardHover(true))
    expectEq(clockEffects(machine.handle(.heardNothing)),
             [.scheduleNoticeExpiry(SessionMachine.noticeDelay), .pauseNoticeExpiry],
             "K4: el segundo «no te oí», idéntico y con el puntero encima, nace pausado")
    _ = machine.handle(.pressed)
    _ = machine.handle(.released)
    expectEq(clockEffects(machine.handle(.heardNothing)),
             [.scheduleNoticeExpiry(SessionMachine.noticeDelay)],
             "K4: al irse el aviso el puntero no se hereda")
}

@Test func k4R2DelayCommentDoesNotQuoteTheBundle() throws {
    let source = try String(contentsOf: worktreeFile("Sources/CompanionCore/Session/SessionMachine.swift"),
                            encoding: .utf8)
    expect(source.contains(
        "4.9 s, Incredible's dictation countdown (local reference; brief isla-ciclo-y-legibilidad K4)"),
           "K4: el comentario del plazo es esa frase")
    expect(!source.contains("dm=4900"), "K4: el comentario no cita la constante del bundle")
    expect(!source.contains("overlay-"), "K4: el comentario no cita el archivo del bundle")
}

private func worktreeFile(_ path: String) -> URL {
    URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: path)
}

private func dictatedCard() -> (SessionMachine, [SessionEffect]) {
    var machine = SessionMachine()
    _ = machine.handle(.pressed)
    _ = machine.handle(.dictating(app: "Slack"))
    _ = machine.handle(.released)
    let effects = machine.handle(.dictated(app: "Slack", text: "hola"))
    return (machine, effects)
}
