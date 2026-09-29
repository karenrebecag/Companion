import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing

// Wave 16h-3, criterion 3 (spec 16h section 2): the detail of a done action
// goes to a receipt on the island, and a receipt only exists with proof.

private func ok(_ tool: String, target: String = "Safari", verified: Bool = false) -> ParentToolOutcome {
    ParentToolOutcome(ok: true, output: "ok", target: target, tool: tool, verified: verified)
}

// MARK: - Proof

@Test func testAReceiptLineExistsOnlyForAChangeThatSucceeded() {
    expectEq(ReceiptProof.line(tool: "open_app", outcome: ok("open_app"), language: .es), "Abrí Safari.",
             "recibo: abrir con éxito da su línea")
    let failed = ParentToolOutcome(ok: false, output: "nope", target: "Safari", tool: "open_app")
    expect(ReceiptProof.line(tool: "open_app", outcome: failed, language: .es) == nil, "recibo: un fallo no tiene palomita")
    expect(ReceiptProof.line(tool: "list_apps", outcome: ok("list_apps"), language: .es) == nil,
           "recibo: leer no cambia nada, no es recibo")
    expect(ReceiptProof.line(tool: "look", outcome: ok("look"), language: .es) == nil, "recibo: mirar tampoco")
}

@Test func testTypingHasNoReceiptWithoutTheReadBack() {
    expect(ReceiptProof.line(tool: "type_text", outcome: ok("type_text"), language: .es) == nil,
           "recibo: escribir sin lectura posterior no tiene palomita")
    expectEq(ReceiptProof.line(tool: "type_text", outcome: ok("type_text", verified: true), language: .es),
             "Escribí el texto.", "recibo: con prueba, sí")
}

@Test func testAReceiptIsBoundedDedupedAndNeverEmpty() {
    expect(ActionReceipt(lines: []) == nil, "recibo: sin líneas no hay recibo")
    expect(ActionReceipt(lines: ["  ", ""]) == nil, "recibo: líneas en blanco tampoco")
    let many = (1 ... 6).map { "Abrí App \($0)." }
    expectEq(ActionReceipt(lines: many)?.lines, Array(many.suffix(ActionReceipt.maxLines)), "recibo: gana lo último")
    expectEq(ActionReceipt(lines: ["Abrí Safari.", "Abrí Safari."])?.lines, ["Abrí Safari."], "recibo: sin repetidas")
    let long = ActionReceipt(lines: [String(repeating: "x", count: 500)])
    expect((long?.lines.first?.unicodeScalars.count ?? 999) <= ActionReceipt.maxLineLength + 1, "recibo: línea acotada")
    let joined = ActionReceipt(lines: ["Abrí A."])?.merging(ActionReceipt(lines: ["Abrí B."])!)
    expectEq(joined?.lines, ["Abrí A.", "Abrí B."], "recibo: dos rondas del turno se unen")
}

// MARK: - What the receipt says, and does not

private func hasInvisible(_ text: String) -> Bool {
    text.unicodeScalars.contains { $0.properties.generalCategory == .format }
}

@Test func testInvisibleScalarsNeverReachAReceiptLineOrTheirCap() {
    let smuggled = ReceiptProof.line(
        tool: "open_file", outcome: ok("open_file", target: "a\u{202E}b.pdf"), language: .en)
    expect(smuggled != nil && !hasInvisible(smuggled ?? ""), "recibo: un nombre con bidi no llega con bidi — \(smuggled ?? "nil")")
    expectEq(smuggled, "Opened ab.pdf.", "recibo: el nombre queda legible y en un orden")
    let padded = ActionReceipt(lines: [String(repeating: "\u{E0041}", count: 200) + "hola"])
    expectEq(padded?.lines, ["hola"], "recibo: los caracteres de etiqueta no gastan el tope de 120 ni viajan")
    expectEq(TextHygiene.oneLine("a\u{E0041}\u{202E}b\u{200B}c\nd\te"), "abc d e",
             "higiene: sin invisibles, y saltos y controles a espacio")
}

