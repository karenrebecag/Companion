import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import Testing

// The ring is elapsed time minus time under the pointer.

@Test @MainActor func k4RingIgnoresTimeUnderThePointer() {
    let life = SessionMachine.noticeDelay
    let shown = Date(timeIntervalSinceReferenceDate: 1_000)
    var pause = NoticePause()
    pause.hover(true, at: shown.addingTimeInterval(2))
    let under = shown.addingTimeInterval(5)
    expectEq(
        NoticeRing.fraction(elapsed: under.timeIntervalSince(shown),
                            paused: pause.accumulated(at: under), lifetime: life),
        NoticeRing.fraction(elapsed: 2, paused: 0, lifetime: life),
        "K4: con el puntero encima el anillo no avanza")
    pause.hover(false, at: under)
    let after = under.addingTimeInterval(1)
    expectEq(
        NoticeRing.fraction(elapsed: after.timeIntervalSince(shown),
                            paused: pause.accumulated(at: after), lifetime: life),
        NoticeRing.fraction(elapsed: 3, paused: 0, lifetime: life),
        "K4: al salir el anillo sigue donde iba")
}

@Test @MainActor func k4ANewNoticeDoesNotInheritTheRingPause() {
    let shown = Date(timeIntervalSinceReferenceDate: 1_000)
    var pause = NoticePause()
    pause.hover(true, at: shown)
    let again = shown.addingTimeInterval(4)
    pause.reset(at: again)
    expect(pause.over, "K4: el puntero sigue encima del aviso nuevo")
    expectEq(pause.accumulated(at: again), 0, "K4: el anillo nuevo empieza lleno")
}

@Test @MainActor func k4R2HoverRuleMatchesTheReducer() {
    let approval = ApprovalRequest(requestId: "1", toolName: "look", summary: "mira", inputJSON: "{}")
    let receipt = ActionReceipt(lines: ["hecho"])!
    let answer = Card(payload: .gallery(GalleryBlock(images: [])), source: .tool)
    let pairs: [(SessionCard, IslandState.Line?)] = [
        (.couldntHear, .couldntHear),
        (.permission(.micDenied), .permission(.micDenied)),
        (.failure(.networkUnavailable), .failure(.networkUnavailable)),
        (.approval(approval), nil),
        (.approvalAnswered(tool: "look", approved: true, remembered: false), nil),
        (.answer(answer), nil),
        (.holdHint, .holdHint),
        (.connectApp(slug: "slack", name: "Slack"), .connectApp(slug: "slack", name: "Slack")),
        (.signInApp(slug: "slack", name: "Slack"), .signInApp(slug: "slack", name: "Slack")),
        (.receipt(receipt), .receipt(receipt)),
        (.replyCut, .replyCut),
        (.approvalWithdrawn, .approvalWithdrawn),
    ]
    for (card, line) in pairs {
        let reducer = SessionMachine.pausesOnHover(card)
        if let line {
            expectEq(NoticeHoverRule.viewPauses(line), reducer, "K4: \(line) usa la regla del reducer")
        } else {
            expect(!reducer, "K4: \(card) no pausa al pasar el puntero")
        }
    }
    expect(!NoticeHoverRule.viewPauses(.chatError("no pude guardar")),
           "K4: el error de chat no pausa: su reloj es el de la vista")
}

@Test @MainActor func k4R2PointerRecordsLeaveBeforeTheSend() {
    var pause = NoticePause()
    var sent: [Bool] = []
    let start = Date(timeIntervalSinceReferenceDate: 1_000)
    pause.pointerMoved(true, pausesClock: true, at: start) { sent.append($0) }
    pause.pointerMoved(false, pausesClock: false, at: start.addingTimeInterval(1)) { sent.append($0) }
    expect(!pause.over, "K4: C no nace pausada: B ya registró la salida")
    expectEq(sent, [true], "K4: solo la tarjeta con reloj avisa a la sesión")
}

@Test @MainActor func k4R2NoticeCardTakesTheSender() throws {
    let card = try String(contentsOf: k4Source("Sources/CompanionUI/Island/Notices/IslandNoticeCard.swift"),
                          encoding: .utf8)
    let model = try String(contentsOf: k4Source("Sources/CompanionUI/Voice/SessionModel.swift"),
                           encoding: .utf8)
    let status = try String(contentsOf: k4Source("Sources/CompanionUI/Island/Work/IslandView+Status.swift"),
                            encoding: .utf8)
    expect(!card.contains("NoticeCountdownHover"), "K4: la tarjeta no tiene un sender estático")
    expect(!model.contains("NoticeCountdownHover"), "K4: la sesión no lo pisa al crearse")
    expect(card.contains("onHover: (Bool) -> Void"), "K4: el hover entra por parámetro")
    expect(status.contains("noticeCardHover"), "K4: la isla manda el hover de su sesión")
}

@Test @MainActor func k4R2ReduceMotionExpiresOnTheSessionClock() async throws {
    let life = SessionMachine.noticeDelay
    expectEq(NoticeRing.fraction(elapsed: life, paused: 0, lifetime: life), 0,
             "K4: al cumplirse el plazo el anillo está vacío")
    let source = try String(contentsOf: k4Source("Sources/CompanionUI/Island/Notices/IslandNoticeCard.swift"),
                            encoding: .utf8)
    expect(!source.contains("reduce motion still expires"),
           "K4: el anillo no afirma un comportamiento que este test no cubre")
    let sleeper = ManualSleeper()
    let session = SessionModel(jobs: nil, approvals: nil, sleep: sleeper.sleep)
    session.send(.pressed)
    session.send(.released)
    session.send(.heardNothing)
    await pumpUntil("K4: reloj del aviso") { sleeper.armed(life) == 1 }
    sleeper.fire()
    await pumpUntil("K4: caduca el reloj de la sesión") { session.projection.notice == nil }
}

private func k4Source(_ path: String) -> URL {
    URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: path)
}
