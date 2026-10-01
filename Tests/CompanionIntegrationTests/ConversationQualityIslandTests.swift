import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing
import CompanionUITestSupport
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Wave 16h-3, criterion 9 (spec 16h section 2): the island talks to the
// model. A card shown, closed by the user or ignored, and an interruption,
// enter the NEXT turn (voice and chat) as short neutral facts, once, and
// only the latest few.

/// The facts the reducer decided in one step: island events are effects of
/// the reducer itself, not something rebuilt from a before and an after.
private func step(_ machine: inout SessionMachine, _ event: SessionEvent) -> [IslandEvent] {
    facts(machine.handle(event))
}

func facts(_ effects: [SessionEffect]) -> [IslandEvent] {
    effects.compactMap { if case .islandEvent(let fact) = $0 { fact } else { nil } }
}

// MARK: - The reducer's facts

@Test func testANoticeShownIsAnEventButTheHoldHintIsNoise() {
    var machine = SessionMachine()
    expectEq(step(&machine, .heardNothing), [.shown(.notice)], "isla: 'no te oí' es una tarjeta mostrada")
    var hint = SessionMachine()
    expectEq(step(&hint, .tapped), [], "isla: la pista del hold no le dice nada al modelo")
    var connect = SessionMachine()
    expectEq(step(&connect, .connectAppSuggested(slug: "slack", name: "Slack")), [.shown(.notice)],
             "isla: la tarjeta de conectar una app también")
}

@Test func testANoticeThatLeavesOnItsOwnIsIgnoredAndOneTheUserClosesIsClosed() {
    var expired = SessionMachine()
    _ = step(&expired, .heardNothing)
    expectEq(step(&expired, .noticeExpired(.couldntHear)), [.ignored(.notice)], "isla: se fue sola es ignorada")
    expect(expired.projection.notice == nil, "isla: y ya no está")

    var closed = SessionMachine()
    _ = step(&closed, .heardNothing)
    expectEq(step(&closed, .noticeDismissed), [.closed(.notice)], "isla: la cerró la usuaria")
    expect(closed.projection.notice == nil, "isla: cerrar la quita de la proyección")
}

@Test func testNothingToExpireAndNothingToClaimMeansNoEvent() {
    var empty = SessionMachine()
    expectEq(step(&empty, .noticeExpired(.couldntHear)), [], "isla: expirar lo que no hay no es un hecho")
    expectEq(step(&empty, .noticeDismissed), [], "isla: cerrar lo que no hay tampoco")
    var permission = SessionMachine()
    _ = step(&permission, .voice(TurnSnapshot(state: .error, failure: .micDenied)))
    expectEq(step(&permission, .noticeExpired(.permission(.micDenied))), [],
             "isla: un permiso no se va solo: expirar no es ignorarlo")
}

@Test func testStoppingMidTurnIsAnInterruptionAndStoppingAtRestIsNot() {
    var machine = SessionMachine()
    _ = step(&machine, .typedSubmitted)
    expectEq(step(&machine, .stop), [.interrupted], "isla: Esc a mitad del turno es una interrupción")
    var idle = SessionMachine()
    expectEq(step(&idle, .stop), [], "isla: Esc en reposo no interrumpe nada")
}

// MARK: - The log

@Test func testTheLogFoldsRepeatsAndIsAsBigAsTheBlockShows() {
    var log = IslandEventLog()
    log.record(.shown(.result))
    log.record(.shown(.result))
    expectEq(log.pending, [.shown(.result)], "registro: el mismo hecho seguido no se repite")
    for kind in [IslandCardKind.notice, .receipt, .answer, .result, .notice] { log.record(.shown(kind)) }
    expectEq(log.pending.count, IslandEventLog.capacity, "registro: acotado")
    expectEq(IslandEventLog.capacity, ContextBlock.Caps.islandEvents, "registro: lo que se guarda es lo que se cuenta")
    expectEq(log.pending.last, .shown(.notice), "registro: gana lo más reciente")
}

@Test func testAFactRepeatedAfterItWasReadIsNotFoldedIntoTheReadOne() {
    var log = IslandEventLog()
    log.record(.interrupted)
    let read = log.peek()
    log.record(.interrupted)
    log.acknowledge(through: read.through)
    expectEq(log.pending, [.interrupted], "entrega: el segundo hecho igual llegó tras la lectura y sigue pendiente")
}

