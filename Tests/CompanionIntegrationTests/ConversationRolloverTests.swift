import CompanionCore
import CompanionServices
@testable import CompanionUI
import Foundation
import Testing
import CompanionUITestSupport
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

@Test @MainActor func conversationRolloverTests() async {
    // Pure policy (Core): no ChatViewModel involved.
    testShouldRolloverNilLastActivityIsFalse()
    testShouldRolloverBoundaryAt299And300()
    testShouldRolloverBlockedByOpenWork()
    testShouldRolloverClockWentBackwardsIsFalse()

    // ChatViewModel wiring: the triggers, the guards, the archived record.
    await testWrittenTurnAfterSixMinutesRollsOverKeepingOldRecord()
    await testWrittenTurnAfterTwoMinutesKeepsSameThread()
    await testAppendUserBothSignaturesRollOverAfterSixMinutes()
    await testJobRunningBlocksRolloverThenIdleWindowAfterResult()
    await testApprovalPendingBlocksRollover()
    testLoadMostRecentRollsOverStaleRecordButRestoresFresh()
    testStaleStartupNeverRestampsTheOldThread()
    await testHistoryTurnsExpiredReturnsEmpty()
    await testRolloverKeepsDraftAndPendingAttachments()
    await testRolloverIfIdleRespectsKindGuard()
    await testRolloverIfIdleRespectsRealtimeGuard()
    await testNewConversationManualIgnoresGuards()

    // VoiceSession: the seed reorder (555 <-> 556-558).
    await testHandsFreeAfterExpiryStillWritesMemory()
}

// MARK: - 1-6: ConversationRollover.shouldRollover, pure

@MainActor func testShouldRolloverNilLastActivityIsFalse() {
    let activity = ConversationActivity(
        lastActivity: nil, turnInFlight: false, jobRunning: false,
        approvalsPending: false, liveRealtime: false)
    expect(!ConversationRollover.shouldRollover(activity, now: Date()),
           "rollover1: sin lastActivity nunca dispara")
}

@MainActor func testShouldRolloverBoundaryAt299And300() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let activity = ConversationActivity(
        lastActivity: start, turnInFlight: false, jobRunning: false,
        approvalsPending: false, liveRealtime: false)
    expect(
        !ConversationRollover.shouldRollover(activity, now: start.addingTimeInterval(299)),
        "rollover2: 299s no alcanza")
    expect(
        ConversationRollover.shouldRollover(activity, now: start.addingTimeInterval(300)),
        "rollover2: 300s sí dispara")
}

@MainActor func testShouldRolloverBlockedByOpenWork() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let hourLater = start.addingTimeInterval(3600)
    let base = ConversationActivity(
        lastActivity: start, turnInFlight: false, jobRunning: false,
        approvalsPending: false, liveRealtime: false)
    var jobRunning = base
    jobRunning.jobRunning = true
    var approvalsPending = base
    approvalsPending.approvalsPending = true
    var turnInFlight = base
    turnInFlight.turnInFlight = true
    var liveRealtime = base
    liveRealtime.liveRealtime = true
    let guarded: [(ConversationActivity, String)] = [
        (jobRunning, "encargo corriendo"),
        (approvalsPending, "aprobación pendiente"),
        (turnInFlight, "turno en curso"),
        (liveRealtime, "realtime vivo"),
    ]
    for (activity, label) in guarded {
        expect(!ConversationRollover.shouldRollover(activity, now: hourLater),
               "rollover3-5: 1h idle con \(label) no dispara")
    }
}

@MainActor func testShouldRolloverClockWentBackwardsIsFalse() {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let activity = ConversationActivity(
        lastActivity: start, turnInFlight: false, jobRunning: false,
        approvalsPending: false, liveRealtime: false)
    expect(
        !ConversationRollover.shouldRollover(activity, now: start.addingTimeInterval(-10)),
        "rollover6: un reloj atrasado nunca fuerza el rollover")
}