@Test func testAnUrlOnTheReceiptShowsHostAndPathButNeverQueryFragmentOrCredentials() {
    let url = "https://user:pw@example.com/a/b?token=secret&x=1#frag"
    let line = ReceiptProof.line(tool: "open_url", outcome: ok("open_url", target: url), language: .en) ?? ""
    expectEq(line, "Opened example.com/a/b.", "recibo: host y ruta")
    for leaked in ["token", "secret", "frag", "user", "pw", "?"] {
        expect(!line.contains(leaked), "recibo: «\(leaked)» no viaja en la línea")
    }
    expectEq(ReceiptProof.line(tool: "open_url", outcome: ok("open_url", target: "https://example.com/"), language: .en),
             "Opened example.com.", "recibo: una ruta vacía no deja la barra")
    expectEq(ReceiptProof.line(tool: "open_app", outcome: ok("open_app", target: "Safari"), language: .en),
             "Opened Safari.", "recibo: un nombre de app pasa igual")
}

@Test func testAnySchemeLosesQueryFragmentAndCredentialsOnTheReceipt() {
    let mail = ReceiptProof.line(
        tool: "open_url", outcome: ok("open_url", target: "mailto:x@y.com?subject=secreto#f"), language: .en) ?? ""
    expect(mail.contains("x@y.com") && !mail.contains("secreto") && !mail.contains("?") && !mail.contains("#"),
           "recibo: mailto sin asunto ni fragmento — \(mail)")
    let own = ReceiptProof.line(
        tool: "open_url", outcome: ok("open_url", target: "myapp://user:pw@host/path?token=abc"), language: .en) ?? ""
    expect(own.contains("host/path") && !own.contains("token") && !own.contains("pw"),
           "recibo: un esquema propio tampoco lleva query ni credenciales — \(own)")
    expectEq(ReceiptProof.line(tool: "open_app", outcome: ok("open_app", target: "Note: hola"), language: .en),
             "Opened Note: hola.", "recibo: un nombre con dos puntos y espacio no es una URL")
}

@Test @MainActor func testOnlyAReadBackLineIsCalledVerified() {
    let typed = ReceiptProof.entry(tool: "type_text", outcome: ok("type_text", verified: true), language: .es)
    let opened = ReceiptProof.entry(tool: "open_app", outcome: ok("open_app"), language: .es)
    expectEq(typed?.verified, true, "etiqueta: escribir con lectura posterior está comprobado")
    expectEq(opened?.verified, false, "etiqueta: abrir dice hecho, no comprobado")
    for language in [AppLanguage.es, .en] {
        let done = Localized.string("island.receipt.done", language: language)
        let checked = Localized.string("island.receipt.check", language: language)
        expect(done != "island.receipt.done" && done != checked, "etiqueta (\(language)): 'Hecho' distinto de 'comprobado'")
        expectEq(IslandReceipt.checkLabel(typed!, language: language), checked, "etiqueta (\(language)): comprobado")
        expectEq(IslandReceipt.checkLabel(opened!, language: language), done, "etiqueta (\(language)): hecho")
    }
    let merged = ActionReceipt(entries: [ReceiptLine(text: "Abrí A.", verified: false)])!
        .merging(ActionReceipt(entries: [ReceiptLine(text: "Abrí A.", verified: true)])!)
    expectEq(merged.entries.map(\.verified), [true], "etiqueta: la misma línea probada después queda comprobada")
}

// MARK: - The reducer

private func run(_ machine: inout SessionMachine, _ event: SessionEvent) -> [SessionEffect] {
    machine.handle(event)
}

private let opened = ActionReceipt(lines: ["Abrí Safari."])!
private let notes = ActionReceipt(lines: ["Abrí Notas."])!

/// The real order of a turn with two rounds of hands: every round opens with
/// `parentActing` (which starts a step, not a turn) and closes with `parentActed`.
private func twoRounds(_ machine: inout SessionMachine, first: ActionReceipt, second: ActionReceipt) {
    _ = run(&machine, .typedSubmitted)
    _ = run(&machine, .parentActing(targets: ["Safari"]))
    _ = run(&machine, .receipt(first))
    _ = run(&machine, .parentActed)
    _ = run(&machine, .parentActing(targets: ["Notas"]))
    _ = run(&machine, .receipt(second))
    _ = run(&machine, .parentActed)
}

