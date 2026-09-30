import CompanionCore
import CompanionServices
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

// Wave 16m-6, review round: the card's send/pending rules, focus, the origin
// mark the model sees, the stale card, and the notice source's edges.

private let sampleFence = "```companion:choice\n"
    + #"{"question":"¿Cómo?","options":["Rápido","Completo","Solo números"]}"#
    + "\n```"

@MainActor private func msg(
    _ role: TurnRole?, _ text: String, status: Bool = false, failure: Bool = false, restored: Bool = false
) -> ChatMessage {
    ChatMessage(role: role, isStatus: status, text: text, isFailure: failure, restored: restored)
}

@MainActor private func threeOptions() -> ChoiceBlock {
    ChoiceBlock(question: "¿Cómo?", options: [.init(label: "Rápido"), .init(label: "Completo"), .init(label: "Solo números")])
}

// MARK: - Resolution rules

@Test @MainActor func choiceResolutionRulesTests() {
    let block = threeOptions()
    let ask = msg(.assistant, sampleFence)
    func resolve(_ thread: [ChatMessage], _ target: ChatMessage? = nil) -> ChoiceBlock.Resolution {
        IslandChoice.resolution(of: block, messageID: (target ?? ask).id, in: thread)
    }
    expectEq(resolve([ask, msg(.user, "otra cosa"), msg(.user, "Rápido")]), .passed,
             "16m-6 fix: lo primero que ella dijo cierra la pregunta")
    let again = msg(.assistant, sampleFence)
    expectEq(resolve([ask, msg(.user, "Rápido"), again], again), .open,
             "16m-6 fix: la misma pregunta otra vez arranca abierta")
    expectEq(resolve([ask, msg(.user, "Rápido"), again], ask), .chosen(0),
             "16m-6 fix: y la vieja conserva su marca")

    let long = String(repeating: "ñ", count: 500)
    let capped = CompanionBlocks.choice(#"{"question":"¿?","options":["\#(long)","B"]}"#)
    let label = capped?.options.first?.label ?? ""
    expectEq(IslandChoice.resolution(of: capped ?? block, messageID: ask.id, in: [ask, msg(.user, label)]),
             .chosen(0), "16m-6 fix: la etiqueta recortada resuelve con el mensaje recortado que se envió")

    expectEq(resolve([ask, msg(.user, "rápido")]), .passed,
             "16m-6 fix: la comparación distingue mayúsculas: «rápido» no es la etiqueta «Rápido», así que cuenta como otra respuesta")
    expectEq(resolve([ask, msg(.user, "")]), .passed, "16m-6 fix: un turno solo con adjuntos cierra la pregunta")

    let failure = msg(nil, "No pude conectar", status: true, failure: true)
    expectEq(resolve([ask, msg(.user, "Rápido"), failure]), .open,
             "16m-6 fix: un turno fallido devuelve la pregunta para reintentar")
    expectEq(resolve([ask, msg(.user, "Rápido"), failure, msg(.user, "Completo")]), .chosen(1),
             "16m-6 fix: el reintento la vuelve a responder")
    expectEq(resolve([ask, msg(.user, "Rápido"), msg(nil, "Job en marcha", status: true)]), .chosen(0),
             "16m-6 fix: una línea de estado que no es fallo no reabre")

    let old = msg(.assistant, sampleFence, restored: true)
    expectEq(resolve([old], old), .passed, "16m-6 fix: una pregunta restaurada sin respuesta no tiene turno vivo")
    expectEq(resolve([old, msg(.user, "Rápido", restored: true)], old), .chosen(0),
             "16m-6 fix: una restaurada ya respondida conserva su marca")
    expectEq(resolve([ask], ask), .open, "16m-6 fix: la del turno vivo sí queda abierta")

    let record = ConversationRecord(id: "x", title: "t", updatedAt: Date(), messages: [
        ConversationMessage(role: "assistant", text: "a"), ConversationMessage(role: "status", text: "s"),
    ])
    expect(ChatViewModel.messages(of: record).allSatisfy(\.restored), "16m-6 fix: lo leído de disco se marca restaurado")
}

/// The two steps the card takes now (16q-2): a click selects, Confirm sends.
/// The old one-step tests keep their subject (pending, queue, refusals) by
/// walking both.
@MainActor @discardableResult
private func sendPick(
    _ state: inout IslandChoiceState, _ index: Int, block: ChoiceBlock,
    resolution: ChoiceBlock.Resolution, queued: [String], send: (String) -> Bool
) -> Bool {
    state.select(index, block: block, resolution: resolution, queued: queued)
    return state.confirm(block: block, resolution: resolution, queued: queued, send: send)
}

// MARK: - Pending and picking

@Test @MainActor func islandChoiceStateTests() {
    let block = threeOptions()
    var sent: [String] = []
    var state = IslandChoiceState()

    let first = sendPick(&state, 0, block: block, resolution: .open, queued: [], send: { sent.append($0); return true })
    expect(first, "16m-6 fix: el primer pick sale")
    let second = sendPick(&state, 2, block: block, resolution: .open, queued: ["Rápido"], send: { sent.append($0); return true })
    expect(!second, "16m-6 fix: clic y luego dígito no mandan dos respuestas")
    expectEq(sent, ["Rápido"], "16m-6 fix: un solo envío con la primera etiqueta")

    expectEq(state.effective(resolution: .open, queued: ["Rápido"]), .chosen(0), "16m-6 fix: en cola cuenta como elegida")
    expectEq(state.effective(resolution: .open, queued: []), .open,
             "16m-6 fix: la cola vaciada (cancelar, cambiar de conversación) devuelve la tarjeta")
    expectEq(state.effective(resolution: .chosen(1), queued: []), .chosen(1), "16m-6 fix: el hilo manda sobre lo local")
    expectEq(state.effective(resolution: .passed, queued: ["Rápido"]), .passed, "16m-6 fix: respondida por otra vía")

    var refused = IslandChoiceState()
    var attempts = 0
    let none = sendPick(&refused, 1, block: block, resolution: .open, queued: [], send: { _ in attempts += 1; return false })
    expect(!none && refused.pending == nil, "16m-6 fix: si choose no aceptó, no queda pendiente")
    expectEq(refused.effective(resolution: .open, queued: []), .open, "16m-6 fix: y la tarjeta sigue abierta")
    _ = sendPick(&refused, 1, block: block, resolution: .open, queued: [], send: { _ in attempts += 1; return true })
    expectEq(attempts, 2, "16m-6 fix: se puede volver a intentar")

    var answered = IslandChoiceState()
    var calls = 0
    _ = sendPick(&answered, 0, block: block, resolution: .chosen(1), queued: [], send: { _ in calls += 1; return true })
    _ = sendPick(&answered, 0, block: block, resolution: .passed, queued: [], send: { _ in calls += 1; return true })
    _ = sendPick(&answered, 7, block: block, resolution: .open, queued: [], send: { _ in calls += 1; return true })
    _ = sendPick(&answered, -1, block: block, resolution: .open, queued: [], send: { _ in calls += 1; return true })
    expectEq(calls, 0, "16m-6 fix: un pick tras responder o fuera de rango se ignora")

    typealias S = IslandChoiceState
    expectEq((0 ..< 3).map { S.tile(index: $0, resolution: .chosen(1), cursor: nil) },
             [.unavailable, .picked, .unavailable], "16m-6 fix: la resuelta marca la elegida")
    expectEq((0 ..< 3).map { S.tile(index: $0, resolution: .passed, cursor: 1) },
             [.unavailable, .unavailable, .unavailable], "16m-6 fix: respondida por otra vía, todas apagadas")
    expectEq((0 ..< 3).map { S.tile(index: $0, resolution: .open, cursor: 2) },
             [.idle, .idle, .cursor], "16m-6 fix: abierta muestra el cursor")
}

// MARK: - Keys and focus

@Test @MainActor func islandChoiceKeyParsingTests() {
    typealias K = IslandChoiceKeys
    expectEq(K.key(.other, characters: "3", hasModifiers: false), .digit(3), "16m-6 fix: dígito ASCII")
    expectEq(K.key(.other, characters: "9", hasModifiers: false), .digit(9), "16m-6 fix: hasta el 9")
    for bad in ["٣", "½", "", "０", "３", "0", "12", "a", "²"] {
        expect(K.key(.other, characters: bad, hasModifiers: false) == nil, "16m-6 fix: «\(bad)» no es atajo")
    }
    expectEq(K.key(.enter, characters: "\r", hasModifiers: false), .enter, "16m-6 fix: Return")
    expect(K.key(.enter, characters: "\r", hasModifiers: true) == nil, "16m-6 fix: Shift+Return se ignora")
    expect(K.key(.other, characters: "3", hasModifiers: true) == nil, "16m-6 fix: ⌘3 no es atajo")
    expectEq(K.key(.up, characters: "", hasModifiers: false), .up, "16m-6 fix: flecha arriba")
    expectEq(K.key(.down, characters: "", hasModifiers: false), .down, "16m-6 fix: flecha abajo")
    expect(K.key(.down, characters: "", hasModifiers: true) == nil, "16m-6 fix: flecha con modificador se ignora")
}

@Test @MainActor func choiceFocusCountsAsComposingTests() {
    func composing(_ choiceFocused: Bool) -> Bool {
        IslandComposing.active(focused: false, draft: "", confirmingClear: false, staged: 0,
                               mainInFront: false, choiceFocused: choiceFocused)
    }
    expect(composing(true), "16m-6 fix: la tarjeta con foco mantiene la isla abierta bajo el teclado")
    expect(!composing(false), "16m-6 fix: sin foco no")
}

// MARK: - Chat: what a pick does and does not do

@Test @MainActor func choosingContractTests() async {
    let keyless = ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([:]),
        store: MemoryConversationStore(), config: .default)
    expect(!keyless.choose("Rápido"), "16m-6 fix: sin clave no se manda nada")
    expectEq(keyless.messages.count, 0, "16m-6 fix: y no queda mensaje")
    expectEq(keyless.queued, [], "16m-6 fix: ni cola")
    var state = IslandChoiceState()
    _ = sendPick(&state, 0, block: threeOptions(), resolution: .open, queued: keyless.queued, send: { keyless.choose($0) })
    expectEq(state.effective(resolution: .open, queued: keyless.queued), .open,
             "16m-6 fix: la tarjeta sigue abierta si no salió")

    let vm = primed(chat: FakeChatProvider(replies: [.success([.text("ok")])]))
    expect(!vm.choose("  \n"), "16m-6 fix: etiqueta en blanco no sale")
    expect(vm.choose("Rápido"), "16m-6 fix: una válida sí")
}

