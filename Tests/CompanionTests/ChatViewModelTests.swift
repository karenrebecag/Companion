import CompanionCore
import CompanionServices
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

@Test @MainActor func chatViewModelTests() async {
    await pinLanguage {
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
        await testParentToolRoundRecordsCallAndResult()
        await testParentToolRoundsCapAtThree()
        await testParentToolThenHandoffInOneRound()
        await testParentToolCardsComeAfterAllToolAnswers()
        await testForeignURLWaitsForTheSheet()
        await testForeignURLDeniedIsAnInstruction()
        await testRememberedDenialSkipsTheSheet()
        await testSaidURLOpensWithoutSheet()
        testApprovalDetailRepairsWhatItShows()
        await testSwitchingConversationDropsTheGate()
        await testTwoPendingRequestsAnswerInOrder()
        await testContextTravelsOnlyInTheCurrentTurn()
        await testContextChannelsOffStillCarriesSource()
        await testContextNeverPersists()
        await testMemoryTurnsCarryRawTextOnly()
        await testHandoffCommitsPrefaceAndStatus()
        await testNewConversationDropsQueue()
        await testAlwaysSendsDelegateTool()
        await testChangeKeyCancelsAndDropsQueue()
        await testStatusLinesStayOutOfHistory()
        await testThreadAppendsPersistWithoutStreaming()
        await testShowStreamAndFinishStream()
        await testHistoryTurnsWindowsAndSkipsStatus()
        await testConversationPresentingEmptyAndUnicode()
        await testPendingAttachmentsStageThenRideTheTurn()
        testAKeyIsJudgedByShapeBeforeTheNetwork()
        await testAMangledPasteNeverReachesTheNetwork()
    }
}

@MainActor func testTokensRamp() async {
    expectEq(
        [Space.x1, Space.x2, Space.x3, Space.x4, Space.x6],
        [CGFloat(4), 8, 12, 16, 24],
        "tokens: space 4/8/12/16/24")
    _ = (Semantic.background, Semantic.surface, Semantic.foreground,
         Semantic.mutedForeground, Semantic.border, Semantic.accent,
         Semantic.destructive, Font.uiTitle, Font.uiBody, Font.uiCaption)
    expect(true, "tokens: rampa semántica sin Palette")
}

