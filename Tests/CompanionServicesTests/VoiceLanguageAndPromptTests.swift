import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Wave 15d-7 (TDD row 11): the language instruction rides in front of the
// hold's transcript, as Incredible does — the system prompt alone lost to
// English text on screen. Wave 15d-9 (row 13): the hold's system prompt
// carries voice rules; the typed chat's prompt does not change.

@Test @MainActor func voiceLanguageAndPromptTests() async {
    testLanguageInstructionPerLanguage()
    await testHoldUserTurnStartsWithTheLanguageInstruction()
    await testHoldUserTurnWithoutContextStillStartsWithIt()
    testVoicePromptCarriesTheVoiceRules()
    testTypedPromptIsUnchanged()
    testVoiceClientSendsTheVoicePromptAndTypedDoesNot()
}

@MainActor func testLanguageInstructionPerLanguage() {
    expectEq(ContextBlock.languageInstruction(.es),
             "(Responde solo en español, sin importar el idioma de la pantalla o de mensajes anteriores.)",
             "15d-7: instrucción en español")
    expectEq(ContextBlock.languageInstruction(.en),
             "(Reply only in English, regardless of the language on screen or in earlier messages.)",
             "15d-7: instrucción en inglés")
}

private func languageRuntime(
    heard: String, chat: ScriptedChat, thread: ScriptedThread
) -> ClassicRuntime {
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = heard
    chat.deltas = [.text("Listo.")]
    return ClassicRuntime(
        transcriber: transcriber, synthesizer: ScriptedSynth(), chat: chat, thread: thread)
}

@MainActor func testHoldUserTurnStartsWithTheLanguageInstruction() async {
    let chat = ScriptedChat()
    let thread = ScriptedThread()
    let runtime = languageRuntime(heard: "abre Safari", chat: chat, thread: thread)
    runtime.sensor = FakeContextSensor(TurnContext(source: .voice, focusedApp: "Mail"))
    await runtime.submit(config: Config(language: .es)) { _ in }

    let sent = chat.histories.first?.last?.content ?? ""
    let instruction = ContextBlock.languageInstruction(.es)
    expect(sent.hasPrefix("<context"),
           "15d-7 fila 11: el bloque de contexto abre el turno, como siempre")
    expect(sent.hasSuffix(instruction + "\n\nabre Safari"),
           "15d-7 fila 11: la instrucción de idioma va justo delante del transcript")
    let contextEnd = sent.range(of: "</context>")?.upperBound
    let instructionStart = sent.range(of: instruction)?.lowerBound
    expect(contextEnd != nil && instructionStart != nil && contextEnd! <= instructionStart!,
           "15d-7 fila 11: la instrucción va después del bloque <context>")
    expectEq(thread.turns.first?.content, "abre Safari",
             "15d-7: la burbuja de la UI no muestra la instrucción")
    expect(!(thread.history.first?.content ?? "").contains("Responde solo"),
           "15d-7: el historial guardado no la acumula turno a turno")
}

@MainActor func testHoldUserTurnWithoutContextStillStartsWithIt() async {
    let chat = ScriptedChat()
    let thread = ScriptedThread()
    let runtime = languageRuntime(heard: "what time is it", chat: chat, thread: thread)
    await runtime.submit(config: Config(language: .en)) { _ in }

    let sent = chat.histories.first?.last?.content ?? ""
    expectEq(sent, ContextBlock.languageInstruction(.en) + "\n\nwhat time is it",
             "15d-7: sin sensor, instrucción y lo oído")
}

@MainActor func testVoicePromptCarriesTheVoiceRules() {
    let es = ChatPrompt.system(
        ownerFirstName: "Karen", delegateEnabled: false, language: .es, voice: true)
    for rule in ["router con voz", "Dos frases casi siempre", "empieza por la noticia",
                 "máximo 3", "Nunca markdown", "emojis", "a menos que el contexto lo muestre",
                 "di qué hiciste en una frase"] {
        expect(es.contains(rule), "15d-9 fila 13: la regla de voz '\(rule)' está (es)")
    }
    expect(!es.contains("2 a 4 frases"), "15d-9: la voz no arrastra el largo del chat")
    let en = ChatPrompt.system(
        ownerFirstName: "Karen", delegateEnabled: false, language: .en, voice: true)
    for rule in ["router with a voice", "Two sentences almost always", "contractions",
                 "Lead with the news", "at most 3", "Never markdown", "emoji",
                 "unless the context shows it", "say what you did in one sentence"] {
        expect(en.contains(rule), "15d-9 fila 13: la regla de voz '\(rule)' está (en)")
    }
    expect(en.contains("Answer in English"), "15d-9: el idioma sigue dicho")
    expect(en.contains("You are not Hermes"), "15d-9: la honestidad del chat se conserva")
}

@MainActor func testTypedPromptIsUnchanged() {
    let typed = ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: false, language: .en)
    expect(typed.hasPrefix(
        "You are Companion, the voice assistant on Karen's Mac. "
        + "Answer in English, warm, direct, 2 to 4 sentences. "
        + "You are not Hermes, not a TUI, not in a terminal. "
        + "Do not invent backends or internal paths. "
        + "If you do not know something, say so. Talk, do not report."),
           "15d-9 fila 13: el prompt del chat escrito no cambia")
    expect(!typed.contains("router with a voice"), "15d-9: sin reglas de voz en el chat escrito")
    expectEq(typed, ChatPrompt.system(
        ownerFirstName: "Karen", delegateEnabled: false, language: .en, voice: false),
             "15d-9: voice false es el default")
}

@MainActor func testVoiceClientSendsTheVoicePromptAndTypedDoesNot() {
    func systemSent(voice: Bool) -> String {
        let transport = ScriptedTransport()
        transport.stub(.cerebras, ScriptedReply(lines: [SSEFixtures.hello, SSEFixtures.done]))
        let client = ChatProviderClient(
            secrets: TestSecretStore([.cerebras: "csk-test"]),
            probe: TestProbe(available: ["cerebras"]),
            transport: transport, ownerFirstName: "Karen",
            catalog: [ProviderDescriptor.cerebras], voice: voice)
        _ = collectChat(client)
        return transport.requests.first.map { chatSystem(chatBody($0)) } ?? ""
    }
    expect(systemSent(voice: true).contains("router with a voice"),
           "15d-9: el cliente del hold manda las reglas de voz")
    expect(!systemSent(voice: false).contains("router with a voice"),
           "15d-9: el cliente del chat escrito no")
}