@Test @MainActor func choosingDoesNotTakeAttachmentsTests() async {
    let provider = FakeChatProvider(replies: [.success([.text("a")]), .success([.text("b")])])
    let vm = primed(chat: provider)
    let chip = AttachmentRef(name: "a.png", path: "/tmp/a.png", kind: .image)
    vm.pendingAttachments = [chip]
    vm.choose("Rápido")
    expectEq(vm.messages.first?.attachments.count, 0, "16m-6 fix: la elección no lleva lo adjunto")
    expectEq(vm.pendingAttachments, [chip], "16m-6 fix: los adjuntos siguen en el compositor")
    await pumpUntil("16m-6 fix: turno") { !vm.busy }
    vm.draft = "ahora sí"
    vm.send()
    expectEq(vm.messages.last { $0.role == .user }?.attachments, [chip], "16m-6 fix: el mensaje escrito sí los lleva")

    let queuedVM = primed(chat: FakeChatProvider(replies: [.success([.text("a")]), .success([.text("b")])]))
    queuedVM.draft = "uno"
    queuedVM.send()
    queuedVM.pendingAttachments = [chip]
    queuedVM.choose("Completo")
    await pumpUntil("16m-6 fix: cola") { !queuedVM.busy && queuedVM.queued.isEmpty }
    expectEq(queuedVM.messages.first { $0.text == "Completo" }?.attachments.count, 0,
             "16m-6 fix: una elección que sale de la cola tampoco se los lleva")
    expectEq(queuedVM.pendingAttachments, [chip], "16m-6 fix: ni los suelta")
}