@Test func testTheBlockAtItsLimitStillCarriesAllTheIslandEvents() {
    let huge = String(repeating: "x", count: 600)
    let ctx = TurnContext(
        source: .voice, focusedApp: huge, openDocuments: Array(repeating: huge, count: 12),
        clipboard: ClipboardSummary(kind: .text, preview: huge),
        screenSummary: huge, screenSnippets: Array(repeating: ScreenSnippet(app: huge, text: huge), count: 12),
        focusedWindow: huge, location: UserLocation(city: "Cuernavaca", country: "México"),
        islandEvents: [.shown(.result), .closed(.notice), .ignored(.receipt), .interrupted])
    let block = ContextBlock.render(ctx, language: .en)
    for line in ["card shown: result", "card closed by the user: notice",
                 "card left on its own, unattended: receipt", "the user interrupted"] {
        expect(block.contains(line), "límite: «\(line)» viaja aunque se recorte lo demás")
    }
}

@Test func testDeliveryHasTwoPhasesAndOnlyTheAcknowledgedFactsAreForgotten() {
    var log = IslandEventLog()
    log.record(.shown(.result))
    log.record(.interrupted)
    let first = log.peek()
    expectEq(first.events, [.shown(.result), .interrupted], "entrega: se ven sin consumir")
    expectEq(log.peek(), first, "entrega: mirar dos veces no consume")
    log.record(.closed(.answer))
    log.acknowledge(through: first.through)
    expectEq(log.pending, [.closed(.answer)], "entrega: lo llegado después del prompt queda para el siguiente")
    log.acknowledge(through: log.peek().through)
    expectEq(log.pending, [], "entrega: y luego se acusa")
}

@Test func testTheBufferIsSafeUnderConcurrentWritersAndAcknowledgesOnce() async {
    let buffer = IslandEventBuffer()
    await withTaskGroup(of: Void.self) { group in
        for index in 0 ..< 50 {
            group.addTask { buffer.record(index.isMultiple(of: 2) ? .interrupted : .shown(.result)) }
        }
    }
    let batch = buffer.pending()
    expect(!batch.events.isEmpty && batch.events.count <= IslandEventLog.capacity, "buffer: acotado bajo concurrencia")
    buffer.acknowledge(through: batch.through)
    expectEq(buffer.pending().events, [], "buffer: acusado, no vuelve")
}

// MARK: - The context block

@Test func testTheBlockTellsTheLatestEventsInShortNeutralWords() {
    let events: [IslandEvent] = [.shown(.result), .closed(.notice), .ignored(.receipt), .interrupted]
    let es = ContextBlock.render(TurnContext(source: .voice, islandEvents: events), language: .es)
    for line in ["tarjeta mostrada: resultado", "tarjeta cerrada por la usuaria: aviso",
                 "tarjeta que se fue sola sin atender: recibo", "la usuaria interrumpió"] {
        expect(es.contains(line), "isla (es): «\(line)»")
    }
    let en = ContextBlock.render(TurnContext(source: .typed, islandEvents: events), language: .en)
    for line in ["card shown: result", "card closed by the user: notice",
                 "card left on its own, unattended: receipt", "the user interrupted"] {
        expect(en.contains(line), "isla (en): «\(line)»")
    }
    expect(es.contains("<island_events>") && es.contains("</island_events>"), "isla: dentro de su tag")
}

@Test func testOnlyTheLatestFewEventsTravelAndNoneMeansNoTag() {
    let many: [IslandEvent] = [.shown(.result), .shown(.notice), .shown(.receipt), .shown(.answer),
                               .closed(.result), .interrupted]
    let block = ContextBlock.render(TurnContext(source: .voice, islandEvents: many), language: .en)
    let lines = block.split(separator: "\n").filter { $0.hasPrefix("    - ") && !$0.contains("[") }
    let events = lines.filter { $0.contains("card") || $0.contains("interrupted") }
    expectEq(events.count, ContextBlock.Caps.islandEvents, "isla: solo los \(ContextBlock.Caps.islandEvents) últimos")
    expect(!block.contains("card shown: result"), "isla: el más viejo ya no viaja")
    expect(block.contains("the user interrupted"), "isla: el último sí")
    expect(!ContextBlock.render(TurnContext(source: .voice), language: .en).contains("<island_events"),
           "isla: sin eventos no hay tag")
}

