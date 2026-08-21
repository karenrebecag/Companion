import CompanionCore
import CompanionUI
import Foundation
import Testing

@Test @MainActor func chatViewModelTests() async {
    await testTokensRamp()
    await testChatCopy()
    await testSendAppendsUserAndStreamsAssistant()
    await testSecondSendWhileBusyQueues()
    await testQueueDrainsAfterFinish()
    await testThrowShowsErrorAndClearsBusy()
    await testQueueDrainsAfterError()
    await testEmptyDraftIsNoOp()
    await testOnboardingPingFailDoesNotWriteKey()
    await testOnboardingPingOkWritesKey()
    await testEmptyPasteShowsCopy()
    await testReopenLoadsLastConversation()
    await testHandoffCommitsPrefaceAndStatus()
    await testNewConversationDropsQueue()
    await testAlwaysSendsDelegateTool()
    await testChangeKeyCancelsAndDropsQueue()
    await testStatusLinesStayOutOfHistory()
    await testThreadAppendsPersistWithoutStreaming()
    await testShowStreamAndFinishStream()
    await testHistoryTurnsWindowsAndSkipsStatus()
    await testConversationPresentingEmptyAndUnicode()
}

@MainActor func testTokensRamp() async {
    expectEq(
        [Tokens.Space.s4, Tokens.Space.s8, Tokens.Space.s12,
         Tokens.Space.s16, Tokens.Space.s24],
        [CGFloat(4), 8, 12, 16, 24],
        "tokens: space 4/8/12/16/24")
    _ = (Tokens.Color.bg, Tokens.Color.surface, Tokens.Color.fg,
         Tokens.Color.muted, Tokens.Color.border, Tokens.Color.accent,
         Tokens.Color.destructive, Tokens.Typography.title,
         Tokens.Typography.body, Tokens.Typography.caption)
    expect(true, "tokens: rampa semántica sin Palette")
}

@MainActor func testChatCopy() async {
    let invalid = "Esta clave no es válida. Revísala en platform.openai.com."
    let persist = "No pude guardar la conversación. Revisa el espacio en disco."
    let net = "No pude conectar. Revisa la red e inténtalo de nuevo."
    expectEq(ChatCopy.emptyKey, "Pega tu clave de OpenAI para empezar.", "copy: vacío")
    expectEq(ChatCopy.error(ChatError.unauthorized), invalid, "copy: 401")
    expectEq(ChatCopy.error(ChatError.invalidKey), invalid, "copy: invalidKey")
    expectEq(ChatCopy.error(ChatError.forbidden),
             "Esta clave no tiene permiso. Revisa su acceso en platform.openai.com.",
             "copy: 403")
    expectEq(ChatCopy.error(ChatError.rateLimited),
             "Demasiadas peticiones. Espera un momento e inténtalo de nuevo.",
             "copy: 429")
    expectEq(ChatCopy.error(ChatError.timeout), net, "copy: timeout")
    expectEq(ChatCopy.error(ChatError.unreachable), net, "copy: unreachable")
    expectEq(ChatCopy.error(ChatError.httpStatus(502)),
             "El servidor respondió 502. Inténtalo de nuevo.", "copy: httpStatus")
    expectEq(ChatCopy.error(ChatError.noProvider),
             "No hay un proveedor de chat disponible.", "copy: noProvider")
    expectEq(ChatCopy.error(ChatError.empty),
             "El modelo no contestó. Inténtalo de nuevo.", "copy: empty")
    expectEq(ChatCopy.error(SecretStoreError.denied),
             "No pude guardar la clave en el llavero. Autoriza el acceso e inténtalo de nuevo.",
             "copy: denied")
    expectEq(ChatCopy.error(PersistenceError.io), persist, "copy: persist io")
    expectEq(ChatCopy.error(PersistenceError.encoding), persist, "copy: persist enc")
    expectEq(
        ChatCopy.handoff(Handoff(goal: "listar el escritorio", context: "x")),
        "Encargo: listar el escritorio — el especialista llega en una próxima versión.",
        "copy: handoff")
}