@Test func testTheRoundsOfOneTurnJoinIntoOneReceiptPublishedAtRest() {
    var machine = SessionMachine()
    twoRounds(&machine, first: opened, second: notes)
    expect(machine.projection.notice == nil, "recibo: a mitad del turno no se publica")
    _ = run(&machine, .typedReplyFinished)
    _ = run(&machine, .completedTimerExpired)
    expectEq(machine.projection.notice, .receipt(ActionReceipt(lines: ["Abrí Safari.", "Abrí Notas."])!),
             "recibo: las dos rondas, en un solo recibo al llegar a reposo")
}

@Test func testAStepInsideTheTurnKeepsTheReceiptButANewTurnDropsIt() {
    var machine = SessionMachine()
    twoRounds(&machine, first: opened, second: notes)
    _ = run(&machine, .typedReplyFinished)
    _ = run(&machine, .completedTimerExpired)
    _ = run(&machine, .typedSubmitted)
    expect(machine.projection.notice == nil, "recibo: un turno nuevo retira el publicado")
    _ = run(&machine, .parentActing(targets: ["Mail"]))
    _ = run(&machine, .receipt(ActionReceipt(lines: ["Abrí Mail."])!))
    _ = run(&machine, .parentActed)
    _ = run(&machine, .typedReplyFinished)
    _ = run(&machine, .completedTimerExpired)
    expectEq(machine.projection.notice, .receipt(ActionReceipt(lines: ["Abrí Mail."])!),
             "recibo: el turno nuevo empieza de cero, sin líneas del anterior")
}

@Test func testAReceiptDoesNotChangeTheKindWhileTheTurnRuns() {
    var machine = SessionMachine()
    _ = run(&machine, .typedSubmitted)
    _ = run(&machine, .receipt(opened))
    expectEq(machine.projection.kind, .processing(.thinking), "recibo: no cambia lo que hace el chrome")
}

@Test func testTheReceiptClockStartsWhenTheTurnRestsNotWhenItArrives() {
    var machine = SessionMachine()
    _ = run(&machine, .typedSubmitted)
    let arrival = run(&machine, .receipt(opened))
    expect(!arrival.contains(.scheduleNoticeExpiry(SessionMachine.receiptDelay)),
           "recibo: mientras el turno sigue no corre el reloj")
    _ = run(&machine, .typedReplyFinished)
    let rested = run(&machine, .completedTimerExpired)
    expect(rested.contains(.scheduleNoticeExpiry(SessionMachine.receiptDelay)),
           "recibo: al llegar a reposo empieza su tiempo (\(rested))")
    _ = run(&machine, .noticeExpired(.receipt(opened)))
    expect(machine.projection.notice == nil, "recibo: se va solo")
}

@Test func testAReceiptArrivingAtRestIsPublishedAndStartsItsClockAtOnce() {
    var machine = SessionMachine()
    let effects = run(&machine, .receipt(opened))
    expect(effects.contains(.scheduleNoticeExpiry(SessionMachine.receiptDelay)), "recibo: en reposo, ya")
    expectEq(machine.projection.notice, .receipt(opened), "recibo: publicado")
}

@Test func testAReceiptDismissedIsNotPublishedAgainWhenTheHoverEnds() {
    var machine = SessionMachine()
    _ = run(&machine, .receipt(opened))
    _ = run(&machine, .noticeDismissed)
    _ = run(&machine, .hoverEntered)
    _ = run(&machine, .hoverLeft)
    expect(machine.projection.notice == nil, "recibo: cerrado no reaparece al pasar el puntero")
}

@Test func testANewTurnClearsTheReceiptWithoutAnEvent() {
    var machine = SessionMachine()
    _ = run(&machine, .receipt(opened))
    let effects = run(&machine, .pressed)
    expect(machine.projection.notice == nil, "recibo: un turno nuevo lo retira")
    expect(!facts(effects).contains(.ignored(.receipt)), "recibo: retirado por un turno nuevo no es ignorado")
}