@Test func testTheEventsAreNotSavedInTheHistoryLine() {
    let compact = ContextBlock.compact(
        TurnContext(source: .voice, islandEvents: [.shown(.result)]), language: .en)
    expect(!compact.contains("card"), "isla: la línea compacta del hilo no guarda eventos")
}

// MARK: - The sensor hands them over once, to voice and chat alike

private func scripted(_ events: [IslandEvent]) -> IslandEventBuffer {
    let buffer = IslandEventBuffer()
    for event in events { buffer.record(event) }
    return buffer
}

@Test func testSensingAloneNeverConsumesTheEvents() async {
    let buffer = scripted([.shown(.result), .closed(.result)])
    let sensor = SystemContextSensor(
        focused: FakeChannel(app: "Safari"), documents: FakeChannel(), clipboard: FakeChannel(),
        islandEvents: buffer)
    let first = await sensor.sense(.default, budget: .milliseconds(200))
    expectEq(first.islandEvents, [.shown(.result), .closed(.result)], "sensor: el turno siguiente los lleva")
    let again = await sensor.sense(.default, budget: .milliseconds(200))
    expectEq(again.islandEvents, first.islandEvents, "sensor: sentir dos veces (pulsación cancelada) no consume")
    sensor.acknowledgeIslandEvents(through: again.islandEventsThrough)
    let third = await sensor.sense(.default, budget: .milliseconds(200))
    expectEq(third.islandEvents, [], "sensor: acusado por quien armó el prompt, nunca se repiten")
}

@Test func testTheEventsTravelEvenWithEveryChannelOff() async {
    let sensor = SystemContextSensor(
        focused: FakeChannel(app: "Safari"), documents: FakeChannel(), clipboard: FakeChannel(),
        islandEvents: scripted([.interrupted]))
    let ctx = await sensor.sense([], budget: .milliseconds(200))
    expectEq(ctx.islandEvents, [.interrupted], "sensor: son hechos de la propia app, no del entorno de ella")
}

/// A sensor that hands over island facts and records who acknowledged them.
/// Every read gets its own watermark, so an ack can only match the read that
/// actually built the prompt (a fixed number would pass whichever was spent).
final class AckingSensor: ContextSensing, @unchecked Sendable {
    private let lock = NSLock()
    private var acked: [Int] = []
    private var reads: [Int] = []
    var acks: [Int] { lock.withLock { acked } }
    var served: [Int] { lock.withLock { reads } }
    func sense(_ channels: ContextChannels, budget: Duration) async -> TurnContext {
        let mark = lock.withLock { () -> Int in
            reads.append(reads.count + 1)
            return reads.count
        }
        return TurnContext(source: .typed, islandEvents: [.interrupted], islandEventsThrough: mark)
    }
    func acknowledgeIslandEvents(through: Int) { lock.withLock { acked.append(through) } }
}

