import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing
import CompanionUITestSupport
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// 16q-1, review round. Security: a spoken yes needs the user's own words in
// that hold (M3), the sheet and the voice session agree on what is pending
// (M2), a duplicate MCP id fails closed (L1). QA: the edges of the MCP sheet,
// the announced question and the per-job stop at the VoiceSession level.

@Test @MainActor func approvals16q1ReviewTests() async {
    await testAnAnnouncedYesNeedsTheUsersOwnWords()
    await testAnAnnouncedYesWithClearWordsResolves()
    await testAnInjectedResolveWithOtherWordsResolvesNothing()
    await testAYesTheUserSaidResolvesThroughTheModel()
    await testAResolvedRequestIsNotAnnouncedOrAnswered()
    await testAnExpiredRequestIsNotAnswered()
    await testANewerRequestTakesTheYesAway()
    await testStopVoiceDuringTheQuestionCutsItAndTheYesNeedsTheClick()
    await testStoppingTheJobDropsItsAnnouncedPermissionAndLeavesBs()
    await testTheApprovalsActorRefusesADuplicateID()
    await testTheSheetsExitsReachTheVoicePort()
    await testEveryBridgeEventCarriesTheJobsID()
    await testTheChatsJobIsTaggedFromItsFirstEvent()
    testTheMCPPromptForbidsAnApprovingResolve()
}

// MARK: - Security M3: the user's own words

@MainActor private func answerAfterSaying(_ said: String?) async -> SpokenApproval {
    let jobs = GatedJob()
    let h = await q1Classic(jobs)
    await q1AskedAndSaid(h, jobs)
    await q1HeldKey(h)
    if let said { await h.session.noteHeard(said, pressed: await h.session.timeline.pressed) }
    let answer = await h.session.answerPendingApproval(true)
    jobs.open()
    await h.session.hangUp()
    return answer
}

@MainActor func testAnAnnouncedYesNeedsTheUsersOwnWords() async {
    expectEq(await answerAfterSaying("pásame la sal"), .needsClick, "palabras: otra cosa, aunque el tiempo cuadre")
    expectEq(await answerAfterSaying("no, no lo hagas"), .needsClick, "palabras: una negacion")
    expectEq(await answerAfterSaying("sí, pero no"), .needsClick, "palabras: un si con reserva")
    expectEq(await answerAfterSaying(nil), .needsClick, "palabras: no dijo nada en este hold")
}

@MainActor func testAnAnnouncedYesWithClearWordsResolves() async {
    expectEq(await answerAfterSaying("sí, dale"), .resolved, "palabras: un si claro, anunciado antes, resuelve")
}

/// The injection: the model calls resolve_approval(true) through a whole
/// classic turn and she said something else.
@MainActor func testAnInjectedResolveWithOtherWordsResolvesNothing() async {
    let jobs = GatedJob()
    let model = SessionModel(jobs: jobs, approvals: nil)
    let h = await q1Classic(jobs, model: model, rounds: [[.handoff(q1Flights)], q1SaysYes])
    await q1AskedAndSaid(h, jobs)
    h.clock.now += 5
    h.transcriber.stoppedText = "qué hora es"
    await h.session.hold()
    await pumpUntil("inyeccion: hold") { h.watch.latest.state == .listening }
    await h.session.release()
    await h.session.awaitClassicTurn()
    expect(jobs.resolutions.isEmpty, "inyeccion: el modelo dijo si y ella dijo otra cosa: no se aprueba")
    expect(h.synth.queue.contains(Escalation.approvalNeedsClickSpoken(.es)), "inyeccion: la voz pide el clic")
    jobs.open()
}

@MainActor func testAYesTheUserSaidResolvesThroughTheModel() async {
    let jobs = GatedJob()
    let model = SessionModel(jobs: jobs, approvals: nil)
    let h = await q1Classic(jobs, model: model, rounds: [[.handoff(q1Flights)], q1SaysYes])
    await q1AskedAndSaid(h, jobs)
    h.clock.now += 5
    h.transcriber.stoppedText = "sí, dale"
    await h.session.hold()
    await pumpUntil("si real: hold") { h.watch.latest.state == .listening }
    await h.session.release()
    await h.session.awaitClassicTurn()
    await pumpUntil("si real: el permiso se aprueba") { jobs.resolutions == [true] }
    jobs.open()
}

// MARK: - Security M2: what is pending