@MainActor func testSendAppendsUserAndStreamsAssistant() async {
    let chat = FakeChatProvider(replies: [.success([.text("Ho"), .text("la")])])
    let store = MemoryConversationStore()
    let vm = primed(chat: chat, store: store)
    vm.draft = "  ñoño — café  "
    vm.send()
    expectEq(vm.draft, "", "send: limpia el draft")
    expect(vm.busy, "send: busy al arrancar")
    expectEq(vm.messages.map(\.text), ["ñoño — café"], "send: el usuario entra ya")
    await pumpUntil("send: el asistente termina") { !vm.busy }
    expectEq(vm.messages.map(\.text), ["ñoño — café", "Hola"], "send: concatena")
    expectEq(vm.messages.last?.role, .assistant, "send: cierre assistant")
    expectEq(vm.streaming, "", "send: streaming vacío")
    expect(vm.errorText == nil, "send: sin error")
    do {
        let recents = try store.list()
        expectEq(recents.count, 1, "send: persiste")
        expectEq(recents.first?.title, "ñoño — café", "send: título = primer user")
        let loaded = try store.load(recents[0].id)
        expectEq(loaded?.messages.map(\.text), ["ñoño — café", "Hola"],
                 "send: roundtrip")
    } catch {
        expect(false, "send: persist no debía tirar \(error)")
    }
}

@MainActor func testSecondSendWhileBusyQueues() async {
    let chat = FakeChatProvider(replies: [.success([.text("A")]), .success([.text("B")])])
    let vm = primed(chat: chat)
    vm.draft = "uno"
    vm.send()
    expect(vm.busy, "cola: el primero ocupa")
    vm.draft = "dos"
    vm.send()
    expectEq(vm.queued, ["dos"], "cola: el segundo espera")
    expectEq(vm.messages.map(\.text), ["uno"], "cola: no se adelanta")
    expectEq(vm.draft, "", "cola: draft vacío")
}

@MainActor func testQueueDrainsAfterFinish() async {
    let chat = FakeChatProvider(replies: [.success([.text("A")]), .success([.text("B")])])
    let vm = primed(chat: chat)
    vm.draft = "uno"
    vm.send()
    vm.draft = "dos"
    vm.send()
    await pumpUntil("drain: idle") { !vm.busy && vm.queued.isEmpty }
    expectEq(vm.messages.map(\.text), ["uno", "A", "dos", "B"], "drain: encolado")
    expectEq(chat.histories.count, 2, "drain: dos streams")
    expectEq(chat.histories[0].last?.content, "uno", "drain: primero uno")
    expectEq(chat.histories[1].last?.content, "dos", "drain: después dos")
}

@MainActor func testThrowShowsErrorAndClearsBusy() async {
    let chat = FakeChatProvider(replies: [.failure(ChatError.timeout)])
    let vm = primed(chat: chat)
    vm.draft = "hola"
    vm.send()
    await pumpUntil("error: idle") { !vm.busy }
    expectEq(vm.errorText, ChatCopy.error(ChatError.timeout), "error: copy")
    expect(!vm.busy, "error: busy false")
    expectEq(vm.streaming, "", "error: sin streaming")
    expectEq(vm.messages.map(\.role), [.user], "error: no comete parcial")
}

@MainActor func testQueueDrainsAfterError() async {
    let chat = FakeChatProvider(replies: [
        .failure(ChatError.rateLimited), .success([.text("ok")]),
    ])
    let vm = primed(chat: chat)
    vm.draft = "uno"
    vm.send()
    vm.draft = "dos"
    vm.send()
    await pumpUntil("drain-error: idle") { !vm.busy && vm.queued.isEmpty }
    expect(vm.messages.map(\.text).contains("dos"), "drain-error: encolado corre")
    expect(vm.messages.map(\.text).contains("ok"), "drain-error: segundo comete")
    expectEq(chat.histories.count, 2, "drain-error: dos intentos")
}

@MainActor func testEmptyDraftIsNoOp() async {
    let chat = FakeChatProvider(replies: [.success([.text("no")])])
    let vm = primed(chat: chat)
    vm.draft = ""
    vm.send()
    vm.draft = "   \n\t "
    vm.send()
    expectEq(vm.messages.count, 0, "vacío: no manda")
    expect(!vm.busy, "vacío: no ocupa")
    expectEq(chat.histories.count, 0, "vacío: cero streams")
    expectEq(vm.draft, "   \n\t ", "vacío: deja el draft")
}

@MainActor func testOnboardingPingFailDoesNotWriteKey() async {
    let chat = FakeChatProvider(verifyError: ChatError.unauthorized)
    let secrets = TestSecretStore()
    let vm = onboard(chat, secrets)
    vm.onboardingKey = "sk-bad"
    await awaitMain { await vm.submitOnboarding() }
    expect(vm.needsOnboarding, "onboard fail: sigue")
    expectEq(readOpenAI(secrets), nil, "onboard fail: no escribe")
    expectEq(vm.errorText, ChatCopy.error(ChatError.unauthorized), "onboard fail: 401")
    expectEq(chat.verifyKeys, ["sk-bad"], "onboard fail: pingueó")
}