@MainActor @Test func testAClassicTurnAcknowledgesOnlyOnceThePromptCarriedTheFacts() async {
    let sensor = AckingSensor()
    let h = makeVoiceHarness(sensor: sensor)
    h.transcriber.stoppedText = "hola"
    h.chat.rounds = [[.text("Hola.")]]
    await h.session.hold()
    await pumpUntil("ack: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("ack: el chat recibe el turno") { !h.chat.histories.isEmpty }
    expectEq(sensor.acks.count, 1, "ack: el hold clásico acusa una vez, al armar el prompt")
    expect(sensor.served.contains(sensor.acks.first ?? -1), "ack: acusa la lectura que de verdad leyó (\(sensor.served))")
}

@MainActor @Test func testACancelledHoldConsumesNothing() async {
    let sensor = AckingSensor()
    let h = makeVoiceHarness(sensor: sensor)
    await h.session.hold()
    await pumpUntil("cancelado: listening") { h.watch.latest.state == .listening }
    await h.session.discard()
    await pumpUntil("cancelado: la sesión vuelve a reposo") { h.watch.latest.state == .idle }
    expectEq(sensor.acks, [], "cancelado: una pulsación cancelada no consume los eventos")
}

@MainActor @Test func testARealtimeSegmentCommitAcknowledges() async {
    let ear = ScriptedSegmentingEar()
    let sensor = AckingSensor()
    let h = makeVoiceHarness(realtimeEar: ear, sensor: sensor)
    await h.session.start()
    await pumpUntil("realtime: listening") { h.watch.latest.state == .listening }
    ear.yieldTurn(.speechStarted)
    await pumpUntil("realtime: speechOpen") { h.watch.latest.speechOpen }
    ear.yieldTurn(.finished(text: "crea prueba dos en el desktop"))
    await pumpUntilAsync("realtime: acusa al comprometer el turno") { sensor.acks.count == 1 }
    expect(sensor.served.contains(sensor.acks.first ?? -1), "realtime: acusa la lectura que de verdad leyó (\(sensor.served))")
}

@MainActor @Test func testTheChatAcknowledgesAfterBuildingTheRequest() async {
    let sensor = AckingSensor()
    let chat = FakeChatProvider(replies: [.success([.text("ok")])])
    let vm = primed(chat: chat, sensor: sensor)
    vm.draft = "hola"
    vm.send()
    await pumpUntil("chat ack: idle") { !vm.busy }
    expectEq(sensor.acks.count, 1, "chat: acusa una vez, tras armar el pedido")
    expect(sensor.served.contains(sensor.acks.first ?? -1), "chat: acusa la lectura que de verdad leyó (\(sensor.served))")
}

@MainActor @Test func testTheChatRequestCarriesTheIslandEvents() async {
    let sensor = FakeContextSensor(TurnContext(source: .typed, islandEvents: [.ignored(.notice)]))
    let chat = FakeChatProvider(replies: [.success([.text("ok")])])
    let vm = primed(chat: chat, sensor: sensor, config: Config(language: .en))
    vm.draft = "hola"
    vm.send()
    await pumpUntil("isla: idle") { !vm.busy }
    let last = chat.histories[0].last?.content ?? ""
    expect(last.contains("card left on its own, unattended: notice"),
           "isla: el pedido tecleado lleva el evento — \(last.prefix(300))")
}

// MARK: - The result card's attention

@Test func testAResultNobodyOpenedIsIgnoredWhenTheNextOneArrives() {
    var attention = IslandResultAttention()
    let first = UUID(), second = UUID(), third = UUID()
    expectEq(attention.replyShown(first), [.shown(.result)], "resultado: mostrado")
    expectEq(attention.replyShown(first), [], "resultado: el mismo dos veces no repite")
    expectEq(attention.replyShown(second), [.ignored(.result), .shown(.result)],
             "resultado: el que nadie atendió se ignoró al llegar el siguiente")
    attention.attended()
    expectEq(attention.replyShown(third), [.shown(.result)],
             "resultado: uno abierto no se cuenta como ignorado")
}

// MARK: - The session model is the writer

private final class SinkRecorder: IslandEventSink, @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [IslandEvent] = []
    var events: [IslandEvent] { lock.withLock { seen } }
    func record(_ event: IslandEvent) { lock.withLock { seen.append(event) } }
}

@MainActor @Test func testTheSessionModelFeedsTheSinkFromTheReducersFacts() {
    let sink = SinkRecorder()
    let model = SessionModel(jobs: nil, approvals: nil)
    model.islandEvents = sink
    model.send(.heardNothing)
    model.send(.noticeExpired(.couldntHear))
    model.report(.closed(.answer))
    expectEq(sink.events, [.shown(.notice), .ignored(.notice), .closed(.answer)],
             "modelo de sesión: lo derivado y lo que la UI reporta llegan al mismo buzón")
}

@MainActor @Test func testDismissingANoticeFromTheIslandIsAClosedNotAnExpired() {
    let sink = SinkRecorder()
    let vm = primed(chat: FakeChatProvider(replies: []))
    vm.session.islandEvents = sink
    vm.session.send(.heardNothing)
    vm.dismissIslandNotice(.couldntHear)
    expectEq(sink.events, [.shown(.notice), .closed(.notice)],
             "isla: la × la cierra la usuaria; no es que se fuera sola")
}

// MARK: - The whole cycle with the real pieces

