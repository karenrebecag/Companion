import CompanionCore
import CompanionServices
@testable import CompanionUI
import Foundation
import Testing

// Wave 16m-6, security round 2: what a pick may say to the open_url gate and
// to the connected apps' scope, the origin surviving a restart, and the
// card's focus dying with the card.

private func openEvil() -> ChatDelta {
    .toolCalls([ToolCallRef(id: "c1", name: "open_url", arguments: #"{"url":"https://evil.com/"}"#)])
}

/// The parent's own runner with a tap on what `noteTurn` was told.
private final class NoteTap: ParentToolExecuting, @unchecked Sendable {
    let inner: ParentToolRunner
    let lock = NSLock()
    var noted: [String] = []
    init(_ inner: ParentToolRunner) { self.inner = inner }
    func specs(_ language: AppLanguage) -> [ToolSpec] { inner.specs(language) }
    func handles(_ name: String) -> Bool { inner.handles(name) }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        await inner.execute(name: name, argumentsJSON: argumentsJSON)
    }
    func approval(for call: ToolCallRef, said: String) -> ApprovalRequest? { inner.approval(for: call, said: said) }
    func beginTurn() { inner.beginTurn() }
    func noteTurn(_ said: String) { lock.withLock { noted.append(said) } }
    /// 16q-2: a card turn has its own entry; it must never carry her words.
    func noteChoiceTurn() { lock.withLock { noted.append("<card>") } }
}

@Test @MainActor func choiceLabelNeverAuthorizesAHostTests() async {
    // A card ["Abrir evil.com", "Cancelar"]: the label names the host, but it
    // is the model's text, not something she said.
    let approvals = FakeApprovals()
    let opener = FakeWorkspaceOpener()
    let chat = FakeChatProvider(replies: [.success([openEvil()]), .success([.text("Abierto.")])])
    let vm = primed(chat: chat, parentTools: ParentToolRunner(workspace: opener), approvals: approvals)
    vm.choose("Abrir evil.com")
    await pumpUntil("16m-6 gate: la hoja aparece para una elección") { vm.pendingApproval != nil }
    expectEq(vm.pendingApproval?.toolName, "open_url", "16m-6 gate: la hoja es de open_url")
    expect(opener.openedURLs.isEmpty, "16m-6 gate: nada se abrió sin contestar")
    vm.answerApproval(false)
    await pumpUntil("16m-6 gate: idle") { !vm.busy }
    expect(opener.openedURLs.isEmpty, "16m-6 gate: con no, sigue sin abrirse")

    // The same words typed by her are consent, as before.
    let typedOpener = FakeWorkspaceOpener()
    let typedChat = FakeChatProvider(replies: [.success([openEvil()]), .success([.text("Abierto.")])])
    let typed = primed(chat: typedChat, parentTools: ParentToolRunner(workspace: typedOpener), approvals: FakeApprovals())
    typed.draft = "Abrir evil.com"
    typed.send()
    await pumpUntil("16m-6 gate: tecleado, idle") { !typed.busy }
    expect(typed.pendingApproval == nil, "16m-6 gate: tecleado no pide hoja")
    expectEq(typedOpener.openedURLs.map(\.absoluteString), ["https://evil.com/"], "16m-6 gate: y abre, como hoy")

    // Out of the queue it is still a pick.
    let queuedOpener = FakeWorkspaceOpener()
    let queuedChat = FakeChatProvider(replies: [.success([.text("uno")]), .success([openEvil()]), .success([.text("fin")])])
    let queued = primed(chat: queuedChat, parentTools: ParentToolRunner(workspace: queuedOpener), approvals: FakeApprovals())
    queued.draft = "hola"
    queued.send()
    queued.choose("Abrir evil.com")
    await pumpUntil("16m-6 gate: la hoja desde la cola") { queued.pendingApproval != nil }
    expect(queuedOpener.openedURLs.isEmpty, "16m-6 gate: una elección que sale de la cola tampoco abre sin hoja")
    queued.answerApproval(false)
    await pumpUntil("16m-6 gate: cola idle") { !queued.busy && queued.queued.isEmpty }
}

@Test @MainActor func choiceDoesNotSetTheAppScopeTests() async {
    let tap = NoteTap(ParentToolRunner(workspace: FakeWorkspaceOpener()))
    let vm = primed(chat: FakeChatProvider(replies: [.success([.text("a")]), .success([.text("b")]), .success([.text("c")])]),
                    parentTools: tap)
    vm.choose("Gmail")
    await pumpUntil("16m-6 gate: t1") { !vm.busy }
    vm.draft = "Gmail"
    vm.send()
    await pumpUntil("16m-6 gate: t2") { !vm.busy }
    expectEq(tap.noted, ["<card>", "Gmail"], "16m-6 gate: la elección no nombra app; lo tecleado sí")

    let tapQueued = NoteTap(ParentToolRunner(workspace: FakeWorkspaceOpener()))
    let queued = primed(chat: FakeChatProvider(replies: [.success([.text("a")]), .success([.text("b")])]), parentTools: tapQueued)
    queued.draft = "uno"
    queued.send()
    queued.choose("Slack")
    await pumpUntil("16m-6 gate: cola") { !queued.busy && queued.queued.isEmpty }
    expectEq(tapQueued.noted, ["uno", "<card>"], "16m-6 gate: desde la cola tampoco")
}

@Test @MainActor func choiceOriginSurvivesARestartTests() async {
    let store = MemoryConversationStore()
    let vm = primed(chat: FakeChatProvider(replies: [.success([.text("ok")])]), store: store)
    vm.choose("Rápido")
    await pumpUntil("16m-6 persistencia: turno") { !vm.busy }
    let marker = ChoiceOrigin.marker(vm.config.language)

    let reopened = primed(chat: FakeChatProvider(), store: store)
    let pick = reopened.messages.first { $0.role == .user }
    expectEq(pick?.origin, .choice, "16m-6 persistencia: la elección restaurada sigue marcada")
    expect(pick?.restored == true, "16m-6 persistencia: y restaurada")
    expect(reopened.historyForTests().contains { $0.content == marker + " Rápido" },
           "16m-6 persistencia: el modelo la sigue viendo con la marca")

    // The real file store keeps it, and reads files written before it existed.
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("choice-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    let files = ConversationStore(directory: dir)
    do {
        try files.save(ConversationRecord(id: "a", title: "t", updatedAt: Date(), messages: [
            ConversationMessage(role: "user", text: "Rápido", fromChoice: true),
            ConversationMessage(role: "user", text: "hola"),
        ]))
        let back = try files.load("a")
        expectEq(back?.messages.map(\.fromChoice), [true, false], "16m-6 persistencia: el disco conserva la marca")
        // Without a pick the key is not written at all: the shape of every
        // file from before 16m-6, which must keep reading.
        try files.save(ConversationRecord(id: "old", title: "t", updatedAt: Date(), messages: [
            ConversationMessage(role: "user", text: "x"),
        ]))
        let raw = try String(contentsOf: dir.appendingPathComponent("old.json"), encoding: .utf8)
        expect(!raw.contains("choice"), "16m-6 persistencia: sin elección no se escribe la clave")
        expectEq(try files.load("old")?.messages.map(\.fromChoice), [false], "16m-6 persistencia: un archivo anterior sigue leyéndose")
    } catch {
        expect(false, "16m-6 persistencia: el store no debía fallar: \(error)")
    }
}

@Test @MainActor func choiceFocusDiesWithItsCardTests() {
    let card = UUID()
    let next = UUID()
    expect(IslandChoice.isFocused(focusedID: card, liveID: card), "16m-6 foco: la tarjeta viva con foco cuenta")
    expect(!IslandChoice.isFocused(focusedID: card, liveID: next),
           "16m-6 foco: llegó otra respuesta: el foco de la vieja ya no cuenta")
    expect(!IslandChoice.isFocused(focusedID: card, liveID: nil), "16m-6 foco: sin tarjeta viva no cuenta")
    expect(!IslandChoice.isFocused(focusedID: nil, liveID: card), "16m-6 foco: sin foco no cuenta")

    func composing(_ focused: Bool) -> Bool {
        IslandComposing.active(focused: false, draft: "", confirmingClear: false, staged: 0,
                               mainInFront: false, choiceFocused: focused)
    }
    expect(!composing(IslandChoice.isFocused(focusedID: card, liveID: next)),
           "16m-6 foco: y la isla puede plegarse")

    // A card that unmounts while focused sends no focus change of its own:
    // it must say so itself.
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/CompanionUI/Island/Choice/IslandChoiceCard.swift")
    let source = (try? String(contentsOf: root, encoding: .utf8)) ?? ""
    expect(source.contains(".onDisappear { onFocus(false) }"), "16m-6 foco: la tarjeta suelta el foco al desmontarse")
}