@Test func testTheModelHearsAReceiptShownClosedOrIgnored() {
    var machine = SessionMachine()
    expectEq(facts(run(&machine, .receipt(opened))), [.shown(.receipt)], "recibo: mostrado")
    expectEq(facts(run(&machine, .noticeDismissed)), [.closed(.receipt)], "recibo: cerrado por la usuaria")
    _ = run(&machine, .receipt(notes))
    expectEq(facts(run(&machine, .noticeExpired(.receipt(notes)))), [.ignored(.receipt)],
             "recibo: se fue solo, ignorado")
}

@Test func testALateClockForAGoneNoticeNeitherErasesTheReceiptNorCountsAsIgnored() {
    var machine = SessionMachine()
    _ = run(&machine, .tapped)
    _ = run(&machine, .typedSubmitted)
    _ = run(&machine, .receipt(opened))
    _ = run(&machine, .typedReplyFinished)
    _ = run(&machine, .completedTimerExpired)
    expectEq(machine.projection.notice, .receipt(opened), "reloj viejo: el recibo está publicado")
    let late = run(&machine, .noticeExpired(.holdHint))
    expectEq(machine.projection.notice, .receipt(opened), "reloj viejo: la pista de hace 6 s no borra el recibo")
    expectEq(facts(late), [], "reloj viejo: y no se registra como ignorado")
}

@Test func testTheIslandPaintsTheReceiptAsACardOnlyAtRest() {
    var machine = SessionMachine()
    _ = run(&machine, .receipt(opened))
    let state = IslandState.from(machine.projection, pebbleHidden: false)
    expectEq(state.size, .card, "recibo: es una tarjeta")
    expectEq(state.line, .receipt(opened), "recibo: la línea lleva el recibo")
    _ = run(&machine, .typedSubmitted)
    expect(IslandState.from(machine.projection, pebbleHidden: false).line != .receipt(opened),
           "recibo: con un turno en marcha manda el turno")
}

// MARK: - Re-review: a receipt never buries a notice and never comes back

private func finishTurn(_ machine: inout SessionMachine) {
    _ = run(&machine, .typedReplyFinished)
    _ = run(&machine, .completedTimerExpired)
}

private func typedTurnWithReceipt(_ machine: inout SessionMachine) {
    _ = run(&machine, .typedSubmitted)
    _ = run(&machine, .parentActing(targets: ["Safari"]))
    _ = run(&machine, .receipt(opened))
    _ = run(&machine, .parentActed)
}

@Test func testAFailureAtRestKeepsTheFailureAndTheReceiptComesOutWhenItLeaves() {
    var machine = SessionMachine()
    typedTurnWithReceipt(&machine)
    _ = run(&machine, .voice(TurnSnapshot(state: .error, failure: .notHeard)))
    expectEq(machine.projection.notice, .couldntHear, "aviso: el fallo no lo pisa el recibo")
    _ = run(&machine, .noticeExpired(.couldntHear))
    expectEq(machine.projection.notice, .receipt(opened), "aviso: al salir el fallo sale el recibo")
    var permanent = SessionMachine()
    typedTurnWithReceipt(&permanent)
    _ = run(&permanent, .voice(TurnSnapshot(state: .error, failure: .noProviders)))
    finishTurn(&permanent)
    expectEq(permanent.projection.notice, .failure(.noProviders), "aviso: un fallo que no se va solo sigue mandando")
}

@Test func testAConnectAppNoticeIsNotBuriedByTheReceiptEither() {
    var machine = SessionMachine()
    typedTurnWithReceipt(&machine)
    let card = SessionCard.connectApp(slug: "notion", name: "Notion")
    _ = run(&machine, .connectAppSuggested(slug: "notion", name: "Notion"))
    finishTurn(&machine)
    expectEq(machine.projection.notice, card, "aviso: conectar la app sigue en pantalla al llegar a reposo")
    _ = run(&machine, .noticeExpired(card))
    expectEq(machine.projection.notice, .receipt(opened), "aviso: y el recibo sale cuando esa tarjeta se va")
}