/// The session model writes to a REAL buffer, a REAL sensor reads it, and the
/// turn's own prompt is what is inspected: a card that left on its own is told
/// once and never again.
@MainActor @Test func testChatCycleWithRealPiecesTellsTheModelOnceAndNeverRepeats() async {
    let buffer = IslandEventBuffer()
    let sensor = SystemContextSensor(
        focused: FakeChannel(app: "Safari"), documents: FakeChannel(), clipboard: FakeChannel(),
        islandEvents: buffer)
    let chat = FakeChatProvider(replies: [.success([.text("uno")]), .success([.text("dos")])])
    let vm = primed(chat: chat, sensor: sensor, config: Config(language: .en))
    vm.session.islandEvents = buffer
    vm.session.send(.heardNothing)
    vm.session.send(.noticeExpired(.couldntHear))
    vm.draft = "hola"
    vm.send()
    await pumpUntil("ciclo chat: primer turno") { !vm.busy && chat.histories.count == 1 }
    let first = chat.histories[0].last?.content ?? ""
    expect(first.contains("card left on its own, unattended: notice"),
           "ciclo chat: el primer pedido dice que la tarjeta se fue sola — \(first.prefix(400))")
    vm.draft = "otra cosa"
    vm.send()
    await pumpUntil("ciclo chat: segundo turno") { !vm.busy && chat.histories.count == 2 }
    let second = chat.histories[1].last?.content ?? ""
    expect(!second.contains("card left on its own") && !second.contains("card shown: notice"),
           "ciclo chat: el segundo pedido no repite lo ya dicho — \(second.prefix(400))")
    expectEq(buffer.pending().events, [], "ciclo chat: el buzón quedó vacío")
}