// MARK: - Harness

@MainActor func rolloverPrimed(
    chat: FakeChatProvider = FakeChatProvider(),
    store: MemoryConversationStore = MemoryConversationStore(),
    clock: RolloverClock
) -> ChatViewModel {
    let vm = ChatViewModel(
        chat: chat, secrets: TestSecretStore([.openAI: "sk-test"]),
        store: store, config: .default, now: { clock.date })
    vm.onAppear()
    return vm
}

// MARK: - 7-9: written turns and appendUser drive the same funnel

@MainActor func testWrittenTurnAfterSixMinutesRollsOverKeepingOldRecord() async {
    let clock = RolloverClock(Date(timeIntervalSince1970: 1_800_000_000))
    let store = MemoryConversationStore()
    let chat = FakeChatProvider(replies: [.success([.text("Hi")]), .success([.text("Bye")])])
    let vm = rolloverPrimed(chat: chat, store: store, clock: clock)
    vm.draft = "first"
    vm.send()
    await pumpUntil("rollover7: primer turno termina") { !vm.busy }
    let oldId = vm.conversationId
    let oldUpdatedAt = listOrFail(store, "rollover7").first { $0.id == oldId }?.updatedAt

    clock.advance(by: 360)
    vm.draft = "second"
    vm.send()
    expect(vm.conversationId != oldId, "rollover7: id nuevo")
    expectEq(vm.messages.map(\.text), ["second"], "rollover7: hilo empieza limpio")
    await pumpUntil("rollover7: segundo turno termina") { !vm.busy }

    let records = listOrFail(store, "rollover7")
    expectEq(records.count, 2, "rollover7: el viejo sigue archivado junto al nuevo")
    let old = records.first { $0.id == oldId }
    expectEq(old?.updatedAt, oldUpdatedAt, "rollover7: updatedAt del viejo intacto")
}

@MainActor func testWrittenTurnAfterTwoMinutesKeepsSameThread() async {
    let clock = RolloverClock(Date(timeIntervalSince1970: 1_800_000_000))
    let chat = FakeChatProvider(replies: [.success([.text("Hi")]), .success([.text("Bye")])])
    let vm = rolloverPrimed(chat: chat, clock: clock)
    vm.draft = "first"
    vm.send()
    await pumpUntil("rollover8: primer turno termina") { !vm.busy }
    let id = vm.conversationId

    clock.advance(by: 120)
    vm.draft = "second"
    vm.send()
    expectEq(vm.conversationId, id, "rollover8: mismo id a los 2 min")
    await pumpUntil("rollover8: segundo turno termina") { !vm.busy }
    expectEq(vm.messages.map(\.text), ["first", "Hi", "second", "Bye"],
             "rollover8: seguimiento con contexto")
}

@MainActor func testAppendUserBothSignaturesRollOverAfterSixMinutes() async {
    let clock = RolloverClock(Date(timeIntervalSince1970: 1_800_000_000))
    let vm = rolloverPrimed(clock: clock)
    await vm.appendUser("first")
    let idAfterFirst = vm.conversationId

    clock.advance(by: 360)
    await vm.appendUser("second")
    expect(vm.conversationId != idAfterFirst, "rollover9: appendUser(_:) dispara el mismo embudo")
    expectEq(vm.messages.map(\.text), ["second"], "rollover9: hilo limpio tras appendUser(_:)")
    let idAfterSecond = vm.conversationId

    clock.advance(by: 360)
    await vm.appendUser("third", context: nil)
    expect(vm.conversationId != idAfterSecond,
           "rollover9: appendUser(_:context:) también dispara")
    expectEq(vm.messages.map(\.text), ["third"],
             "rollover9: hilo limpio tras appendUser(_:context:)")
}

// MARK: - 10-11: job and approval guards