@MainActor func testAResolvedRequestIsNotAnnouncedOrAnswered() async {
    let jobs = GatedJob()
    let h = await q1Classic(jobs)
    await h.session.hold()
    await pumpUntil("cerrada: hold") { h.watch.latest.state == .listening }
    jobs.ask(q1Req("r1"))
    await pumpUntilAsync("cerrada: la pregunta espera su hueco") { await h.session.parkedAnnouncements.count == 1 }
    await h.session.approvalClosed(requestId: "r1")
    await h.session.discard()
    await pumpUntilAsync("cerrada: la pregunta se descarta") { await h.session.droppedAnnouncements == 1 }
    expect(!h.synth.queue.contains(Escalation.approvalAskedSpoken(.es)), "cerrada: no se pregunta lo que ya no existe")
    await h.session.noteHeard("sí", pressed: await h.session.timeline.pressed)
    expectEq(await h.session.answerPendingApproval(true), .nothingPending, "cerrada: un si no resuelve nada")
    jobs.open()
}

/// An auto-denied request is dead on the actor; the voice session has no
/// event for it, so it expires by the same clock.
@MainActor func testAnExpiredRequestIsNotAnswered() async {
    let h = makeVoiceHarness(language: .es)
    await h.session.noteApproval(q1Req("r1"))
    await h.session.approvalAnnounced("r1")
    await q1HeldKey(h)
    await h.session.noteHeard("sí", pressed: await h.session.timeline.pressed)
    h.clock.now += ApprovalTiming.autoDeny
    expectEq(await h.session.answerPendingApproval(true), .nothingPending, "caducada: pasado el auto-deny no queda nada")
    await h.session.hangUp()
}

@MainActor func testANewerRequestTakesTheYesAway() async {
    let jobs = GatedJob()
    let h = await q1Classic(jobs)
    await q1AskedAndSaid(h, jobs, "r1")
    jobs.ask(q1Req("r2"))
    await pumpUntilAsync("nueva: r2 es la pendiente") { await h.session.pendingApproval?.requestId == "r2" }
    await q1HeldKey(h)
    await h.session.noteHeard("sí", pressed: await h.session.timeline.pressed)
    expectEq(await h.session.answerPendingApproval(true), .needsClick, "nueva: el si de r1 no vale para r2")
    jobs.open()
    await h.session.hangUp()
}

@MainActor func testStopVoiceDuringTheQuestionCutsItAndTheYesNeedsTheClick() async {
    let jobs = GatedJob()
    let box = Q1SessionVoiceBox()
    let model = SessionModel(jobs: jobs, approvals: nil, voice: box)
    let h = await q1Classic(jobs, model: model)
    box.session = h.session
    jobs.ask(q1Req("r1"))
    await pumpUntil("stop pregunta: suena") { h.synth.queue.contains(Escalation.approvalAskedSpoken(.es)) }
    await pumpUntil("stop pregunta: el reductor lo sabe") { model.projection.announcing }
    let fx = model.send(.stopVoice)
    expect(fx.contains(.cancelVoiceOutput), "stop pregunta: corta la voz")
    await pumpUntil("stop pregunta: el sintetizador se detiene") { h.synth.stopped }
    await q1HeldKey(h)
    await h.session.noteHeard("sí", pressed: await h.session.timeline.pressed)
    expectEq(await h.session.answerPendingApproval(true), .needsClick,
             "stop pregunta: una pregunta cortada no se dijo; el si pide el clic")
    jobs.open()
    await h.session.hangUp()
}

/// B's request must survive A's stop, and A's announced question must not
/// take a yes any more.
@MainActor func testStoppingTheJobDropsItsAnnouncedPermissionAndLeavesBs() async {
    let box = Q1SessionVoiceBox()
    let model = SessionModel(jobs: nil, approvals: nil, voice: box)
    let h = makeVoiceHarness(language: .es, session: model)
    box.session = h.session
    let a = JobID("A"), b = JobID("B")
    model.send(.job(.started(goal: "a"), from: a))
    model.send(.job(.started(goal: "b"), from: b))
    model.send(.job(.approvalRequested(q1Req("r1")), from: a))
    model.send(.job(.approvalRequested(q1Req("r2")), from: b))
    await h.session.noteApproval(q1Req("r1"))
    await h.session.approvalAnnounced("r1")
    await q1HeldKey(h)
    await h.session.noteHeard("sí", pressed: await h.session.timeline.pressed)
    model.send(.stopJob(a))
    await pumpUntilAsync("stopJob: la sesion olvida r1") { await h.session.pendingApproval == nil }
    expectEq(await h.session.answerPendingApproval(true), .nothingPending, "stopJob: el si no resuelve nada")
    expectEq(model.projection.approvalQueue.map(\.requestId), ["r2"], "stopJob: lo de B queda intacto en la hoja")
    await h.session.hangUp()
}