@MainActor @Test func testClassicVoiceCycleWithRealPiecesTellsTheModelOnceAndNeverRepeats() async {
    let buffer = IslandEventBuffer()
    let sensor = SystemContextSensor(
        focused: FakeChannel(app: "Safari"), documents: FakeChannel(), clipboard: FakeChannel(),
        islandEvents: buffer)
    let model = SessionModel(jobs: nil, approvals: nil)
    model.islandEvents = buffer
    let h = makeVoiceHarness(sensor: sensor, session: model)
    model.send(.heardNothing)
    model.send(.noticeExpired(.couldntHear))
    h.transcriber.stoppedText = "hola"
    h.chat.rounds = [[.text("Hola.")], [.text("Va.")]]
    await h.session.hold()
    await pumpUntil("ciclo voz: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("ciclo voz: primer turno") { h.chat.histories.count == 1 }
    let first = h.chat.histories[0].last?.content ?? ""
    expect(first.contains("card left on its own, unattended: notice"),
           "ciclo voz: el primer turno lo dice — \(first.prefix(400))")
    await h.session.awaitClassicTurn()
    h.transcriber.stoppedText = "otra"
    await h.session.hold()
    await pumpUntil("ciclo voz: listening otra vez") { h.watch.latest.state == .listening }
    await h.session.release()
    await h.session.awaitClassicTurn()
    expectEq(h.chat.histories.count, 2, "ciclo voz: el segundo turno llegó al modelo")
    let second = h.chat.histories[1].last?.content ?? ""
    expect(!second.contains("card left on its own") && !second.contains("card shown: notice"),
           "ciclo voz: el segundo turno no repite — \(second.prefix(400))")
}

// MARK: - Criterion 9, one assertion per promise

private final class RouterTurn {
    let runtime: ClassicRuntime
    let sensor = AckingSensor()
    let chat = ScriptedChat()
    init(decision: DecisionOutcome?) {
        let transcriber = FakeTranscriber()
        transcriber.stoppedText = "abre Safari"
        chat.rounds = [[.text("Hecho.")]]
        runtime = ClassicRuntime(
            transcriber: transcriber, synthesizer: ScriptedSynth(), chat: chat, thread: ScriptedThread())
        runtime.sensor = sensor
        if let decision { runtime.decide = { _, _ in decision } }
    }
}

@MainActor @Test func testATurnTheRouterResolvesNeverSpendsTheIslandEvents() async {
    let routed = RouterTurn(decision: .declined)
    await routed.runtime.submit(config: Config(language: .es)) { _ in }
    expectEq(routed.sensor.acks, [], "router: el turno lo resolvió el router, los hechos de la isla siguen pendientes")
    expectEq(routed.chat.histories.count, 0, "router: el modelo ni se enteró de ese turno")
    let passed = RouterTurn(decision: .passThrough(.disabled))
    await passed.runtime.submit(config: Config(language: .es)) { _ in }
    expectEq(passed.chat.histories.count, 1, "router: si se abstiene, el modelo toma el turno")
    expectEq(passed.sensor.acks.count, 1, "router: y entonces sí se gastan, una vez")
}

@Test func testSteerAndTheUserInterruptedTravelTogetherAndMeanDifferentThings() {
    let both = ContextBlock.render(
        TurnContext(source: .voice, interrupted: true, islandEvents: [.interrupted]), language: .en)
    expect(both.contains("<steer>"), "interrupción: <steer> (pulsó a mitad de la respuesta)")
    expect(both.contains("the user interrupted"), "interrupción: 'interrumpió' (Esc o Stop)")
    let steerOnly = ContextBlock.render(TurnContext(source: .voice, interrupted: true), language: .en)
    expect(steerOnly.contains("<steer>") && !steerOnly.contains("the user interrupted"),
           "interrupción: <steer> solo no dice 'interrumpió'")
    let stopOnly = ContextBlock.render(TurnContext(source: .voice, islandEvents: [.interrupted]), language: .en)
    expect(!stopOnly.contains("<steer>") && stopOnly.contains("the user interrupted"),
           "interrupción: 'interrumpió' solo no lleva <steer>")
}

@MainActor @Test func testChangingConversationCountsAsAResultShownAndTheUnattendedOneIgnored() async {
    let chat = chat()
    await chat.appendAssistant("Respuesta de la primera conversación.")
    let voice = VoiceViewModel(voice: RecordingVoice(), thread: FakePresenter())
    let hold = HoldSettingsModel(permission: FakeAccessibility(trusted: true))
    let view = IslandView(chat: chat, voice: voice, hold: hold, onShowMain: {}, onSize: { _, _ in })
    let first = view.latestReply?.id
    let firstConversation = chat.conversationId
    chat.newConversation()
    await chat.appendAssistant("Respuesta de la segunda.")
    let second = view.latestReply?.id
    expect(first != nil && second != nil && first != second,
           "conversación: la respuesta de delante cambia con la conversación, que es lo que dispara 'mostrada'")
    var attention = IslandResultAttention()
    if let first, let second {
        expectEq(attention.replyShown(first), [.shown(.result)], "conversación: la primera, mostrada")
        expectEq(attention.replyShown(second), [.ignored(.result), .shown(.result)],
                 "conversación: la de la otra conversación, mostrada; la que nadie atendió, ignorada")
    }
    chat.openConversation(firstConversation)
    let back = view.latestReply?.id
    expect(back != nil && back != second, "conversación: volver a la primera también cambia lo que se muestra")
}

@Test func testAStopInEveryPhaseOfATurnIsExactlyOneInterruption() {
    let phases: [(String, [SessionEvent])] = [
        ("pensando (tecleado)", [.typedSubmitted]),
        ("hablando (tecleado)", [.typedSubmitted, .typedReplyStreaming]),
        ("pensando (voz)", [.voice(TurnSnapshot(state: .thinking))]),
        ("hablando (voz)", [.voice(TurnSnapshot(state: .speaking))]),
        ("con un encargo activo", [.job(.started(goal: "ordenar"))]),
    ]
    for (name, setup) in phases {
        var machine = SessionMachine()
        for event in setup { _ = machine.handle(event) }
        expectEq(facts(machine.handle(.stop)), [.interrupted], "Esc \(name): una interrupción")
        expectEq(facts(machine.handle(.stop)), [], "Esc \(name): el segundo Esc ya no interrumpe nada")
    }
}

@Test func testAPressInEveryPhaseOfATurnIsTheSteerSignalNotAnInterruptionEvent() {
    let phases: [(String, [SessionEvent])] = [
        ("pensando (tecleado)", [.typedSubmitted]),
        ("hablando (tecleado)", [.typedSubmitted, .typedReplyStreaming]),
        ("pensando (voz)", [.voice(TurnSnapshot(state: .thinking))]),
        ("hablando (voz)", [.voice(TurnSnapshot(state: .speaking))]),
        ("con un encargo activo", [.job(.started(goal: "ordenar"))]),
    ]
    for (name, setup) in phases {
        for press in [SessionEvent.pressed, .pressedProvisionally] {
            var machine = SessionMachine()
            for event in setup { _ = machine.handle(event) }
            expectEq(facts(machine.handle(press)), [],
                     "pulsar \(name): cortar con la voz es <steer>, no un 'interrumpió' de la isla")
        }
    }
}