@MainActor func testJobRunningBlocksRolloverThenIdleWindowAfterResult() async {
    let clock = RolloverClock(Date(timeIntervalSince1970: 1_800_000_000))
    let vm = rolloverPrimed(clock: clock)
    await vm.appendUser("first")
    let job = JobID("j")
    vm.session.send(.job(.started(goal: "buscar algo"), from: job))

    clock.advance(by: 360)
    let midJobTurns = await vm.historyTurns()
    expect(!midJobTurns.isEmpty, "rollover10: con encargo corriendo no hay rollover")
    expectEq(vm.messages.map(\.text), ["first"], "rollover10: el hilo sigue siendo el mismo")

    // Review 16h-2 round 3: the job ends by its own tagged end.
    vm.session.send(.jobFinished(ok: true, from: job))
    await vm.appendAssistant("resultado")
    let idAfterResult = vm.conversationId

    clock.advance(by: 120)
    _ = await vm.historyTurns()
    expectEq(vm.conversationId, idAfterResult, "rollover10: +2 min tras el resultado no dispara")

    clock.advance(by: 240)
    _ = await vm.historyTurns()
    expect(vm.conversationId != idAfterResult, "rollover10: +6 min tras el resultado sí dispara")
}

@MainActor func testApprovalPendingBlocksRollover() async {
    let clock = RolloverClock(Date(timeIntervalSince1970: 1_800_000_000))
    let vm = rolloverPrimed(clock: clock)
    await vm.appendUser("first")
    vm.session.send(.job(.approvalRequested(ApprovalRequest(
        requestId: "r1", toolName: "open_url", summary: "abrir x", inputJSON: "{}"))))

    clock.advance(by: 360)
    _ = await vm.historyTurns()
    expectEq(vm.messages.map(\.text), ["first"],
             "rollover11: aprobación en cola bloquea el rollover")
}

// MARK: - 12-13: startup

@MainActor func testLoadMostRecentRollsOverStaleRecordButRestoresFresh() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    let staleStore = MemoryConversationStore()
    saveOrFail(staleStore, ConversationRecord(
        id: "stale", title: "Viejo", updatedAt: now.addingTimeInterval(-600),
        messages: [ConversationMessage(role: "user", text: "hola")]), "rollover12")
    let staleVM = ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
        store: staleStore, config: .default, now: { now })
    staleVM.onAppear()
    expect(staleVM.messages.isEmpty, "rollover12: 10 min de silencio arranca en limpio")

    let freshStore = MemoryConversationStore()
    saveOrFail(freshStore, ConversationRecord(
        id: "fresh", title: "Reciente", updatedAt: now.addingTimeInterval(-60),
        messages: [ConversationMessage(role: "user", text: "hola")]), "rollover12")
    let freshVM = ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
        store: freshStore, config: .default, now: { now })
    freshVM.onAppear()
    expectEq(freshVM.messages.map(\.text), ["hola"],
             "rollover12: 1 min de silencio restaura el hilo")
}

@MainActor func testStaleStartupNeverRestampsTheOldThread() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let store = MemoryConversationStore()
    let original = ConversationRecord(
        id: "old", title: "Viejo", updatedAt: now.addingTimeInterval(-600),
        messages: [ConversationMessage(role: "user", text: "hola")])
    saveOrFail(store, original, "rollover13")

    let firstLaunch = ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
        store: store, config: .default, now: { now })
    firstLaunch.onAppear()
    expect(firstLaunch.messages.isEmpty, "rollover13: primer arranque en limpio")
    expectEq(loadOrFail(store, "old", "rollover13")?.updatedAt, original.updatedAt,
             "rollover13: el primer arranque no re-estampa el viejo")

    let secondLaunch = ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
        store: store, config: .default, now: { now.addingTimeInterval(60) })
    secondLaunch.onAppear()
    expect(secondLaunch.messages.isEmpty, "rollover13: segundo arranque también en limpio")
    expectEq(loadOrFail(store, "old", "rollover13")?.updatedAt, original.updatedAt,
             "rollover13: sigue con su updatedAt original")
}

