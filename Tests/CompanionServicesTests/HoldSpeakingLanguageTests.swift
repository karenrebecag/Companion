import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// Lo que se elige en "Idioma al hablar" manda sobre la respuesta del hold,
// no solo sobre la voz: si la voz dijera francés y el texto saliera en
// español, el usuario oiría un acento y no un idioma.

@Test @MainActor func holdSpeakingLanguageInstructionNamesTheSpokenLanguage() {
    expectEq(ContextBlock.languageInstruction(.es, speaking: "fr"),
             "(Reply only in French, regardless of the language on screen or in earlier messages.)",
             "hold: otro idioma al hablar se nombra con su nombre en inglés")
    expectEq(ContextBlock.languageInstruction(.en, speaking: "es"),
             "(Reply only in Spanish, regardless of the language on screen or in earlier messages.)",
             "hold: la interfaz en inglés con habla en español")
    expectEq(ContextBlock.languageInstruction(.es, speaking: "es"),
             ContextBlock.languageInstruction(.es),
             "hold: habla igual a la interfaz no cambia ni un byte")
    expectEq(ContextBlock.languageInstruction(.en, speaking: nil),
             ContextBlock.languageInstruction(.en),
             "hold: sin elección es la instrucción de siempre")
    expectEq(ContextBlock.languageInstruction(.es, speaking: "zz"),
             ContextBlock.languageInstruction(.es),
             "hold: un código ajeno al catálogo no inventa un idioma")
}

@Test @MainActor func holdSpeakingLanguageReplyHintFollowsIt() {
    expectEq(ContextBlock.replyHint(.voice, language: .es, speaking: "fr"),
             "Answer in at most 2 sentences, in French, no markdown.",
             "hold: la pista corta también pide el idioma elegido")
    expectEq(ContextBlock.replyHint(.voice, language: .es, speaking: "es"),
             ContextBlock.replyHint(.voice, language: .es),
             "hold: igual a la interfaz, pista intacta")
    expect(ContextBlock.replyHint(.typed, language: .es, speaking: "fr") == nil,
           "hold: tecleado no lleva pista aunque haya elección")
}

@Test @MainActor func holdSpeakingLanguagePromptFollowsIt() {
    let french = ChatPrompt.system(
        ownerFirstName: "Karen", delegateEnabled: false, language: .es, voice: true,
        speaking: "fr")
    expect(french.contains("Answer in French."),
           "hold: el prompt de voz pide responder en el idioma elegido")
    expect(!french.contains("Responde en español."),
           "hold: ya no pide español en la misma frase")
    expect(french.contains("router con voz"), "hold: el resto de las reglas de voz sigue")

    expectEq(
        ChatPrompt.system(
            ownerFirstName: "Karen", delegateEnabled: false, language: .es, voice: true,
            speaking: "es"),
        ChatPrompt.system(
            ownerFirstName: "Karen", delegateEnabled: false, language: .es, voice: true),
        "hold: habla igual a la interfaz, prompt idéntico byte a byte")
    expectEq(
        ChatPrompt.system(
            ownerFirstName: "Karen", delegateEnabled: false, language: .en, speaking: "fr"),
        ChatPrompt.system(ownerFirstName: "Karen", delegateEnabled: false, language: .en),
        "hold: el chat escrito ignora el idioma al hablar")
}

@MainActor @Test func holdSpeakingLanguageReachesTheChatClient() {
    func systemSent(speaking: String?) -> String {
        var source: (@Sendable () -> String)?
        if let speaking { source = { speaking } }
        let transport = ScriptedTransport()
        transport.stub(.cerebras, ScriptedReply(lines: [SSEFixtures.hello, SSEFixtures.done]))
        let client = ChatProviderClient(
            secrets: TestSecretStore([.cerebras: "csk-test"]),
            probe: TestProbe(available: ["cerebras"]),
            transport: transport, ownerFirstName: "Karen",
            languageSource: { .es },
            speakingSource: source,
            catalog: [ProviderDescriptor.cerebras], voice: true)
        _ = collectChat(client)
        return transport.requests.first.map { chatSystem(chatBody($0)) } ?? ""
    }
    expect(systemSent(speaking: "fr").contains("Answer in French."),
           "hold: el cliente manda el idioma elegido en el prompt")
    expect(systemSent(speaking: nil).contains("Responde en español."),
           "hold: sin fuente, el prompt sigue la interfaz")
}

@MainActor private func spokenLanguageRuntime(
    heard: String, reply: String, speaking: String
) -> (ClassicRuntime, ScriptedChat, ScriptedSynth) {
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = heard
    let chat = ScriptedChat()
    chat.deltas = [.text(reply)]
    let synth = ScriptedSynth()
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: synth, chat: chat, thread: ScriptedThread())
    runtime.speechCode = { _ in speaking }
    return (runtime, chat, synth)
}

@Test @MainActor func holdSpeakingLanguageRidesTheTurnInstruction() async {
    let (runtime, chat, _) = spokenLanguageRuntime(
        heard: "abre Safari", reply: "Listo.", speaking: "fr")
    await runtime.submit(config: Config(language: .es)) { _ in }
    let sent = chat.histories.first?.last?.content ?? ""
    expectEq(sent, ContextBlock.languageInstruction(.es, speaking: "fr") + "\n\nabre Safari",
             "hold: la instrucción por turno pide el idioma elegido")

    let (same, sameChat, _) = spokenLanguageRuntime(
        heard: "abre Safari", reply: "Listo.", speaking: "es")
    await same.submit(config: Config(language: .es)) { _ in }
    expectEq(sameChat.histories.first?.last?.content,
             ContextBlock.languageInstruction(.es) + "\n\nabre Safari",
             "hold: habla igual a la interfaz, el turno queda como antes")
}

@Test @MainActor func holdSpeakingLanguageIsNotDroppedByTheGate() async {
    // Evidencia en español (lo oído) y una frase en inglés que antes se
    // descartaba como razonamiento filtrado: con el habla en inglés es la
    // respuesta pedida, no una fuga.
    let (runtime, _, synth) = spokenLanguageRuntime(
        heard: "abre la terminal por favor",
        reply: "We need to answer why the file is open.", speaking: "en")
    await runtime.submit(config: Config(language: .es)) { _ in }
    expectEq(synth.queue, ["We need to answer why the file is open."],
             "hold: el inglés elegido para hablar llega a la voz")
}

@MainActor @Test func holdSpeakingLanguageGateJudgesTheSpokenCode() {
    var spanishUnderEnglishUi = MouthLanguageGate(
        speaking: "es", recognizer: FakeRecognizer(), heard: "abre la terminal por favor")
    expectEq(
        spanishUnderEnglishUi.admit("We need to answer why. Abrí la terminal."),
        "Abrí la terminal.",
        "compuerta: con habla en español, el inglés filtrado se descarta")

    var french = MouthLanguageGate(
        speaking: "fr", recognizer: FakeRecognizer(), heard: "abre la terminal por favor")
    let cut = "We need to answer why. Voici la réponse."
    expectEq(french.admit(cut), cut,
             "compuerta: un código que el reconocedor no sabe juzgar no descarta nada")
    expectEq(french.dropped, [], "compuerta: sin descartes para un código sin juez")

    var interface = MouthLanguageGate(
        language: .es, recognizer: FakeRecognizer(), heard: "abre la terminal por favor")
    expectEq(interface.admit("We need to answer why. Abrí la terminal."), "Abrí la terminal.",
             "compuerta: el init por idioma de la app se comporta como siempre")
}