@MainActor func testOnboardingPingOkWritesKey() async {
    let chat = FakeChatProvider()
    let secrets = TestSecretStore()
    let vm = onboard(chat, secrets)
    vm.onboardingKey = "  sk-live  \n"
    await awaitMain { await vm.submitOnboarding() }
    expect(!vm.needsOnboarding, "onboard ok: entra")
    expectEq(readOpenAI(secrets), "sk-live", "onboard ok: escribe OPENAI")
    expect(vm.errorText == nil, "onboard ok: sin error")
    expectEq(vm.onboardingKey, "", "onboard ok: limpia")
    expectEq(chat.verifyProviders, [.openAI], "onboard ok: ping OpenAI")
}

@MainActor func testEmptyPasteShowsCopy() async {
    let chat = FakeChatProvider()
    let secrets = TestSecretStore()
    let vm = onboard(chat, secrets)
    vm.onboardingKey = "  \n"
    await awaitMain { await vm.submitOnboarding() }
    expectEq(vm.errorText, ChatCopy.emptyKey, "paste vacío: copy")
    expect(vm.needsOnboarding, "paste vacío: no entra")
    expectEq(chat.verifyKeys.count, 0, "paste vacío: no pinguea")
    expectEq(readOpenAI(secrets), nil, "paste vacío: no escribe")
}

@MainActor func testReopenLoadsLastConversation() async {
    let store = MemoryConversationStore()
    do {
        try store.save(ConversationRecord(
            id: "c1", title: "Hola", updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            messages: [
                ConversationMessage(role: "user", text: "Hola"),
                ConversationMessage(role: "assistant", text: "Qué tal"),
            ]))
    } catch {
        expect(false, "reopen: save no debía tirar \(error)")
        return
    }
    let vm = ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
        store: store, config: .default)
    vm.onAppear()
    expect(!vm.needsOnboarding, "reopen: con clave no pide onboarding")
    expectEq(vm.messages.map(\.text), ["Hola", "Qué tal"], "reopen: hilo")
    expectEq(vm.messages.map(\.role), [.user, .assistant], "reopen: roles")
    expectEq(vm.recents.first?.id, "c1", "reopen: recents")
}

@MainActor func testHandoffCommitsPrefaceAndStatus() async {
    let handoff = Handoff(goal: "listar el escritorio", context: "workdir ~")
    let chat = FakeChatProvider(replies: [.success([.text("Voy. "), .handoff(handoff)])])
    let store = MemoryConversationStore()
    let vm = primed(chat: chat, store: store)
    vm.draft = "hazlo"
    vm.send()
    await pumpUntil("handoff: idle") { !vm.busy }
    let status = ChatCopy.handoff(handoff)
    expectEq(vm.messages.map(\.text), ["hazlo", "Voy. ", status], "handoff: prefacio")
    expectEq(vm.messages.map(\.isStatus), [false, false, true], "handoff: estado")
    do {
        let loaded = try store.load(store.list()[0].id)
        expectEq(loaded?.messages.map(\.role), ["user", "assistant", "status"],
                 "handoff: persiste nota")
        expectEq(loaded?.messages.last?.text, status, "handoff: especialista ausente")
    } catch {
        expect(false, "handoff: persist no debía tirar \(error)")
    }
}

@MainActor func testNewConversationDropsQueue() async {
    let chat = FakeChatProvider(replies: [.success([.text("A")]), .success([.text("NO")])])
    let vm = primed(chat: chat)
    vm.draft = "uno"
    vm.send()
    vm.draft = "dos"
    vm.send()
    expectEq(vm.queued, ["dos"], "nuevo: había cola")
    vm.newConversation()
    expectEq(vm.queued, [], "nuevo: tira la cola")
    expectEq(vm.messages.count, 0, "nuevo: hilo vacío")
    expect(!vm.busy, "nuevo: no ocupa")
    await settle()
    expectEq(vm.messages.count, 0, "nuevo: el cancelado no comete")
    expect(!chat.histories.contains { $0.last?.content == "dos" }, "nuevo: sin drenar")
}

@MainActor func testAlwaysSendsDelegateTool() async {
    let chat = FakeChatProvider(replies: [.success([.text("ok")])])
    let vm = primed(chat: chat)
    vm.draft = "hola"
    vm.send()
    await pumpUntil("tools: idle") { !vm.busy }
    expectEq(chat.toolsSeen, [.delegate], "tools: siempre delegate")
}