// MARK: - 14, 16: what a rollover leaves behind

@MainActor func testHistoryTurnsExpiredReturnsEmpty() async {
    let clock = RolloverClock(Date(timeIntervalSince1970: 1_800_000_000))
    let vm = rolloverPrimed(clock: clock)
    await vm.appendUser("first")
    clock.advance(by: 360)
    let turns = await vm.historyTurns()
    expect(turns.isEmpty, "rollover14: historyTurns caducado no lleva el hilo viejo")
}

@MainActor func testRolloverKeepsDraftAndPendingAttachments() async {
    let clock = RolloverClock(Date(timeIntervalSince1970: 1_800_000_000))
    let vm = rolloverPrimed(clock: clock)
    await vm.appendUser("first")
    vm.draft = "sin enviar"
    vm.pendingAttachments = [AttachmentRef(name: "a.png", path: "/tmp/a.png", kind: .image)]

    clock.advance(by: 360)
    _ = await vm.historyTurns()
    expect(vm.messages.isEmpty, "rollover16: el hilo sí rota")
    expectEq(vm.draft, "sin enviar", "rollover16: el draft sobrevive")
    expectEq(vm.pendingAttachments.map(\.name), ["a.png"], "rollover16: el adjunto sobrevive")
}

// MARK: - 17-18: rolloverIfIdle from applicationDidBecomeActive

@MainActor func testRolloverIfIdleRespectsKindGuard() async {
    let busyClock = RolloverClock(Date(timeIntervalSince1970: 1_800_000_000))
    let busyVM = rolloverPrimed(clock: busyClock)
    await busyVM.appendUser("first")
    busyVM.session.send(.typedSubmitted)
    busyClock.advance(by: 360)
    busyVM.rolloverIfIdle()
    expectEq(busyVM.messages.map(\.text), ["first"], "rollover17: kind processing no dispara")

    let idleClock = RolloverClock(Date(timeIntervalSince1970: 1_800_000_000))
    let idleVM = rolloverPrimed(clock: idleClock)
    await idleVM.appendUser("first")
    idleClock.advance(by: 360)
    idleVM.rolloverIfIdle()
    expect(idleVM.messages.isEmpty, "rollover17: kind idle sí dispara")
}

@MainActor func testRolloverIfIdleRespectsRealtimeGuard() async {
    let liveClock = RolloverClock(Date(timeIntervalSince1970: 1_800_000_000))
    let liveVM = rolloverPrimed(clock: liveClock)
    await liveVM.appendUser("first")
    liveVM.session.send(.voice(TurnSnapshot(state: .listening, pipeline: .realtime, muted: false)))
    liveClock.advance(by: 360)
    liveVM.rolloverIfIdle()
    expectEq(liveVM.messages.map(\.text), ["first"], "rollover18: voz .live no dispara")

    let connectingClock = RolloverClock(Date(timeIntervalSince1970: 1_800_000_000))
    let connectingVM = rolloverPrimed(clock: connectingClock)
    await connectingVM.appendUser("first")
    connectingVM.session.send(.voice(TurnSnapshot(state: .connecting, pipeline: .realtime)))
    connectingClock.advance(by: 360)
    connectingVM.rolloverIfIdle()
    expect(connectingVM.messages.isEmpty, "rollover18: voz .connecting sí dispara")
}

// MARK: - 19: the manual reset is untouched

@MainActor func testNewConversationManualIgnoresGuards() async {
    let clock = RolloverClock(Date(timeIntervalSince1970: 1_800_000_000))
    let vm = rolloverPrimed(clock: clock)
    await vm.appendUser("first")
    vm.session.send(.job(.started(goal: "algo largo")))
    let oldId = vm.conversationId

    vm.newConversation()
    expect(vm.conversationId != oldId, "rollover19: newConversation resetea al instante")
    expect(vm.messages.isEmpty, "rollover19: hilo vacío sin esperar el idle ni mirar el encargo")
}