@Test @MainActor func choiceOriginReachesTheModelTests() async {
    let provider = FakeChatProvider(replies: [.success([.text("a")]), .success([.text("b")]), .success([.text("c")])])
    let vm = primed(chat: provider)
    let marker = ChoiceOrigin.marker(vm.config.language)
    vm.draft = "hola"
    vm.send()
    await pumpUntil("16m-6 fix: t1") { !vm.busy }
    vm.choose("Rápido")
    await pumpUntil("16m-6 fix: t2") { !vm.busy }
    let users = provider.histories[1].filter { $0.role == .user }.map(\.content)
    expectEq(users[0], "hola", "16m-6 fix: lo tecleado no lleva marca")
    expectEq(users[1], marker + " Rápido", "16m-6 fix: lo elegido en la tarjeta llega marcado")
    expect(!marker.isEmpty, "16m-6 fix: la marca existe")
    expectEq(vm.messages.first { $0.role == .user && $0.origin == .choice }?.text, "Rápido",
             "16m-6 fix: el hilo muestra la etiqueta limpia")
    expect(vm.historyForTests().contains { $0.content == marker + " Rápido" }, "16m-6 fix: el historial sigue marcado")
    let memory = await vm.memoryTurns()
    expect(memory.contains { $0.content == "Rápido" } && !memory.contains { $0.content.contains(marker) },
           "16m-6 fix: la memoria de sesión guarda la palabra cruda")

    let busy = primed(chat: FakeChatProvider(replies: [.success([.text("a")]), .success([.text("b")])]))
    busy.draft = "uno"
    busy.send()
    busy.choose("Completo")
    await pumpUntil("16m-6 fix: cola") { !busy.busy && busy.queued.isEmpty }
    expectEq(busy.messages.first { $0.text == "Completo" }?.origin, .choice, "16m-6 fix: la cola conserva el origen")

    let sensed = primed(chat: FakeChatProvider(replies: [.success([.text("a")])]),
                        sensor: FakeContextSensor(TurnContext(source: .typed, focusedApp: "Safari")))
    let sensedChat = sensed.chat as? FakeChatProvider
    sensed.choose("Rápido")
    await pumpUntil("16m-6 fix: sensado") { !sensed.busy }
    let last = sensedChat?.histories.first?.last?.content ?? ""
    expect(last.contains("<context") && last.hasSuffix(marker + " Rápido"),
           "16m-6 fix: con contexto sensado la marca también viaja")
}

