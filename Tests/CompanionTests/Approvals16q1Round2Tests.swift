import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing

// 16q-1, second review round. A spoken yes belongs to its own hold (S2) and
// to the request it answered once (consumption); a request that already left
// the sheet is never re-armed by a task that lost the race (C2); a question
// that failed to sound was not said (Q4).

@Test @MainActor func approvals16q1Round2Tests() async {
    await testAStaleYesDoesNotAnswerANewRequestInACancelledHold()
    await testAYesOfAnEarlierHoldDoesNotAnswerALaterHold()
    await testAYesIsClearedWhenANewRequestArrivesInTheSameHold()
    await testAYesIsClearedWhenTheSheetChanges()
    await testATypedTurnClearsTheHeldYes()
    await testACancelledHoldReportsNoWords()
    await testOneYesResolvesOneRequestOnly()
    await testAClosedRequestIsNotReArmedByALateNote()
    await testTheClosedSetIsBounded()
    await testAFailedQuestionWasNotSaid()
}

// MARK: - S2: a yes belongs to its hold

/// The chain of the review: a yes nobody consumed, a new announced request,
/// a new hold that was cancelled before its own words, the model's injected
/// resolve_approval(true).
@MainActor func testAStaleYesDoesNotAnswerANewRequestInACancelledHold() async {
    let jobs = GatedJob()
    let h = await q1Classic(jobs)
    await q1AskedAndSaid(h, jobs, "r1")
    await q1HeldKey(h)
    await h.session.noteHeard("sí", pressed: await h.session.timeline.pressed)
    await h.session.discard()
    await pumpUntil("cadena: el hold A termino") { h.watch.latest.state != .listening }
    await q1AskedAndSaid(h, jobs, "r2")
    await q1HeldKey(h)
    expectEq(await h.session.answerPendingApproval(true), .needsClick,
             "cadena: el si de otro hold no vale para r2, aunque el tiempo cuadre")
    jobs.open()
    await h.session.hangUp()
}

/// Rewinding the clock stands for a question said before the hold started:
/// the announcement is stamped by it, and the hold under test must be the
/// only thing that can still refuse.
@MainActor private func announcedBeforeTheHold(_ h: VoiceHarness, _ id: String) async {
    h.clock.now = 0
    await h.session.noteApproval(q1Req(id))
    await h.session.approvalAnnounced(id)
}

/// The same request stays pending, so only the hold itself can refuse: the
/// yes was said in hold A and hold B answers with no words of its own.
@MainActor func testAYesOfAnEarlierHoldDoesNotAnswerALaterHold() async {
    let h = makeVoiceHarness(language: .es)
    await announcedBeforeTheHold(h, "r1")
    await q1HeldKey(h)
    await h.session.noteHeard("sí", pressed: await h.session.timeline.pressed)
    await h.session.discard()
    await pumpUntil("otro hold: el A termino") { h.watch.latest.state != .listening }
    await q1HeldKey(h)
    expectEq(await h.session.answerPendingApproval(true), .needsClick,
             "otro hold: un si de un hold anterior no responde en este")
    await h.session.hangUp()
}

@MainActor func testAYesIsClearedWhenANewRequestArrivesInTheSameHold() async {
    let h = makeVoiceHarness(language: .es)
    await announcedBeforeTheHold(h, "r1")
    await q1HeldKey(h)
    await h.session.noteHeard("sí", pressed: await h.session.timeline.pressed)
    await announcedBeforeTheHold(h, "r2")
    expectEq(await h.session.answerPendingApproval(true), .needsClick,
             "nueva en el mismo hold: el si era de la anterior")
    await h.session.hangUp()
}

@MainActor func testAYesIsClearedWhenTheSheetChanges() async {
    let h = makeVoiceHarness(language: .es)
    await announcedBeforeTheHold(h, "r1")
    await q1HeldKey(h)
    await h.session.noteHeard("sí", pressed: await h.session.timeline.pressed)
    await h.session.approvalClosed(requestId: "otra")
    expectEq(await h.session.answerPendingApproval(true), .needsClick,
             "hoja cambiada: un si dicho antes no cuenta despues")
    await h.session.hangUp()
}

@MainActor func testATypedTurnClearsTheHeldYes() async {
    let h = makeVoiceHarness(language: .es)
    await announcedBeforeTheHold(h, "r1")
    await q1HeldKey(h)
    await h.session.noteHeard("sí", pressed: await h.session.timeline.pressed)
    await h.session.apply(.typedSubmit)
    expectEq(await h.session.answerPendingApproval(true), .needsClick,
             "turno escrito: el si hablado no sobrevive")
    await h.session.hangUp()
}