// MARK: - 15: the realtime seed after an expired thread

@MainActor func testHandsFreeAfterExpiryStillWritesMemory() async {
    let clock = RolloverClock(Date(timeIntervalSince1970: 1_800_000_000))
    let vm = rolloverPrimed(clock: clock)
    await vm.appendUser("previous turn")
    clock.advance(by: 360)

    let memory = RecordingMemoryStore()
    let h = makeRolloverVoiceHarness(thread: vm, memoryStore: memory)
    h.transcriber.stoppedText = "hola"
    await h.session.start()
    await pumpUntil("rollover15: listening") { h.watch.latest.state == .listening }
    expect(vm.messages.isEmpty, "rollover15: abrir la sesión ya archivó el hilo caducado")

    h.transport.yield(.speechStarted)
    await pumpUntil("rollover15: speechOpen") { h.watch.latest.speechOpen }
    let before = h.transport.sent.count
    await h.session.toggleMute()
    await pumpUntil("rollover15: texto nativo enviado") {
        hasMessage(Array(h.transport.sent.dropFirst(before)), type: "conversation.item.create")
    }
    h.transport.yield(.responseCreated)
    h.transport.yield(.assistantTranscriptDelta("hola"))
    h.transport.yield(.assistantTranscriptDone("hola de vuelta"))
    await pumpUntil("rollover15: la respuesta llega al hilo nuevo") {
        vm.messages.map(\.text).contains("hola de vuelta")
    }

    await h.session.hangUp()
    await pumpUntil("rollover15: la nota de sesión se escribe") { !memory.sessions.isEmpty }
    let note = memory.sessions.joined()
    expect(note.contains("hola"),
           "rollover15: la nota cubre el intercambio de ESTA sesión, no el hilo caducado")
}

private struct AlwaysOnline: ReachabilityProbing {
    var isOnline: Bool { get async { true } }
}

@MainActor func makeRolloverVoiceHarness(
    thread: ChatViewModel, memoryStore: any MemoryStore
) -> (session: VoiceSession, transport: ScriptedVoiceTransport, watch: SnapWatch,
      transcriber: ScriptedTranscriber) {
    let transport = ScriptedVoiceTransport()
    transport.autoEvents = [.sessionCreated, .sessionUpdated]
    let mic = ScriptedMic()
    let player = ScriptedPlayer()
    let transcriber = ScriptedTranscriber()
    let synth = ScriptedSynth()
    let chat = ScriptedChat()
    let secrets = ScriptedSecrets([.openAI: "sk-test"])
    let provider = StaticConfigProvider(.default)
    let session = VoiceSession(
        transport: transport, mic: mic, player: player, transcriber: transcriber,
        synthesizer: synth, chat: chat, secrets: secrets, thread: thread,
        configProvider: provider, memoryStore: memoryStore,
        reachability: AlwaysOnline(), readyTimeout: 1)
    let watch = SnapWatch(session.snapshots)
    return (session, transport, watch, transcriber)
}

// MARK: - Store helpers (fail loud instead of force-try, matching the suite)

@MainActor func listOrFail(_ store: MemoryConversationStore, _ label: String) -> [ConversationMeta] {
    do { return try store.list() } catch {
        expect(false, "\(label): list no debía tirar \(error)")
        return []
    }
}

@MainActor func saveOrFail(
    _ store: MemoryConversationStore, _ record: ConversationRecord, _ label: String
) {
    do { try store.save(record) } catch {
        expect(false, "\(label): save no debía tirar \(error)")
    }
}

@MainActor func loadOrFail(
    _ store: MemoryConversationStore, _ id: String, _ label: String
) -> ConversationRecord? {
    do { return try store.load(id) } catch {
        expect(false, "\(label): load no debía tirar \(error)")
        return nil
    }
}