@Test func testAReceiptHeldBehindAPermanentFailureIsDroppedWhenAnythingElseStartsAtRest() {
    var machine = SessionMachine()
    typedTurnWithReceipt(&machine)
    _ = run(&machine, .voice(TurnSnapshot(state: .error, failure: .noProviders)))
    finishTurn(&machine)
    expectEq(machine.projection.notice, .failure(.noProviders), "retenido: el fallo manda")
    _ = run(&machine, .job(.started(goal: "ordenar")))
    _ = run(&machine, .jobFinished(ok: true))
    finishTurn(&machine)
    var isReceipt = false
    if case .receipt? = machine.projection.notice { isReceipt = true }
    expect(!isReceipt, "retenido: un encargo ajeno al turno no saca el recibo del turno anterior")
    var bridge = SessionMachine()
    typedTurnWithReceipt(&bridge)
    _ = run(&bridge, .voice(TurnSnapshot(state: .error, failure: .noProviders)))
    _ = run(&bridge, .parentActing(targets: ["Mail"]))
    _ = run(&bridge, .parentActed)
    finishTurn(&bridge)
    if case .receipt? = bridge.projection.notice { expect(false, "retenido: un paso del puente tampoco") }
}

@Test func testACouldntHearNoticeAtRestIsNotBuriedByTheReceipt() {
    var machine = SessionMachine()
    typedTurnWithReceipt(&machine)
    _ = run(&machine, .heardNothing)
    finishTurn(&machine)
    expectEq(machine.projection.notice, .couldntHear, "aviso: 'no te oí' no lo pisa el recibo")
}

@Test func testASeenReceiptNeverComesBackWhenItExpiresOrIsClosed() {
    for close in [SessionEvent.noticeExpired(.receipt(opened)), .noticeDismissed] {
        var machine = SessionMachine()
        _ = run(&machine, .receipt(opened))
        _ = run(&machine, close)
        expect(machine.projection.notice == nil, "visto: se fue (\(close))")
        _ = run(&machine, .parentActing(targets: ["Mail"]))
        _ = run(&machine, .parentActed)
        _ = run(&machine, .job(.started(goal: "ordenar")))
        _ = run(&machine, .jobFinished(ok: true))
        finishTurn(&machine)
        _ = run(&machine, .completedTimerExpired)
        expect(machine.projection.notice == nil,
               "visto: ni un paso del puente, ni un encargo en segundo plano lo vuelven a mostrar (\(close))")
    }
}

@Test func testALateBackgroundJobStartAfterTheReceiptWasSeenShowsNothing() {
    var machine = SessionMachine()
    _ = run(&machine, .receipt(opened))
    _ = run(&machine, .noticeExpired(.receipt(opened)))
    expect(machine.projection.job == nil, "tardío: no hay encargo")
    _ = run(&machine, .job(.started(goal: "tarde")))
    _ = run(&machine, .jobFinished(ok: true))
    expect(machine.projection.notice == nil, "tardío: el recibo visto no reaparece")
}

// MARK: - From the runtime and the chat

private final class ProofTools: ParentToolExecuting, @unchecked Sendable {
    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { true }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        switch name {
        case "read_focused": ParentToolOutcome(ok: true, output: "hola mundo", tool: name, fieldPID: 10)
        case "type_text": ParentToolOutcome(ok: true, output: "typed", tool: name, fieldPID: 10, typedBefore: 0)
        default: ParentToolOutcome(ok: true, output: "opened", target: "Safari", tool: name)
        }
    }
}

@MainActor private func receipts(calls: [ToolCallRef]) async -> [ActionReceipt] {
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "abre Safari"
    let chat = ScriptedChat()
    chat.rounds = [[.toolCalls(calls)], [.text("Listo.")]]
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: ScriptedSynth(), chat: chat, thread: ScriptedThread())
    runtime.parentTools = ProofTools()
    let box = AudioStreamBox<SessionEvent>()
    runtime.events = box
    await runtime.submit(config: Config(language: .es)) { _ in }
    box.finish()
    var found: [ActionReceipt] = []
    for await event in box.stream { if case .receipt(let r) = event { found.append(r) } }
    return found
}