@MainActor func testChangeKeyCancelsAndDropsQueue() async {
    let chat = FakeChatProvider(replies: [.success([.text("A")]), .success([.text("NO")])])
    let vm = primed(chat: chat)
    vm.draft = "uno"
    vm.send()
    vm.draft = "dos"
    vm.send()
    expectEq(vm.queued, ["dos"], "clave: había cola")
    vm.changeKey()
    expect(vm.needsOnboarding, "clave: vuelve al onboarding")
    expectEq(vm.queued, [], "clave: tira la cola")
    expect(!vm.busy, "clave: no ocupa")
    await settle()
    expect(!chat.histories.contains { $0.last?.content == "dos" },
           "clave: no drena con onboarding")
}

@MainActor func testStatusLinesStayOutOfHistory() async {
    let handoff = Handoff(goal: "listar", context: "")
    let chat = FakeChatProvider(replies: [
        .success([.text("Voy. "), .handoff(handoff)]),
        .success([.text("ok")]),
    ])
    let vm = primed(chat: chat)
    vm.draft = "hazlo"
    vm.send()
    await pumpUntil("status-hist: primer turno") { !vm.busy }
    vm.draft = "y ahora"
    vm.send()
    await pumpUntil("status-hist: segundo turno") { !vm.busy }
    let second = chat.histories.last ?? []
    expect(!second.contains { $0.content.contains("especialista") },
           "status: la nota no viaja al modelo")
}

@MainActor func testThreadAppendsPersistWithoutStreaming() async {
    let chat = FakeChatProvider(replies: [.success([.text("NO")])])
    let store = MemoryConversationStore()
    let vm = primed(chat: chat, store: store)
    let port: any ConversationPresenting = vm
    await port.appendUser("hola")
    await port.appendAssistant("qué tal")
    await port.appendStatus("pensando")
    expectEq(vm.messages.map(\.text), ["hola", "qué tal", "pensando"],
             "thread: los tres entran al hilo")
    expectEq(vm.messages.map(\.role), [.user, .assistant, nil], "thread: roles")
    expectEq(vm.messages.map(\.isStatus), [false, false, true], "thread: status")
    expect(!vm.busy, "thread: append no ocupa el chat")
    expectEq(vm.streaming, "", "thread: sin streaming")
    expectEq(chat.histories.count, 0, "thread: no dispara al proveedor")
    do {
        let recents = try store.list()
        expectEq(recents.count, 1, "thread: persiste")
        expectEq(recents.first?.title, "hola", "thread: título = primer user")
        let loaded = try store.load(recents[0].id)
        expectEq(loaded?.messages.map(\.role), ["user", "assistant", "status"],
                 "thread: roundtrip roles")
        expectEq(loaded?.messages.map(\.text), ["hola", "qué tal", "pensando"],
                 "thread: roundtrip textos")
    } catch {
        expect(false, "thread: persist no debía tirar \(error)")
    }
}

@MainActor func testShowStreamAndFinishStream() async {
    let store = MemoryConversationStore()
    let vm = primed(chat: FakeChatProvider(), store: store)
    let port: any ConversationPresenting = vm
    await port.showStream("Ho")
    expectEq(vm.streaming, "Ho", "stream: pisa")
    await port.showStream("")
    expectEq(vm.streaming, "", "stream: vacío es un valor")
    await port.showStream("ñoño — café 👋")
    expectEq(vm.streaming, "ñoño — café 👋", "stream: unicode")
    expectEq(vm.messages.count, 0, "stream: no comete")
    await port.appendAssistant("ñoño — café 👋")
    await port.finishStream()
    expectEq(vm.streaming, "", "stream: finish limpia")
    expectEq(vm.messages.map(\.text), ["ñoño — café 👋"], "stream: assistant ya iba")
    expectEq(vm.messages.last?.role, .assistant, "stream: rol assistant")
    do {
        let loaded = try store.load(store.list()[0].id)
        expectEq(loaded?.messages.map(\.text), ["ñoño — café 👋"],
                 "stream: persiste el assistant, no el parcial")
    } catch {
        expect(false, "stream: persist no debía tirar \(error)")
    }
    await port.finishStream()
    expectEq(vm.streaming, "", "stream: finish vacío es no-op")
    expectEq(vm.messages.count, 1, "stream: no duplica")
}

