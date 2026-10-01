import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import CompanionCoreTestSupport
import CompanionTestKit
import CompanionUITestSupport
import Foundation
import Testing

// 16q-2, decision 5: the question card works like Incredible's. A click or a
// key selects, Confirm sends; several picks when the fence says so; an answer
// in her own words when the fence allows it; and the agent keeps every
// connector. Deliberate difference: 1-9 stay as SELECT shortcuts (keyboard
// accessibility), they never send. Untouchable: a card answer is never
// consent (said = "" for the gate and noteTurn).

private func fence(_ json: String) -> String { "```companion:choice\n\(json)\n```" }

@MainActor private func abc(multiple: Bool = false, allowText: Bool = false) -> ChoiceBlock {
    ChoiceBlock(
        question: "¿Cuáles?",
        options: [.init(label: "A"), .init(label: "B"), .init(label: "C")],
        multiple: multiple, allowText: allowText)
}

// MARK: - Core: the fence and the reply

@Test @MainActor func fenceDeclaresMultipleAndFreeText() {
    let plain = CompanionBlocks.choice(#"{"question":"q","options":["A","B"]}"#)
    expect(plain?.multiple == false && plain?.allowText == false, "16q-2: sin banderas, una tarjeta como la de siempre")
    let both = CompanionBlocks.choice(#"{"question":"q","multiple":true,"allowText":true,"options":["A","B"]}"#)
    expect(both?.multiple == true, "16q-2: multiple: true declara seleccion multiple")
    expect(both?.allowText == true, "16q-2: allowText: true declara respuesta libre")
    let junk = CompanionBlocks.choice(#"{"question":"q","multiple":"yes","allowText":null,"options":["A","B"]}"#)
    expect(junk != nil, "16q-2: una bandera mal tipada no rompe la fence")
    expect(junk?.multiple == false && junk?.allowText == false, "16q-2: y se lee como apagada")
}

@Test @MainActor func multipleRepliesAreOptionOrderAndReadBack() {
    let block = abc(multiple: true)
    expectEq(block.reply(for: [2, 0]), "A, C", "16q-2: la respuesta va en el orden de las opciones")
    expectEq(block.reply(for: [1, 1, 9, -1]), "B", "16q-2: sin repetidos ni indices fuera de rango")
    expectEq(block.reply(for: []), "", "16q-2: sin nada, respuesta vacia")
    expectEq(block.resolution(reply: "A, C"), .chosenMany([0, 2]), "16q-2: la respuesta multiple marca las elegidas")
    expectEq(block.resolution(reply: "B"), .chosen(1), "16q-2: una sola es una eleccion normal")
    expectEq(block.resolution(reply: "C, A"), .passed, "16q-2: fuera de orden no es una respuesta de la tarjeta")
    expectEq(block.resolution(reply: "A, D"), .passed, "16q-2: con algo que no es opcion, respuesta libre")
    expectEq(abc().resolution(reply: "A, C"), .passed, "16q-2: una tarjeta simple no lee listas")

    let commas = ChoiceBlock(question: "q", options: [.init(label: "Rojo, azul"), .init(label: "Verde")], multiple: true)
    expectEq(commas.resolution(reply: "Rojo, azul, Verde"), .chosenMany([0, 1]), "16q-2: una etiqueta con coma no se parte")
    expectEq(commas.resolution(reply: "Rojo, azul"), .chosen(0), "16q-2: y sola sigue siendo ella")
}

// MARK: - State: a click selects, Confirm sends

@Test @MainActor func aClickSelectsAndOnlyConfirmSends() {
    let block = abc()
    var state = IslandChoiceState()
    var sent: [String] = []
    state.select(0, block: block, resolution: .open, queued: [])
    expectEq(sent, [], "16q-2: seleccionar no envia nada")
    expectEq(state.selection, [0], "16q-2: queda seleccionada")
    state.select(2, block: block, resolution: .open, queued: [])
    expectEq(state.selection, [2], "16q-2: en una tarjeta simple otra seleccion sustituye")
    expect(state.confirm(block: block, resolution: .open, queued: [], send: { sent.append($0); return true }),
           "16q-2: Confirmar envia")
    expectEq(sent, ["C"], "16q-2: la etiqueta elegida, una vez")
    expect(!state.confirm(block: block, resolution: .open, queued: ["C"], send: { sent.append($0); return true }),
           "16q-2: un segundo Confirmar no manda otra respuesta")
    expectEq(sent, ["C"], "16q-2: sigue siendo una")
    expectEq(state.effective(resolution: .open, queued: ["C"]), .chosen(2), "16q-2: en cola cuenta como elegida")
}

@Test @MainActor func confirmWithNothingSelectedSendsNothing() {
    var state = IslandChoiceState()
    var calls = 0
    expect(!state.confirm(block: abc(), resolution: .open, queued: [], send: { _ in calls += 1; return true }),
           "16q-2: sin seleccion Confirmar no hace nada")
    expectEq(calls, 0, "16q-2: y no llama a enviar")
}

@Test @MainActor func multipleSelectionTogglesAndSendsInOptionOrder() {
    let block = abc(multiple: true)
    var state = IslandChoiceState()
    var sent: [String] = []
    for index in [2, 0, 1, 0] { state.select(index, block: block, resolution: .open, queued: []) }
    expectEq(state.selection, [1, 2], "16q-2: seleccion multiple: alterna y se guarda ordenada")
    state.confirm(block: block, resolution: .open, queued: [], send: { sent.append($0); return true })
    expectEq(sent, ["B, C"], "16q-2: se envia una respuesta con las elegidas en orden")
    expectEq(state.effective(resolution: .open, queued: ["B, C"]), .chosenMany([1, 2]),
             "16q-2: en cola cuentan las dos")
}

@Test @MainActor func aRefusedSendKeepsTheSelectionAndTheCardOpen() {
    let block = abc()
    var state = IslandChoiceState()
    state.select(1, block: block, resolution: .open, queued: [])
    expect(!state.confirm(block: block, resolution: .open, queued: [], send: { _ in false }), "16q-2: no salio")
    expect(state.pending == nil, "16q-2: nada pendiente")
    expectEq(state.selection, [1], "16q-2: la seleccion sigue para reintentar")
    expectEq(state.effective(resolution: .open, queued: []), .open, "16q-2: la tarjeta sigue abierta")
}

@Test @MainActor func nothingChangesOnceTheQuestionIsAnswered() {
    let block = abc(multiple: true, allowText: true)
    var state = IslandChoiceState()
    for resolution in [ChoiceBlock.Resolution.chosen(0), .chosenMany([0, 1]), .passed] {
        state.select(1, block: block, resolution: resolution, queued: [])
        state.setText("tarde", block: block, resolution: resolution, queued: [])
    }
    expect(state.selection.isEmpty && state.text.isEmpty, "16q-2: respondida, ni se selecciona ni se escribe")
    state.select(7, block: block, resolution: .open, queued: [])
    state.select(-1, block: block, resolution: .open, queued: [])
    expect(state.selection.isEmpty, "16q-2: fuera de rango se ignora")
}

// MARK: - State: her own words

@Test @MainActor func freeTextOnlyWorksWhenTheFenceAllowsIt() {
    var closed = IslandChoiceState()
    closed.setText("otra cosa", block: abc(), resolution: .open, queued: [])
    expectEq(closed.text, "", "16q-2: sin allowText el campo no guarda nada")
    var calls = 0
    closed.confirm(block: abc(), resolution: .open, queued: [], send: { _ in calls += 1; return true })
    expectEq(calls, 0, "16q-2: y Confirmar no manda texto")
}

@Test @MainActor func freeTextIsTheAlternativeToThePicks() {
    let block = abc(multiple: true, allowText: true)
    var state = IslandChoiceState()
    var sent: [String] = []
    state.select(0, block: block, resolution: .open, queued: [])
    state.setText("  una tercera   via \n", block: block, resolution: .open, queued: [])
    expect(state.selection.isEmpty, "16q-2: escribir vacia la seleccion: son alternativas")
    state.select(1, block: block, resolution: .open, queued: [])
    expectEq(state.text, "", "16q-2: seleccionar vacia lo escrito")
    state.setText("  una tercera   via \n", block: block, resolution: .open, queued: [])
    state.confirm(block: block, resolution: .open, queued: [], send: { sent.append($0); return true })
    expectEq(sent, ["una tercera via"], "16q-2: se envia su texto, en una linea y sin bordes")
    expectEq(state.effective(resolution: .open, queued: ["una tercera via"]), .passed,
             "16q-2: un texto libre responde la tarjeta sin marcar opcion")
}

@Test @MainActor func aBlankOrHugeAnswerIsHandledAtTheBoundary() {
    let block = abc(allowText: true)
    var state = IslandChoiceState()
    var sent: [String] = []
    state.setText(" \n\t ", block: block, resolution: .open, queued: [])
    expect(!state.confirm(block: block, resolution: .open, queued: [], send: { sent.append($0); return true }),
           "16q-2: un texto en blanco no se envia")
    state.setText(String(repeating: "ñ", count: ChoiceBlock.maxAnswer * 3), block: block, resolution: .open, queued: [])
    state.confirm(block: block, resolution: .open, queued: [], send: { sent.append($0); return true })
    expectEq(sent.first?.count, ChoiceBlock.maxAnswer, "16q-2: el tope de la respuesta libre es exacto")
    var emoji = IslandChoiceState()
    emoji.setText("<b>hola</b> \u{1F600}\u{202E}", block: block, resolution: .open, queued: [])
    expect(!emoji.text.unicodeScalars.contains { $0.value == 0x202E }, "16q-2: sin escalares bidi en lo que se envia")
}

// MARK: - Keys: select, never send

@Test @MainActor func keysSelectAndReturnConfirms() {
    typealias K = IslandChoiceKeys
    expectEq(K.outcome(for: .digit(2), focused: nil, count: 3, hasSelection: true), .select(1),
             "16q-2: un digito selecciona, aunque ya haya seleccion; no envia")
    expectEq(K.outcome(for: .digit(2), focused: nil, count: 3, hasSelection: false), .select(1),
             "16q-2: y tampoco envia sin ella (diferencia deliberada con Incredible: existen)")
    expectEq(K.outcome(for: .space, focused: 2, count: 3), .select(2), "16q-2: espacio selecciona la del cursor")
    expectEq(K.outcome(for: .space, focused: nil, count: 3), .none, "16q-2: espacio sin cursor no hace nada")
    expectEq(K.outcome(for: .enter, focused: 1, count: 3, hasSelection: true), .confirm,
             "16q-2: Return con algo seleccionado confirma")
    expectEq(K.outcome(for: .enter, focused: 1, count: 3, hasSelection: false), .select(1),
             "16q-2: Return sin seleccion selecciona la del cursor (el siguiente Return confirma)")
    expectEq(K.outcome(for: .enter, focused: nil, count: 3, hasSelection: true), .confirm,
             "16q-2: con seleccion, Return confirma aunque el cursor no este")
    expectEq(K.outcome(for: .enter, focused: nil, count: 3, hasSelection: false), .none,
             "16q-2: sin cursor ni seleccion, Return no hace nada")
    expectEq(K.key(.space, characters: " ", hasModifiers: false), .space, "16q-2: la tecla espacio")
    expect(K.key(.space, characters: " ", hasModifiers: true) == nil, "16q-2: con modificador se ignora")
    for key in [K.Key.space, .enter] {
        expectEq(K.outcome(for: key, focused: 0, count: 0, hasSelection: true), .none, "16q-2: sin opciones no hay teclas")
    }
}

@Test @MainActor func tilesShowTheSelectionBeforeTheSend() {
    typealias S = IslandChoiceState
    expectEq((0 ..< 3).map { S.tile(index: $0, resolution: .open, cursor: 0, selection: [1, 2]) },
             [.cursor, .selected, .selected], "16q-2: las seleccionadas se ven antes de enviar")
    expectEq((0 ..< 3).map { S.tile(index: $0, resolution: .chosenMany([0, 2]), cursor: nil) },
             [.picked, .unavailable, .picked], "16q-2: las enviadas quedan marcadas")
    expectEq((0 ..< 2).map { S.tile(index: $0, resolution: .passed, cursor: nil, selection: [0]) },
             [.unavailable, .unavailable], "16q-2: respondida por otra via, apagadas")
}

@Test @MainActor func theThreadMarksEveryPickedOption() {
    let block = abc(multiple: true)
    let ask = ChatMessage(role: .assistant, text: "¿Cuáles?\n" + fence(#"{"question":"q","multiple":true,"options":["A","B","C"]}"#))
    let reply = ChatMessage(role: .user, text: "A, C")
    expectEq(IslandChoice.resolution(of: block, messageID: ask.id, in: [ask, reply]), .chosenMany([0, 2]),
             "16q-2: el hilo marca las dos")
    let free = ChatMessage(role: .user, text: "ninguna, gracias")
    expectEq(IslandChoice.resolution(of: block, messageID: ask.id, in: [ask, free]), .passed,
             "16q-2: la respuesta libre cierra la pregunta sin marca")
}

// MARK: - Tools: a card turn keeps every connector, and stays no consent

private final class SlackApps: AppsService, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(tool: String, approved: Bool)] = []
    var calls: [(tool: String, approved: Bool)] { lock.withLock { recorded } }
    func catalog(query: String, after: String?) async throws -> CatalogPage { CatalogPage(apps: [], total: 0, next: nil) }
    func accounts() async throws -> [ConnectedAccount] {
        [ConnectedAccount(id: "apn_1", app: "slack_v2", name: "karen@x", state: .connected)]
    }
    func connectLink(app: String) async throws -> URL { throw AppsFailure.unexpected }
    func tools(app: String) async throws -> [AppAction] {
        [AppAction(slug: "slack_v2-send-message", name: "Send Message", description: "Send a message",
                   group: .crearYCambiar, schemaJSON: #"{"type":"object","properties":{"text":{"type":"string"}}}"#),
         AppAction(slug: "slack_v2-list-channels", name: "List Channels", description: "List channels", group: .leer)]
    }
    func disconnect(account: String) async throws {}
    func call(app: String, tool: String, argumentsJSON: String, approved: Bool) async throws -> AppCallResult {
        lock.withLock { recorded.append((tool, approved)) }
        return AppCallResult(isError: false, text: "sent")
    }
}

private func slackRunner(_ service: SlackApps) async -> AppToolRunner {
    let runner = AppToolRunner(service: { service }, catalog: [], suggest: nil)
    await runner.refresh()
    return runner
}

@Test func aCardTurnOffersEveryConnectedAppAndATypedTurnStillNarrows() async {
    let runner = await slackRunner(SlackApps())
    runner.noteChoiceTurn()
    expectEq(runner.specs(.es).count, 2, "16q-2: un turno de tarjeta lleva las tools de todo lo conectado")
    runner.noteTurn("dime la hora")
    expect(runner.specs(.es).isEmpty, "16q-2: un turno tecleado que no nombra app sigue sin ellas")
    runner.noteChoiceTurn()
    _ = runner.specs(.es)
    expectEq(runner.specs(.es).count, 2, "16q-2: y la lectura siguiente vuelve a todo, como cualquier turno")
}

@Test func aCardTurnStillNeedsTheSheetForAnAppWrite() async {
    let service = SlackApps()
    let runner = await slackRunner(service)
    runner.noteChoiceTurn()
    let write = ToolCallRef(id: "1", name: "slack_v2-send-message", arguments: #"{"text":"hola"}"#)
    expect(runner.approval(for: write, said: "") != nil, "16q-2: una escritura de app pide su hoja con said vacio")
    let refused = await runner.execute(name: "slack_v2-send-message", argumentsJSON: #"{"text":"hola"}"#)
    expect(!refused.ok && service.calls.isEmpty, "16q-2: sin clic no llega a la funcion")
}

@Test func aGrantDiesWhenTheCardTurnBegins() async {
    let service = SlackApps()
    let runner = await slackRunner(service)
    runner.noteTurn("manda un slack")
    let write = ToolCallRef(id: "1", name: "slack_v2-send-message", arguments: #"{"text":"hola"}"#)
    if let request = runner.approval(for: write, said: "manda un slack") { runner.granted(request) }
    runner.noteChoiceTurn()
    let stale = await runner.execute(name: "slack_v2-send-message", argumentsJSON: #"{"text":"hola"}"#)
    expect(!stale.ok, "16q-2: el clic de un turno no autoriza escribir en el turno de tarjeta")
    expect(service.calls.isEmpty, "16q-2: nada salio")
}

/// Records what the chat tells the runner and what the gate is asked with.
private final class CardTap: ParentToolExecuting, @unchecked Sendable {
    let inner: AppToolRunner
    let lock = NSLock()
    var typed: [String] = []
    var choiceTurns = 0
    var saidAtGate: [String] = []
    init(_ inner: AppToolRunner) { self.inner = inner }
    func specs(_ language: AppLanguage) -> [ToolSpec] { inner.specs(language) }
    func handles(_ name: String) -> Bool { inner.handles(name) }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        await inner.execute(name: name, argumentsJSON: argumentsJSON)
    }
    func approval(for call: ToolCallRef, said: String) -> ApprovalRequest? {
        lock.withLock { saidAtGate.append(said) }
        return inner.approval(for: call, said: said)
    }
    func granted(_ request: ApprovalRequest) { inner.granted(request) }
    func noteTurn(_ said: String) { lock.withLock { typed.append(said) }; inner.noteTurn(said) }
    func noteChoiceTurn() { lock.withLock { choiceTurns += 1 }; inner.noteChoiceTurn() }
}

@Test @MainActor func aChoiceReachesTheAppsWithoutBecomingConsent() async {
    let service = SlackApps()
    let tap = CardTap(await slackRunner(service))
    let write = ChatDelta.toolCalls([ToolCallRef(id: "c1", name: "slack_v2-send-message", arguments: #"{"text":"Enviar a Fer"}"#)])
    let chat = FakeChatProvider(replies: [.success([write]), .success([.text("Hecho")])])
    let vm = primed(chat: chat, parentTools: tap, approvals: FakeApprovals())
    vm.choose("Enviar a Fer")
    await pumpUntil("16q-2: la hoja aparece para la escritura") { vm.pendingApproval != nil }
    expect(chat.histories.count >= 1, "16q-2: el turno pidio al modelo")
    expectEq(tap.choiceTurns, 1, "16q-2: el turno se anuncia como de tarjeta")
    expectEq(tap.typed, [], "16q-2: y no como palabras suyas: noteTurn no recibe la etiqueta")
    expectEq(tap.saidAtGate, [""], "16q-2: la compuerta recibe said vacio: una eleccion no es consentimiento")
    expect(service.calls.isEmpty, "16q-2: la escritura espera su hoja")
    vm.answerApproval(false)
    await pumpUntil("16q-2: idle") { !vm.busy }
    expect(service.calls.isEmpty, "16q-2: con no, no se escribe")
}

@Test @MainActor func aChoiceTurnsFirstRequestCarriesTheAppTools() async {
    let tap = CardTap(await slackRunner(SlackApps()))
    let chat = FakeChatProvider(replies: [.success([.text("Listo")])])
    let vm = primed(chat: chat, parentTools: tap)
    vm.choose("Rápido")
    await pumpUntil("16q-2: idle") { !vm.busy }
    expect(chat.toolsSeen.map(\.name).contains("slack_v2-send-message"),
           "16q-2: la primera peticion de un turno de eleccion ya lleva las tools de apps")

    let typedTap = CardTap(await slackRunner(SlackApps()))
    let typedChat = FakeChatProvider(replies: [.success([.text("Listo")])])
    let typed = primed(chat: typedChat, parentTools: typedTap)
    typed.draft = "dime la hora"
    typed.send()
    await pumpUntil("16q-2: idle tecleado") { !typed.busy }
    expect(!typedChat.toolsSeen.map(\.name).contains("slack_v2-send-message"),
           "16q-2: un turno tecleado sin nombrar la app sigue sin ellas")
    expectEq(typedTap.typed, ["dime la hora"], "16q-2: lo tecleado sigue llegando a noteTurn")
}

// MARK: - The model learns the two flags

@Test func theVocabularyTeachesMultipleAndFreeText() {
    for language in [AppLanguage.en, .es] {
        let vocabulary = CardVocabulary.text(language)
        expect(vocabulary.contains("\"multiple\""), "16q-2 (\(language)): el vocabulario ensena multiple")
        expect(vocabulary.contains("\"allowText\""), "16q-2 (\(language)): y allowText")
        expect(vocabulary.contains("\(ChoiceBlock.maxOptions)"), "16q-2 (\(language)): el tope de opciones sigue ahi")
    }
}