@MainActor func testChatCopy() async {
    let invalid = "This key is not valid. Check it at platform.openai.com."
    let persist = "I could not save the conversation. Check your disk space."
    let net = "I could not connect. Check your network and try again."
    expectEq(ChatCopy.emptyKey, "Paste your OpenAI key to get started.", "copy: vacío")
    expectEq(ChatCopy.error(ChatError.unauthorized), invalid, "copy: 401")
    expectEq(ChatCopy.error(ChatError.invalidKey), invalid, "copy: invalidKey")
    expectEq(ChatCopy.error(ChatError.forbidden),
             "This key has no permission. Check its access at platform.openai.com.",
             "copy: 403")
    expectEq(ChatCopy.error(ChatError.rateLimited),
             "Too many requests. Wait a moment and try again.",
             "copy: 429")
    expectEq(ChatCopy.error(ChatError.timeout), net, "copy: timeout")
    expectEq(ChatCopy.error(ChatError.unreachable), net, "copy: unreachable")
    expectEq(ChatCopy.error(ChatError.httpStatus(502)),
             "The server answered 502. Try again.", "copy: httpStatus")
    expectEq(ChatCopy.error(ChatError.noProvider),
             "No chat provider is available.", "copy: noProvider")
    expectEq(ChatCopy.error(ChatError.empty),
             "The model did not answer. Try again.", "copy: empty")
    expectEq(ChatCopy.error(SecretStoreError.denied),
             "I could not save the key to the keychain. Allow access and try again.",
             "copy: denied")
    expectEq(ChatCopy.error(PersistenceError.io), persist, "copy: persist io")
    expectEq(ChatCopy.error(PersistenceError.encoding), persist, "copy: persist enc")
    // Dos copys distintas desde Wave 9g: una marca lo delegado cuando el
    // especialista SI corre, y la otra es la nota de "aqui no hay runner".
    // Estaban fundidas, y la version larga salia en encargos que si estaban
    // ejecutandose — la app diciendo que el especialista llegaria algun dia
    // mientras trabajaba.
    expectEq(
        ChatCopy.handoff(Handoff(goal: "listar el escritorio", context: "x")),
        "Job: listar el escritorio",
        "copy: encargo en marcha")
    expectEq(
        ChatCopy.handoffUnavailable(
            Handoff(goal: "listar el escritorio", context: "x")),
        "Job: listar el escritorio — the specialist arrives in a future version.",
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
    // Live 2026-09-28: a turn every provider refused ended looking
    // "completed" — the banner is transient and nothing was persisted, so
    // the user saw a question that simply never got answered. The thread
    // keeps the record now; no partial assistant text is committed.
    expectEq(vm.messages.count, 2, "error: el fallo queda en el hilo")
    expect(vm.messages.last?.isStatus == true, "error: como línea de estado")
    expectEq(vm.messages.last?.text, ChatCopy.error(ChatError.timeout),
             "error: el mismo copy del banner")
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
    // Con forma de clave: lo que se prueba aquí es el 401 del servidor, no
    // el guardia local de forma, que ni siquiera dejaría salir a la red.
    vm.onboardingKey = "sk-proj-badbadbadbadbad"
    await awaitMain { await vm.submitOnboarding() }
    expect(vm.needsOnboarding, "onboard fail: sigue")
    expectEq(readOpenAI(secrets), nil, "onboard fail: no escribe")
    expectEq(vm.errorText, ChatCopy.error(ChatError.unauthorized), "onboard fail: 401")
    expectEq(chat.verifyKeys, ["sk-proj-badbadbadbadbad"], "onboard fail: pingueó")
}

@MainActor func testOnboardingPingOkWritesKey() async {
    let chat = FakeChatProvider()
    let secrets = TestSecretStore()
    let vm = onboard(chat, secrets)
    vm.onboardingKey = "  sk-proj-livelivelivelive  \n"
    await awaitMain { await vm.submitOnboarding() }
    expect(!vm.needsOnboarding, "onboard ok: entra")
    expectEq(readOpenAI(secrets), "sk-proj-livelivelivelive",
             "onboard ok: escribe OPENAI")
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
    // Wave 15a: reopen is not idle rollover (that has its own suite) — pin
    // "now" to the record's own updatedAt so this fixture is never stale.
    let vm = ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
        store: store, config: .default, now: { Date(timeIntervalSince1970: 1_700_000_000) })
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
    // Este recorrido no tiene runner cableado: es la nota de ausencia.
    let status = ChatCopy.handoffUnavailable(handoff)
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
    expectEq(chat.toolsSeen, [.delegate()], "tools: siempre delegate")
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
    // Desde Wave 9h lo que sale de la ventana deja una NOTA en vez de un
    // hueco: truncar en silencio es lo que hacia que el modelo olvidara cosas
    // que la usuaria recordaba haber dicho.
    expectEq(turns.map(\.role), [.system, .assistant, .user],
             "hist: ventana 2 mas la nota de lo comprimido")
    expectEq(turns.map(\.content).suffix(2), ["b", "tres"],
             "hist: los dos últimos de chat siguen enteros")
    expect(turns.first?.content.contains("uno") == true,
           "hist: y la primera petición sobrevive en la nota")
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
    // Ya no viaja entero: desde Wave 9d lo que el asistente dice entra en la
    // memoria acotado al presupuesto. El hilo y la persistencia siguen
    // guardando los 10k — se comprueba abajo — porque lo que se muestra y lo
    // que se recuerda dejaron de ser lo mismo.
    expect((after.last?.content.count ?? 0) <= ConversationMemory.defaultBudget + 200,
           "present: la memoria acota lo que el asistente dice")
    do {
        let loaded = try store.load(store.list()[0].id)
        expectEq(loaded?.messages.count, 5, "present: persiste los cinco")
        expectEq(loaded?.messages.last?.text.count, 10_000, "present: 10k persistido")
    } catch {
        expect(false, "present: persist no debía tirar \(error)")
    }
}