@Test @MainActor func testTheClassicTurnEmitsAReceiptOnlyForProvenEffects() async {
    let open = ToolCallRef(id: "o1", name: "open_app", arguments: #"{"name":"Safari"}"#)
    let type = ToolCallRef(id: "t1", name: "type_text", arguments: #"{"text":"hola"}"#)
    let read = ToolCallRef(id: "r1", name: "read_focused", arguments: "{}")
    let proven = await receipts(calls: [open, type, read])
    expectEq(proven.flatMap(\.lines), ["Abrí Safari.", "Escribí el texto."], "turno: abrir y escribir comprobado")
    expectEq(proven.flatMap(\.entries).map(\.verified), [false, true],
             "turno: solo lo escrito con lectura posterior va como comprobado")
    let unproven = await receipts(calls: [type])
    expectEq(unproven.count, 0, "turno: escribir sin lectura no emite recibo")
    let reading = await receipts(calls: [read])
    expectEq(reading.count, 0, "turno: solo leer no emite recibo")
}

private final class OpenTools: ParentToolExecuting, @unchecked Sendable {
    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { true }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        ParentToolOutcome(ok: true, output: "opened", target: "Safari", tool: name)
    }
}

@Test @MainActor func testTheChatTurnLeavesAReceiptOnTheIsland() async {
    let call = ToolCallRef(id: "o1", name: "open_app", arguments: #"{"name":"Safari"}"#)
    let chat = FakeChatProvider(replies: [.success([.toolCalls([call])]), .success([.text("Listo.")])])
    let vm = primed(chat: chat, parentTools: OpenTools(), config: Config(language: .es))
    vm.draft = "abre Safari"
    vm.send()
    await pumpUntil("recibo: publicado al llegar a reposo") { vm.session.projection.notice != nil }
    expectEq(vm.session.projection.notice, .receipt(opened), "chat: el turno tecleado deja su recibo")
}

// MARK: - The card

@Test @MainActor func testTheReceiptCardUsesTheMeasuredRunCardSurface() {
    expectEq(ReceiptMetrics.minWidth, WorkStateMetrics.runMinWidth, "medida: ancho mín de la tarjeta de ejecución")
    expectEq(ReceiptMetrics.maxWidth, WorkStateMetrics.runMaxWidth, "medida: ancho máx")
    expectEq(ReceiptMetrics.eyebrowAlpha, 0.42, "medida: eyebrow de ov-card al 42 %")
    expectEq(ReceiptMetrics.checkHex, "8CDC96", "medida: verde de éxito del aviso de la isla")
}

@Test @MainActor func testTheReceiptSpeaksToVoiceOverInBothLanguages() {
    for language in [AppLanguage.es, .en] {
        for key in ["island.receipt.title", "island.receipt.dismiss", "island.receipt.check"] {
            expect(Localized.string(key, language: language) != key, "recibo (\(language)): falta \(key)")
        }
    }
    let spoken = IslandReceipt.announcement(opened, language: .es)
    expect(spoken.contains("Abrí Safari.") && spoken.contains(Localized.string("island.receipt.title", language: .es)),
           "recibo: el anuncio dice título y línea — \(spoken)")
}

// MARK: - QA: the limits of the receipt, pinned

@Test @MainActor func testRealtimeToolsThatSucceedLeaveNoReceiptAcceptedLimitation() async {
    let h = makeVoiceHarness(parentTools: ParentToolRunner(workspace: FakeWorkspaceOpener()))
    let seen = SessionEventBox(h.session.events)
    await h.session.start()
    await pumpUntil("realtime: listening") { h.watch.latest.state == .listening }
    h.transport.yield(.functionCall(name: "open_app", arguments: #"{"name":"Safari"}"#, callId: "c1"))
    await pumpUntil("realtime: la herramienta corrió") { seen.events.contains { $0 == .parentActed } }
    await pumpUntil("realtime: y el servidor recibió su salida") {
        h.transport.sent.contains { $0.contains("function_call_output") && $0.contains("c1") }
    }
    let receipts = seen.events.filter { if case .receipt = $0 { true } else { false } }
    expectEq(receipts.count, 0, "realtime: limitación aceptada, una herramienta ok no emite recibo (lo acusa la voz)")
}

private final class TypingTools: ParentToolExecuting, @unchecked Sendable {
    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { true }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        name == "type_text"
            ? ParentToolOutcome(ok: true, output: "typed", tool: name, fieldPID: 10, typedBefore: 0)
            : ParentToolOutcome(ok: true, output: "opened", target: "Safari", tool: name)
    }
}

@Test @MainActor func testInChatTypingNeverProducesAReceiptLineAndNeverOverclaims() async {
    let open = ToolCallRef(id: "o1", name: "open_app", arguments: #"{"name":"Safari"}"#)
    let type = ToolCallRef(id: "t1", name: "type_text", arguments: #"{"text":"hola"}"#)
    let mixed = FakeChatProvider(replies: [.success([.toolCalls([open, type])]), .success([.text("Listo.")])])
    let vm = primed(chat: mixed, parentTools: TypingTools(), config: Config(language: .es))
    vm.draft = "abre Safari y escribe hola"
    vm.send()
    await pumpUntil("chat mixto: recibo publicado") { vm.session.projection.notice != nil }
    guard case .receipt(let receipt)? = vm.session.projection.notice else {
        expect(false, "chat mixto: el aviso es un recibo")
        return
    }
    expectEq(receipt.lines, ["Abrí Safari."], "chat mixto: solo lo probado, escribir sin lectura no entra")
    expectEq(receipt.entries.map(\.verified), [false],
             "chat mixto: 'Hecho', nunca 'comprobado': el chat no lee de vuelta")

    let only = FakeChatProvider(replies: [.success([.toolCalls([type])]), .success([.text("Listo.")])])
    let typing = primed(chat: only, parentTools: TypingTools(), config: Config(language: .es))
    typing.draft = "escribe hola"
    typing.send()
    await pumpUntil("chat escribir: el turno terminó") { !typing.busy && typing.session.projection.kind == .idle }
    expect(typing.session.projection.notice == nil, "chat escribir: sin lectura posterior no hay recibo")
}

private final class NamedTools: ParentToolExecuting, @unchecked Sendable {
    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { true }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        let app = (try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8)) as? [String: String])?["name"] ?? "?"
        return ParentToolOutcome(ok: true, output: "opened", target: app, tool: name)
    }
}

@Test @MainActor func testSixOpensReachTheReceiptAsTheLastFourAndTheVoiceSaysAllOfThem() async {
    let apps = ["Uno", "Dos", "Tres", "Cuatro", "Cinco", "Seis"]
    let calls = apps.enumerated().map { ToolCallRef(id: "o\($0.offset)", name: "open_app", arguments: #"{"name":"\#($0.element)"}"#) }
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "abre todo"
    let synth = ScriptedSynth()
    let chat = ScriptedChat()
    // The reply is the kind the filter swallows, so the app itself says the effects.
    chat.rounds = [[.toolCalls(calls)], [.text("Acusa en una línea: abrí todo.")]]
    let runtime = ClassicRuntime(transcriber: transcriber, synthesizer: synth, chat: chat, thread: ScriptedThread())
    runtime.parentTools = NamedTools()
    let box = AudioStreamBox<SessionEvent>()
    runtime.events = box
    // Read while the turn runs: finishing the stream first would only prove
    // that the events exist, not the order they were emitted in.
    let reader = Task { () -> [SessionEvent] in
        var all: [SessionEvent] = []
        for await event in box.stream { all.append(event) }
        return all
    }
    await runtime.submit(config: Config(language: .es)) { _ in }
    box.finish()
    let events = await reader.value

    let kinds = events.compactMap { event -> String? in
        switch event {
        case .parentActing: "acting"
        case .receipt: "receipt"
        case .parentActed: "acted"
        default: nil
        }
    }
    expectEq(kinds, ["acting", "receipt", "acted"], "orden: parentActing, recibo y parentActed, en ese orden")
    let receipt = events.compactMap { if case .receipt(let r) = $0 { r } else { nil } }.first
    expectEq(receipt?.lines, ["Abrí Tres.", "Abrí Cuatro.", "Abrí Cinco.", "Abrí Seis."],
             "recibo: las últimas cuatro de seis")
    let spoken = synth.queue
    for line in receipt?.lines ?? [] {
        expect(spoken.contains(line), "voz: dice «\(line)», así el recibo nunca afirma más que ella (\(spoken))")
    }
    for app in apps {
        expect(spoken.contains("Abrí \(app)."), "voz: y dice también las que el recibo no cabe («\(app)»)")
    }
}