@MainActor func testHistoryTurnsWindowsAndSkipsStatus() async {
    let chat = FakeChatProvider()
    let store = MemoryConversationStore()
    let vm = ChatViewModel(
        chat: chat, secrets: TestSecretStore([.openAI: "sk-test"]),
        store: store, config: Config(chat: ChatSettings(historyWindow: 2)))
    vm.onAppear()
    let port: any ConversationPresenting = vm
    await port.appendUser("uno")
    await port.appendAssistant("a")
    await port.appendStatus("nota")
    await port.appendUser("dos")
    await port.appendAssistant("b")
    await port.appendUser("tres")
    let turns = await port.historyTurns()
    expectEq(turns.map(\.role), [.assistant, .user], "hist: ventana 2, sin status")
    expectEq(turns.map(\.content), ["b", "tres"], "hist: los dos últimos de chat")
    expectEq(vm.messages.count, 6, "hist: el hilo guarda todo")
    expect(!turns.contains { $0.content == "nota" }, "hist: status fuera")
}

@MainActor func testConversationPresentingEmptyAndUnicode() async {
    let store = MemoryConversationStore()
    let vm = primed(chat: FakeChatProvider(), store: store)
    let port: any ConversationPresenting = vm
    expectEq(await port.historyTurns(), [], "present: vacío")
    await port.appendUser("")
    await port.appendUser("ñoño — café 👋'; DROP")
    await port.appendAssistant("")
    await port.appendStatus("")
    let turns = await port.historyTurns()
    expectEq(turns.map(\.role), [.user, .user, .assistant], "present: roles")
    expectEq(turns.map(\.content), ["", "ñoño — café 👋'; DROP", ""],
             "present: vacío y unicode viajan")
    expectEq(vm.messages.map(\.isStatus), [false, false, false, true],
             "present: status vacío queda en el hilo")
    let long = String(repeating: "a", count: 10_000)
    await port.appendAssistant(long)
    let after = await port.historyTurns()
    expectEq(after.last?.content.count, 10_000, "present: 10k chars")
    do {
        let loaded = try store.load(store.list()[0].id)
        expectEq(loaded?.messages.count, 5, "present: persiste los cinco")
        expectEq(loaded?.messages.last?.text.count, 10_000, "present: 10k persistido")
    } catch {
        expect(false, "present: persist no debía tirar \(error)")
    }
}

@MainActor func primed(
    chat: FakeChatProvider,
    store: MemoryConversationStore = MemoryConversationStore()
) -> ChatViewModel {
    let vm = ChatViewModel(
        chat: chat, secrets: TestSecretStore([.openAI: "sk-test"]),
        store: store, config: .default)
    vm.onAppear()
    return vm
}

@MainActor func onboard(_ chat: FakeChatProvider, _ secrets: TestSecretStore)
    -> ChatViewModel
{
    let vm = ChatViewModel(
        chat: chat, secrets: secrets, store: MemoryConversationStore(),
        config: .default)
    vm.onAppear()
    expect(vm.needsOnboarding, "onboard: pide clave")
    return vm
}

@MainActor func readOpenAI(_ secrets: TestSecretStore) -> String? {
    do { return try secrets.read(.openAI) } catch {
        expect(false, "secret read no debía tirar \(error)")
        return nil
    }
}

@MainActor func awaitMain(_ body: @escaping @MainActor () async -> Void) async {
    await body()
}

final class FakeChatProvider: ChatProvider, @unchecked Sendable {
    var replies: [Result<[ChatDelta], Error>]
    var verifyError: Error?
    private(set) var toolsSeen: [ToolSpec] = []
    private(set) var histories: [[Turn]] = []
    private(set) var verifyKeys: [String] = []
    private(set) var verifyProviders: [ProviderDescriptor] = []
    private var index = 0

    init(replies: [Result<[ChatDelta], Error>] = [], verifyError: Error? = nil) {
        self.replies = replies
        self.verifyError = verifyError
    }

    func stream(_ history: [Turn], tools: [ToolSpec])
        -> AsyncThrowingStream<ChatDelta, Error>
    {
        toolsSeen = tools
        histories.append(history)
        let reply = index < replies.count ? replies[index] : .success([])
        index += 1
        return AsyncThrowingStream { continuation in
            let work = Task.detached {
                switch reply {
                case .success(let deltas):
                    for delta in deltas { continuation.yield(delta) }
                    continuation.finish()
                case .failure(let error):
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    func verify(_ key: String, provider: ProviderDescriptor) async throws {
        verifyKeys.append(key)
        verifyProviders.append(provider)
        if let verifyError { throw verifyError }
    }
}