@MainActor func testPendingAttachmentsStageThenRideTheTurn() async {
    let store = MemoryAttachments()
    let vm = ChatViewModel(
        chat: FakeChatProvider(replies: [.success([.text("ok")])]),
        secrets: TestSecretStore([.openAI: "sk-test"]),
        store: MemoryConversationStore(),
        config: .default,
        attachments: store)
    vm.onAppear()
    let url = URL(fileURLWithPath: "/tmp/foto.png")
    expect(vm.attach(url) != nil, "attach: entra a la tira")
    expectEq(vm.pendingAttachments.count, 1, "attach: pendiente")
    vm.draft = "mira"
    vm.send()
    expect(vm.pendingAttachments.isEmpty, "send: la tira se vacía")
    expectEq(vm.messages.first?.attachments.count, 1, "send: viajan con el turno")
    await settle()
}

/// La forma se juzga en local y sin red. Deliberadamente floja: rechazar una
/// clave valida es peor que dejar pasar una mala, asi que solo atrapa lo que
/// no puede ser una clave.
@MainActor func testAKeyIsJudgedByShapeBeforeTheNetwork() {
    expect(APIKeyShape.looksPlausible("sk-proj-Ab3dEf6hIj9lMn2pQr5tUv8x"),
           "forma: una clave de proyecto pasa")
    expect(APIKeyShape.looksPlausible("  sk-Ab3dEf6hIj9lMn2pQr5tUv8x  "),
           "forma: los espacios de los bordes son del portapapeles, no de la clave")
    expect(!APIKeyShape.looksPlausible(
        "https://platform.openai.com/api/keys"),
           "forma: pegar la URL de donde se saca la clave no es la clave")
    expect(!APIKeyShape.looksPlausible("sk-corta"),
           "forma: una clave truncada a la mitad no llega")
    expect(!APIKeyShape.looksPlausible("sk-Ab3dEf6h Ij9lMn2pQr5tUv8x"),
           "forma: un espacio en medio delata un pegado partido")
    expect(!APIKeyShape.looksPlausible("Ab3dEf6hIj9lMn2pQr5tUv8xYz1234"),
           "forma: sin el prefijo no es de OpenAI")
}

/// El bug: cualquier cosa no vacia salia a la red y volvia 1-2 segundos
/// despues como "esta clave no es valida", sin decir que lo que pego no era
/// una clave.
@MainActor func testAMangledPasteNeverReachesTheNetwork() async {
    let chat = FakeChatProvider()
    let secrets = TestSecretStore()
    let vm = onboard(chat, secrets)

    vm.onboardingKey = "https://platform.openai.com/api/keys"
    await vm.submitOnboarding()

    expect(chat.verifyKeys.isEmpty,
           "forma: un pegado imposible no gasta un viaje a la red")
    expectEq(readOpenAI(secrets), nil, "forma: y no se guarda nada")
    expect(vm.needsOnboarding, "forma: sigue pidiendo la clave")
    expectEq(vm.errorText, ChatCopy.malformedKey,
             "forma: el aviso dice que lo pegado no tiene forma de clave")

    vm.onboardingKey = "sk-proj-Ab3dEf6hIj9lMn2pQr5tUv8x"
    await vm.submitOnboarding()
    expectEq(chat.verifyKeys.count, 1,
             "forma: una clave plausible si sale a verificarse")
}

// MARK: - Wave 10b: el padre actúa