@Test @MainActor func choiceNeverApprovesAnythingTests() async {
    let approvals = FakeApprovals()
    let provider = FakeChatProvider(replies: [.success([.text("ok")])])
    let vm = primed(chat: provider, approvals: approvals)
    let request = ApprovalRequest(requestId: "r1", toolName: "Bash", summary: "rm -rf x", inputJSON: "{}")
    let parked = Task { _ = await approvals.request(request) }
    await pumpUntilAsync("16m-6 fix: la aprobación queda pendiente") { await approvals.requested.count == 1 }
    vm.choose("Sí, aprueba")
    await pumpUntil("16m-6 fix: turno") { !vm.busy }
    let resolutions = await approvals.resolutions
    expect(resolutions.isEmpty, "16m-6 fix: elegir «Sí, aprueba» no resuelve ninguna aprobación")
    parked.cancel()

    // The road a pick takes never touches the approval or spoken-confirmation
    // machinery: a source scan, so a future shortcut fails loudly.
    guard let repo = Conformance.repoRoot() else {
        print("  nota  [choice16m6] fuera del checkout: no hay que escanear")
        return
    }
    let root = repo.appendingPathComponent("Sources/CompanionUI")
    let files = [root.appendingPathComponent("Island/Choice/IslandChoice.swift"),
                 root.appendingPathComponent("Island/Choice/IslandChoiceCard.swift")]
    let text = (try? String(contentsOf: root.appendingPathComponent("Chat/ChatViewModel.swift"), encoding: .utf8)) ?? ""
    // No access keyword in the anchor: it survives public -> package.
    let chooseBody = text.components(separatedBy: "func choose(").dropFirst().first?
        .components(separatedBy: "private func dispatch").first ?? ""
    // Sobre texto vacio todo `!contains` pasa: el ancla exige un cuerpo real.
    expect(!chooseBody.isEmpty && chooseBody.contains("dispatch("),
           "16m-6 fix: choose existe y llega a dispatch")
    let sources = files.map { (try? String(contentsOf: $0, encoding: .utf8)) ?? "" }
    expect(sources[0].contains("enum IslandChoice"), "16m-6 fix: IslandChoice.swift se lee")
    expect(sources[1].contains("struct IslandChoiceCard"), "16m-6 fix: IslandChoiceCard.swift se lee")
    for name in ["DecisionGate", "SpokenConfirmation", "resolveApproval", "answerApproval", "ApprovalsProvider"] {
        expect(!chooseBody.contains(name), "16m-6 fix: choose no toca \(name)")
        for (file, source) in zip(files, sources) {
            expect(!source.contains(name), "16m-6 fix: \(file.lastPathComponent) no toca \(name)")
        }
    }
}