private final class HeardBag: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String] = []
    var all: [String] { lock.withLock { items } }
    func add(_ text: String) { lock.withLock { items.append(text) } }
}

/// A hold cut while its ear was finishing returns before the words are
/// reported; the session must still hear "nothing" so an older yes dies.
@MainActor func testACancelledHoldReportsNoWords() async {
    let runtime = ClassicRuntime(
        transcriber: FakeTranscriber(), synthesizer: ScriptedSynth(), chat: ScriptedChat(),
        thread: ScriptedThread())
    let heard = HeardBag()
    runtime.onHeard = { text, _ in heard.add(text) }
    runtime.leftoverHeard = "  "
    let task = Task {
        while !Task.isCancelled { await Task.yield() }
        await runtime.submit(config: Config(language: .es)) { _ in }
    }
    task.cancel()
    await task.value
    expectEq(heard.all, [""], "hold cancelado: la sesion oye nada, no se queda con lo anterior")
}

// MARK: - Consumption

@MainActor func testOneYesResolvesOneRequestOnly() async {
    let h = makeVoiceHarness(language: .es)
    await announcedBeforeTheHold(h, "r1")
    await q1HeldKey(h)
    await h.session.noteHeard("sí", pressed: await h.session.timeline.pressed)
    expectEq(await h.session.answerPendingApproval(true), .resolved, "consumo: el si resuelve r1")
    await announcedBeforeTheHold(h, "r2")
    expectEq(await h.session.answerPendingApproval(true), .needsClick,
             "consumo: r2, anunciada en el mismo hold, no hereda el si de r1")
    await h.session.hangUp()
}

// MARK: - C2: the race with approvalClosed

@MainActor func testAClosedRequestIsNotReArmedByALateNote() async {
    let h = makeVoiceHarness(language: .es)
    await h.session.approvalClosed(requestId: "r1")
    await h.session.noteApproval(q1Req("r1"))
    await h.session.askApprovalAloud(q1Req("r1"))
    expect(await h.session.pendingApproval == nil, "carrera: lo cerrado no se vuelve a armar")
    expectEq(await h.session.droppedAnnouncements, 0, "carrera: ni siquiera se puso en cola")
    expect(h.synth.queue.isEmpty, "carrera: no se pregunta lo que ya no existe")
    await h.session.noteApproval(q1Req("r2"))
    expectEq(await h.session.pendingApproval?.requestId, "r2", "carrera: otra peticion si entra")
    await h.session.hangUp()
}

@MainActor func testTheClosedSetIsBounded() async {
    let h = makeVoiceHarness(language: .es)
    let cap = VoiceSession.closedApprovalCap
    for index in 0 ... cap { await h.session.approvalClosed(requestId: "c\(index)") }
    await h.session.noteApproval(q1Req("c\(cap)"))
    expect(await h.session.pendingApproval == nil, "tope: el mas reciente sigue cerrado")
    await h.session.noteApproval(q1Req("c1"))
    expect(await h.session.pendingApproval == nil, "tope: el mas viejo dentro del tope sigue cerrado")
    await h.session.noteApproval(q1Req("c0"))
    expectEq(await h.session.pendingApproval?.requestId, "c0", "tope: el que salio del tope ya no bloquea")
    await h.session.hangUp()
}

// MARK: - Q4: a question that failed

@MainActor func testAFailedQuestionWasNotSaid() async {
    let jobs = GatedJob()
    let h = await q1Classic(jobs)
    jobs.ask(q1Req("r1"))
    await pumpUntil("fallo: la voz intenta la pregunta") {
        h.synth.queue.contains(Escalation.approvalAskedSpoken(.es))
    }
    h.synth.yield(.failed)
    await pumpUntilAsync("fallo: el audio termino mal") { await !h.session.announcementUnlogged }
    await q1HeldKey(h)
    await h.session.noteHeard("sí", pressed: await h.session.timeline.pressed)
    expectEq(await h.session.answerPendingApproval(true), .needsClick,
             "fallo: una pregunta que no sono no se dijo; el si pide el clic")
    expect(await h.session.pendingApprovalSeen?.announcedAt == nil, "fallo: no queda marcada como anunciada")
    jobs.open()
    await h.session.hangUp()
}