private func openSafari(_ id: String = "c1") -> ChatDelta {
    .toolCalls([ToolCallRef(id: id, name: "open_app", arguments: #"{"name":"Safari"}"#)])
}

/// Ronda 1: texto + open_app → se abre, línea de estado, y el historial
/// guarda `assistant(toolCalls:[id])` + `tool(id)` para la ronda 2.
@MainActor func testParentToolRoundRecordsCallAndResult() async {
    let opener = FakeWorkspaceOpener(installed: ["Safari"])
    let tools = ParentToolRunner(workspace: opener)
    let chat = FakeChatProvider(replies: [
        .success([.text("Voy. "), openSafari()]),
        .success([.text("Listo, ya está Safari.")]),
    ])
    let vm = primed(chat: chat, parentTools: tools)
    vm.draft = "abre safari"
    vm.send()
    await pumpUntil("padre: idle") { !vm.busy }
    expectEq(opener.openedApps, ["Safari"], "padre: el opener fue llamado una vez")
    expectEq(chat.histories.count, 2, "padre: dos rondas")
    expect(chat.toolsSeen.map(\.name).contains("open_app"), "padre: anuncia open_app")
    expect(chat.toolsSeen.map(\.name).contains("delegate"), "padre: y delegate sigue")
    expectEq(vm.messages.map(\.isStatus), [false, false, true, false],
             "padre: usuario, prefacio, línea de estado, respuesta")
    expect(vm.messages[2].text.contains("Safari"), "padre: la línea nombra la app")
    let history = vm.historyForTests()
    let call = history.first { !$0.toolCalls.isEmpty }
    expectEq(call?.toolCalls.map(\.id), ["c1"], "padre: assistant(toolCalls:[c1])")
    expectEq(call?.toolCalls.first?.name, "open_app", "padre: con el nombre de la tool")
    let result = history.first { $0.role == .tool }
    expectEq(result?.toolCallID, "c1", "padre: tool(c1) responde a la llamada")
    expect(result?.content.contains("opened Safari") == true,
           "padre: el modelo lee el resultado de la tool")
    expect(chat.histories[1].contains { $0.role == .tool },
           "padre: la ronda 2 ya vio el resultado")
}

/// Wave 16a: look → click → look → type needs more than the three rounds
/// that fit opening apps. Every round up to the cap runs; the cap closes it
/// and the thread records it.
@MainActor func testParentToolRoundsCapAtThree() async {
    let opener = FakeWorkspaceOpener(installed: ["Safari"])
    let cap = ParentToolCopy.maxRounds
    expectEq(cap, 8, "tope: ocho rondas")
    let chat = FakeChatProvider(replies: (1...(cap + 1)).map { .success([openSafari("c\($0)")]) })
    let vm = primed(chat: chat, parentTools: ParentToolRunner(workspace: opener))
    vm.draft = "abre safari muchas veces"
    vm.send()
    await pumpUntil("tope: idle") { !vm.busy }
    expectEq(chat.histories.count, cap, "tope: \(cap) rondas y no más")
    expectEq(opener.openedApps.count, cap, "tope: todas se ejecutaron")
    expect(vm.messages.contains { $0.isStatus && $0.text == ParentToolCopy.roundCap(.en) },
           "tope: el hilo registra que se alcanzó")
}

/// open_app + delegate en la misma ronda: primero se abre, luego el encargo.
@MainActor func testParentToolThenHandoffInOneRound() async {
    let opener = FakeWorkspaceOpener(installed: ["Safari"])
    let handoff = Handoff(goal: "listar el escritorio", context: "")
    let chat = FakeChatProvider(replies: [
        .success([openSafari(), .handoff(handoff)]),
        .success([.text("NO")]),
    ])
    let vm = primed(chat: chat, parentTools: ParentToolRunner(workspace: opener))
    vm.draft = "abre safari y lista el escritorio"
    vm.send()
    await pumpUntil("mixto: idle") { !vm.busy }
    expectEq(opener.openedApps, ["Safari"], "mixto: primero se abre")
    expectEq(chat.histories.count, 1, "mixto: el encargo cierra el turno, no hay ronda 2")
    expect(vm.messages.contains { $0.text == ChatCopy.handoffUnavailable(handoff) },
           "mixto: luego el encargo (sin runner: la nota de ausencia)")
    let opened = vm.messages.firstIndex { $0.isStatus && $0.text.contains("Safari") } ?? 99
    let job = vm.messages.firstIndex { $0.text == ChatCopy.handoffUnavailable(handoff) } ?? -1
    expect(opened < job, "mixto: en ese orden")
}

/// Dos llamadas en una ronda, la primera con tarjeta: las respuestas `tool`
/// van seguidas y la tarjeta después, o el proveedor rechaza el historial.
@MainActor func testParentToolCardsComeAfterAllToolAnswers() async {
    let place = FoundPlace(name: "Cinépolis", address: "", lat: 19.4, lng: -99.1)
    let tools = ParentToolRunner(
        workspace: FakeWorkspaceOpener(installed: ["Safari"]), places: FakePlaces(found: [place]))
    let chat = FakeChatProvider(replies: [
        .success([.toolCalls([
            ToolCallRef(id: "c1", name: "find_places", arguments: #"{"query":"cines"}"#),
            ToolCallRef(id: "c2", name: "open_app", arguments: #"{"name":"Safari"}"#),
        ])]),
        .success([.text("Ahí tienes.")]),
    ])
    let vm = primed(chat: chat, parentTools: tools)
    vm.draft = "cines y safari"
    vm.send()
    await pumpUntil("orden: idle") { !vm.busy }
    let roles = chat.histories[1].map(\.role)
    let firstTool = roles.firstIndex(of: .tool) ?? -1
    expectEq(Array(roles[firstTool ..< firstTool + 2]), [.tool, .tool],
             "orden: las dos respuestas tool son consecutivas")
    expect(vm.messages.contains { $0.card != nil }, "orden: la tarjeta sí se pinta")
    expect((vm.messages.lastIndex { $0.card != nil } ?? -1)
           > (vm.messages.lastIndex { $0.recall?.role == .tool } ?? 99),
           "orden: la tarjeta va después de las respuestas")
}

// MARK: - Wave 10a: el turno lleva contexto

/// El bloque completo va solo en el ÚLTIMO turno del request; los anteriores
/// llevan la línea compacta. El hilo en pantalla no cambia.
@MainActor func testContextTravelsOnlyInTheCurrentTurn() async {
    let sensor = FakeContextSensor(TurnContext(
        source: .typed, focusedApp: "Safari", openDocuments: ["~/Desktop/notas.md"],
        clipboard: ClipboardSummary(kind: .text, preview: "SECRET")))
    let chat = FakeChatProvider(replies: [.success([.text("ok")]), .success([.text("ok2")])])
    let vm = primed(chat: chat, sensor: sensor)
    vm.draft = "resume esto"
    vm.send()
    await pumpUntil("ctx: idle 1") { !vm.busy }
    let first = chat.histories[0]
    expect(first.last?.role == .user, "ctx: el último turno es el usuario")
    expect(first.last?.content.contains("<context source=\"typed\"") == true, "ctx: bloque completo")
    expect(first.last?.content.contains("<focused_app>Safari</focused_app>") == true, "ctx: la app viaja")
    expect(first.last?.content.hasSuffix("\n\nresume esto") == true, "ctx: el texto va al final")
    expectEq(vm.messages.last { $0.role == .user }?.text, "resume esto", "ctx: el hilo muestra lo dicho")
    expect(vm.messages.last { $0.role == .user }?.recall?.content.hasPrefix("[typed · Safari · 1 docs · clipboard]") == true,
           "ctx: la memoria guarda la compacta")
    expectEq(sensor.calls.first?.channels, ContextChannels.default, "ctx: canales de config")

    vm.draft = "y ahora"
    vm.send()
    await pumpUntil("ctx: idle 2") { !vm.busy }
    let second = chat.histories[1]
    let users = second.filter { $0.role == .user }
    expectEq(users.count, 2, "ctx: dos turnos de usuario")
    expect(users[0].content.hasPrefix("[typed · Safari") && !users[0].content.contains("<context"),
           "ctx: el anterior lleva solo la compacta")
    expect(users[1].content.contains("<context") && users[1].content.hasSuffix("y ahora"),
           "ctx: el actual lleva el bloque")
    expect(RealtimeCodec.seed(from: vm.historyForTests())?.contains("<context") == false,
           "ctx: el seed realtime no se llena de XML")
}

@MainActor func testContextChannelsOffStillCarriesSource() async {
    let sensor = FakeContextSensor(TurnContext(source: .typed))
    let chat = FakeChatProvider(replies: [.success([.text("ok")])])
    let vm = primed(chat: chat, sensor: sensor, config: Config(contextChannels: []))
    vm.draft = "hola"
    vm.send()
    await pumpUntil("off: idle") { !vm.busy }
    expectEq(sensor.calls.first?.channels, [], "off: el sensor recibe cero canales")
    let last = chat.histories[0].last?.content ?? ""
    expect(last.contains("<context source=\"typed\" at=\"") && !last.contains("<focused_app"),
           "off: solo source y at")
}

/// Nada de pantalla ni portapapeles en `conversations/`.
@MainActor func testContextNeverPersists() async {
    let sensor = FakeContextSensor(TurnContext(
        source: .typed, focusedApp: "Safari",
        clipboard: ClipboardSummary(kind: .text, preview: "SECRET-CLIP")))
    let chat = FakeChatProvider(replies: [.success([.text("ok")])])
    let store = MemoryConversationStore()
    let vm = primed(chat: chat, store: store, sensor: sensor)
    vm.draft = "hola"
    vm.send()
    await pumpUntil("persist: idle") { !vm.busy }
    do {
        let saved = try store.load(store.list()[0].id)
        let all = saved?.messages.map(\.text).joined(separator: "\n") ?? ""
        expect(!all.contains("<context") && !all.contains("SECRET-CLIP") && !all.contains("Safari"),
               "persist: ni bloque, ni portapapeles, ni compacta en disco")
        expectEq(saved?.messages.first?.text, "hola", "persist: el texto crudo sí")
    } catch {
        expect(false, "persist: load no debía tirar \(error)")
    }
}

/// Security review 2026-09-05: la memoria entre sesiones se destila de
/// `historyTurns()`, que lleva la compacta. Lo que la memoria ve es otra
/// cosa que lo que el modelo ve: texto crudo, sin contexto.
@MainActor func testMemoryTurnsCarryRawTextOnly() async {
    let sensor = FakeContextSensor(TurnContext(source: .typed, focusedApp: "1Password"))
    let chat = FakeChatProvider(replies: [.success([.text("ok")])])
    let vm = primed(chat: chat, sensor: sensor)
    vm.draft = "resume esto"
    vm.send()
    await pumpUntil("memoria: idle") { !vm.busy }
    let model = vm.historyForTests().first { $0.role == .user }?.content ?? ""
    expect(model.contains("1Password"), "memoria: el modelo sí ve la compacta")
    let memory = await vm.memoryTurns()
    expectEq(memory.first { $0.role == .user }?.content, "resume esto", "memoria: texto crudo")
    expect(!memory.contains { $0.content.contains("1Password") || $0.content.contains("[typed") },
           "memoria: sin app, sin compacta")
    expectEq(memory.map(\.role), [.user, .assistant], "memoria: los turnos, sin líneas de estado")
    // Code review 2: a job result is shown whole but remembered bounded
    // (ConversationMemory.recall); the memory reads the bounded one.
    let report = String(repeating: "x", count: 10_000)
    vm.messages.append(ChatMessage(
        role: .assistant, text: report,
        recall: Recall(role: .tool, content: ConversationMemory.recall(report), toolCallID: "c1")))
    let last = await vm.memoryTurns().last
    expectEq(last?.content, ConversationMemory.recall(report),
             "memoria: la salida del encargo va acotada, como en el historial")
    expect((last?.content.count ?? 0) < report.count / 2, "memoria: y no entera")
    expectEq(last?.role, .assistant, "memoria: y atribuida al asistente")
}

// MARK: - Wave 10c 3D: open_url con puerta

private func openEvil(_ id: String = "c1") -> ChatDelta {
    .toolCalls([ToolCallRef(id: id, name: "open_url", arguments: #"{"url":"https://evil.example/?q=1"}"#)])
}

/// 25a. Un host que la usuaria no dijo: la hoja aparece, nada se abre hasta
/// que ella contesta; con "sí" se abre.
@MainActor func testForeignURLWaitsForTheSheet() async {
    let opener = FakeWorkspaceOpener()
    let approvals = FakeApprovals()
    let chat = FakeChatProvider(replies: [.success([openEvil()]), .success([.text("Abierto.")])])
    let vm = primed(chat: chat, parentTools: ParentToolRunner(workspace: opener), approvals: approvals)
    vm.draft = "resume esto"
    vm.send()
    await pumpUntil("puerta: la hoja") { vm.pendingApproval != nil }
    expectEq(vm.pendingApproval?.toolName, "open_url", "puerta: la hoja es para open_url")
    expect(opener.openedURLs.isEmpty, "puerta: nada se abrió antes de contestar")
    expect(vm.busy, "puerta: el turno sigue vivo mientras espera")
    vm.answerApproval(true)
    await pumpUntil("puerta: idle") { !vm.busy }
    expectEq(opener.openedURLs.map(\.absoluteString), ["https://evil.example/?q=1"], "puerta: con sí, se abre")
    expect(vm.pendingApproval == nil, "puerta: la hoja se cierra")
    expect(vm.messages.contains { $0.text == ChatCopy.approvalAnswer(true) }, "puerta: la respuesta queda en el hilo")
}

/// 25b. Con "no": no se abre, y el modelo lee `denied_by_user`.
@MainActor func testForeignURLDeniedIsAnInstruction() async {
    let opener = FakeWorkspaceOpener()
    let approvals = FakeApprovals()
    let chat = FakeChatProvider(replies: [.success([openEvil()]), .success([.text("Entendido.")])])
    let vm = primed(chat: chat, parentTools: ParentToolRunner(workspace: opener), approvals: approvals)
    vm.draft = "resume esto"
    vm.send()
    await pumpUntil("no: la hoja") { vm.pendingApproval != nil }
    vm.answerApproval(false)
    await pumpUntil("no: idle") { !vm.busy }
    expect(opener.openedURLs.isEmpty, "no: no se abrió")
    let answer = chat.histories.last?.first { $0.role == .tool }
    expectEq(answer?.content, Escalation.deniedByUser(.en), "no: el modelo lee la instrucción")
    expect(vm.messages.contains { $0.isStatus && $0.text.contains("evil.example") },
           "no: la línea de estado nombra lo que no se abrió")
}

/// 26. La memoria ya negó `open_url(https://evil.example:443)`: ni hoja ni apertura.
@MainActor func testRememberedDenialSkipsTheSheet() async {
    let opener = FakeWorkspaceOpener()
    let approvals = FakeApprovals(memory: ["open_url(https://evil.example:443)": false])
    let chat = FakeChatProvider(replies: [.success([openEvil()]), .success([.text("Ok.")])])
    let vm = primed(chat: chat, parentTools: ParentToolRunner(workspace: opener), approvals: approvals)
    vm.draft = "resume esto"
    vm.send()
    await pumpUntil("memoria: idle") { !vm.busy }
    expect(opener.openedURLs.isEmpty, "memoria: no se abrió")
    expect(await approvals.requested.isEmpty, "memoria: no se pidió")
    expect(vm.messages.contains { $0.isStatus && $0.text == ChatCopy.approvalRemembered("open_url", approved: false) },
           "memoria: el hilo dice denegado, como antes")
}

/// Dicha por la usuaria: sin hoja, como en 10b.
@MainActor func testSaidURLOpensWithoutSheet() async {
    let opener = FakeWorkspaceOpener()
    let approvals = FakeApprovals()
    let chat = FakeChatProvider(replies: [
        .success([.toolCalls([ToolCallRef(id: "c1", name: "open_url", arguments: #"{"url":"https://github.com/karen"}"#)])]),
        .success([.text("Ahí está.")]),
    ])
    let vm = primed(chat: chat, parentTools: ParentToolRunner(workspace: opener), approvals: approvals)
    vm.draft = "abre github"
    vm.send()
    await pumpUntil("dicha: idle") { !vm.busy }
    expectEq(opener.openedURLs.map(\.absoluteString), ["https://github.com/karen"], "dicha: abre")
    expect(await approvals.requested.isEmpty, "dicha: sin hoja")
}

/// Security review (ALTO): la hoja parseaba estricto y el ejecutor reparaba:
/// `{command: 'rm -rf x'}` mostraba solo "run_shell" y ejecutaba el comando.
/// La hoja enseña lo mismo que se va a ejecutar.
@MainActor func testApprovalDetailRepairsWhatItShows() {
    expectEq(ChatCopy.approvalDetail(tool: "run_shell", inputJSON: "{command: 'rm -rf x'}"),
             "rm -rf x", "hoja: repara como el ejecutor")
    expectEq(ChatCopy.approvalDetail(tool: "run_shell", inputJSON: "not json at all"),
             "run_shell", "hoja: lo irreparable sigue mostrando la tool")
}

/// Code review (ALTO): cambiar de conversación con la hoja abierta dejaba
/// la petición viva; al contestar, abría la URL de la conversación anterior
/// y escribía en la nueva. Cancelar el turno niega la petición.
@MainActor func testSwitchingConversationDropsTheGate() async {
    let opener = FakeWorkspaceOpener()
    let approvals = FakeApprovals()
    let chat = FakeChatProvider(replies: [.success([openEvil()]), .success([.text("x")])])
    let vm = primed(chat: chat, parentTools: ParentToolRunner(workspace: opener), approvals: approvals)
    vm.draft = "resume esto"
    vm.send()
    await pumpUntil("cambio: la hoja") { vm.pendingApproval != nil }
    vm.newConversation()
    expect(vm.pendingApproval == nil, "cambio: la hoja se cierra al cambiar")
    await pumpUntilAsync("cambio: la petición se negó sola") { !(await approvals.resolutions).isEmpty }
    expectEq((await approvals.resolutions).first?.approved, false, "cambio: negada, no colgada")
    await settle(0.1)
    expect(opener.openedURLs.isEmpty, "cambio: nada se abrió")
    expect(vm.messages.isEmpty, "cambio: la conversación nueva sigue limpia")
}

/// Security review (MEDIO): un solo hueco para la hoja; una petición de
/// encargo (voz) y la puerta del chat se pisaban. Ahora hacen cola y se
/// contestan en orden.
@MainActor func testTwoPendingRequestsAnswerInOrder() async {
    let opener = FakeWorkspaceOpener()
    let approvals = FakeApprovals()
    let chat = FakeChatProvider(replies: [.success([openEvil()]), .success([.text("x")])])
    let vm = primed(chat: chat, parentTools: ParentToolRunner(workspace: opener), approvals: approvals)
    vm.receiveJobEvent(.approvalRequested(ApprovalRequest(
        requestId: "job-1", toolName: "run_shell", summary: "", inputJSON: #"{"command":"ls"}"#)), from: nil)
    vm.draft = "resume esto"
    vm.send()
    await pumpUntilAsync("cola: dos pendientes") { await approvals.requested.count == 1 }
    expectEq(vm.pendingApproval?.requestId, "job-1", "cola: la primera sigue al frente")
    vm.answerApproval(true)
    await pumpUntilAsync("cola: la primera resuelta") { (await approvals.resolutions).contains { $0.id == "job-1" } }
    expectEq(vm.pendingApproval?.toolName, "open_url", "cola: ahora toca la puerta")
    vm.answerApproval(true)
    await pumpUntil("cola: idle") { !vm.busy }
    expectEq(opener.openedURLs.count, 1, "cola: la segunda también se contestó")
}