@Test @MainActor func failedTurnReopensTheQuestionTests() async {
    let vm = primed(chat: FakeChatProvider(replies: [.failure(ChatError.timeout)]))
    await vm.appendAssistant("¿Cómo?\n" + sampleFence)
    guard let ask = vm.messages.first, let block = IslandChoice.block(in: ask) else {
        expect(false, "16m-6 fix: la pregunta debía parsear")
        return
    }
    vm.choose("Rápido")
    expectEq(IslandChoice.resolution(of: block, messageID: ask.id, in: vm.messages), .chosen(0),
             "16m-6 fix: en vuelo cuenta como elegida")
    await pumpUntil("16m-6 fix: falla") { !vm.busy }
    expectEq(IslandChoice.resolution(of: block, messageID: ask.id, in: vm.messages), .open,
             "16m-6 fix: el turno falló, la pregunta vuelve a estar abierta")
}

@Test @MainActor func cancelledQueueReopensTheCardTests() async {
    let vm = primed(chat: FakeChatProvider(replies: [.success([.text("a")])]))
    vm.draft = "uno"
    vm.send()
    let ask = ChatMessage(role: .assistant, text: sampleFence)
    vm.messages.append(ask)
    let block = threeOptions()
    var state = IslandChoiceState()
    _ = sendPick(&state, 1, block: block, resolution: .open, queued: vm.queued, send: { vm.choose($0) })
    expectEq(vm.queued, ["Completo"], "16m-6 fix: con turno en curso sale a la cola")
    expectEq(state.effective(resolution: IslandChoice.resolution(of: block, messageID: ask.id, in: vm.messages),
                             queued: vm.queued), .chosen(1), "16m-6 fix: en la cola cuenta")
    vm.newConversation()
    expectEq(vm.queued, [], "16m-6 fix: cambiar de conversación vacía la cola")
    expectEq(state.effective(resolution: IslandChoice.resolution(of: block, messageID: ask.id, in: vm.messages),
                             queued: vm.queued), .open, "16m-6 fix: la etiqueta ya no está en la cola ni en el hilo: abierta")
}

// MARK: - Prompt

@Test func choiceOriginPromptTests() {
    expect(ChoiceOrigin.marker(.en) != ChoiceOrigin.marker(.es), "16m-6 fix: la marca va en cada idioma")
    expectEq(ChoiceOrigin.mark("Rápido", language: .en), ChoiceOrigin.marker(.en) + " Rápido", "16m-6 fix: marca + palabra")
    for language in [AppLanguage.en, .es] {
        let vocabulary = CardVocabulary.text(language)
        expect(vocabulary.contains(ChoiceOrigin.marker(language)), "\(language): el prompt explica la marca")
        let sheet = language == .en ? "approval sheet" : "hoja de aprobación"
        expect(vocabulary.contains(sheet), "\(language): los permisos van por la hoja")
        let never = language == .en ? "never approves" : "nunca aprueba"
        expect(vocabulary.contains(never), "\(language): una elección no aprueba permisos ni acciones destructivas")
        let prompt = ChatPrompt.system(ownerFirstName: "K", delegateEnabled: true, language: language)
        expect(prompt.contains(ChoiceOrigin.marker(language)), "\(language): y llega al prompt de la charla")
    }
}

// MARK: - UI odds and ends

@Test @MainActor func choiceCopyAndTextTests() async {
    let keys = ["island.choice.option", "island.choice.selected", "island.choice.unavailable",
                "island.choice.hint", "island.signIn", "island.signIn.body", "island.signIn.action"]
    for language in [AppLanguage.en, .es] {
        await pinLanguage(language) {
            for key in keys {
                let value = Localized.string(key)
                expect(!value.isEmpty && value != key, "16m-6 fix: \(key) resuelve en \(language)")
            }
        }
    }
    expectEq(MarkdownView.choiceLines(ChoiceBlock(question: "¿Cómo?", options: [
        .init(label: "Rápido", detail: "5 min"), .init(label: "Completo"),
    ])), ["¿Cómo?", "1. Rápido — 5 min", "2. Completo"], "16m-6 fix: la ventana lee pregunta y opciones numeradas")

    let long = "Tengo dos caminos y los dos sirven. Uno es rápido. El otro es completo. Dime cuál prefieres ahora mismo por favor."
    let withCard = SpeechBudget.brief(long, hasCard: true)
    let without = SpeechBudget.brief(long, hasCard: false)
    expect(withCard.count < without.count && !withCard.isEmpty, "16m-6 fix: con pregunta la voz dice menos que sin tarjeta")
}