private struct Wire: Equatable {
    let id: String
    let approve: Bool
}

private func wire(_ sent: [String]) -> [Wire] {
    sent.compactMap { text in
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let item = root["item"] as? [String: Any],
              item["type"] as? String == "mcp_approval_response",
              let id = item["approval_request_id"] as? String,
              let approve = item["approve"] as? Bool else { return nil }
        return Wire(id: id, approve: approve)
    }
}

private final class AnswerFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool?
    var answer: Bool? { lock.withLock { value } }
    func set(_ approved: Bool) { lock.withLock { value = approved } }
}

@MainActor func testTheApprovalsActorRefusesADuplicateID() async {
    let actor = Approvals(clock: RealtimeClock(), timeout: 60)
    // Neither is "first" by construction: whichever registers second is the
    // refused one, and it answers at once; the other stays parked.
    let one = AnswerFlag()
    let two = AnswerFlag()
    Task { one.set(await actor.request(q1Req("x")).approved) }
    Task { two.set(await actor.request(q1Req("x")).approved) }
    await pumpUntil("actor: el id repetido se rechaza al momento", timeout: 3) {
        one.answer != nil || two.answer != nil
    }
    let refused = one.answer != nil ? one : two
    let original = one.answer != nil ? two : one
    expectEq(refused.answer, false, "actor: el id repetido se rechaza")
    expect(original.answer == nil, "actor: la original sigue esperando")
    expect(await actor.resolve(requestId: "x", approved: true), "actor: la original sigue resoluble")
    await pumpUntil("actor: la original recibe su respuesta", timeout: 3) { original.answer != nil }
    expectEq(original.answer, true, "actor: y es la que se dio")
}

@MainActor func testTheSheetsExitsReachTheVoicePort() async {
    let voice = RecordingVoice()
    let model = SessionModel(jobs: nil, approvals: nil, voice: voice)
    model.send(.job(.approvalRequested(q1Req("c1"))))
    model.send(.approvalAnswered(requestId: "c1", approved: true, remember: false))
    await pumpUntil("puerto: la salida llega a la voz") { voice.closedRequests == ["c1"] }
}

// MARK: - Ids (code M3)

private final class EventBag: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [SessionEvent] = []
    var all: [SessionEvent] { lock.withLock { items } }
    func add(_ event: SessionEvent) { lock.withLock { items.append(event) } }
}

/// No production road makes an untagged job: the bridge mints an id before
/// the first event and every event, the end included, carries it.
@MainActor func testEveryBridgeEventCarriesTheJobsID() async {
    let bag = EventBag()
    await VoiceJobBridge.run(
        Handoff(goal: "leer", context: ""), jobs: SteppingSubmitter(), thread: ScriptedThread(),
        onEvent: { bag.add($0) })
    var ids: [JobID?] = []
    for event in bag.all {
        switch event {
        case .job(_, let id): ids.append(id)
        case .jobFinished(_, let id): ids.append(id)
        default: break
        }
    }
    expect(ids.count >= 3, "ids: hay inicio, pasos y fin (\(ids.count))")
    expect(ids.allSatisfy { $0 != nil }, "ids: ninguno sin etiqueta")
    expectEq(Set(ids.compactMap { $0 }).count, 1, "ids: todos del mismo encargo")
}

@MainActor func testTheChatsJobIsTaggedFromItsFirstEvent() async {
    let jobs = GatedJob()
    let vm = ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([.cerebras: "sk-test"]),
        store: MemoryConversationStore(), config: .default, jobSubmitter: jobs)
    vm.onAppear()
    Task { await vm.runJob(preface: "", handoff: Handoff(goal: "ordenar", context: ""), submitter: jobs) }
    await pumpUntil("chat ids: el encargo esta en la proyeccion") { vm.session.projection.job != nil }
    expect(vm.session.projection.job?.id != nil, "chat ids: nace con id")
    jobs.open()
}

// MARK: - The MCP prompt

func testTheMCPPromptForbidsAnApprovingResolve() {
    let en = MCPServerConfig.approvalPrompt(server: "docs", tool: "search", .en)
    let es = MCPServerConfig.approvalPrompt(server: "docs", tool: "search", .es)
    expect(en.contains("never call resolve_approval with approved true"), "prompt en: la clausula que prohibe aprobar")
    expect(es.contains("nunca llames resolve_approval con approved true"), "prompt es: la clausula que prohibe aprobar")
    expect(en.contains("resolve_approval with approved false"), "prompt en: el no si se puede decir")
    expect(es.contains("resolve_approval con approved false"), "prompt es: el no si se puede decir")
}
