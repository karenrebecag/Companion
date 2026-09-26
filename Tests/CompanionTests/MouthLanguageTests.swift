import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Wave 15f-2 (TDD row 4). Once, the hold brain leaked its English reasoning
// ("We need to answer why…") into a Spanish reply and the mouth said it. A
// sentence the recognizer is confident is in another language is dropped
// before it is enqueued — only when it has at least four words, so names
// and short neutral fragments ("OK", "Safari") are never touched, and only
// once the user's words or an earlier sentence were in the app language: a
// reply wholly in another language is said, since that beats a silent turn.

@Test @MainActor func mouthLanguageTests() async {
    testAForeignSentenceIsDroppedFromACut()
    testShortOrUnsureSentencesAreNeverDropped()
    testTheAppLanguageIsNeverDropped()
    testWithoutEvidenceAForeignSentenceIsKept()
    testRemovingDroppedSentencesFromTheThreadText()
    await testRuntimeDropsTheLeakedReasoning()
    await testRuntimeNeverDropsShortFragments()
    await testRuntimeLeavesAnEnglishReplyInEnglishAlone()
    await testRuntimeSaysAWhollyForeignReplyInOrder()
    testTheSystemRecognizerTellsTheLeakFromSpanish()
}

/// English when the sentence has one of the listed words, else Spanish.
struct FakeRecognizer: LanguageRecognizing {
    var englishWords: Set<String> = ["we", "need", "the", "is", "hello", "opened"]
    var confidence = 0.9

    func dominant(_ text: String) -> DetectedLanguage? {
        let words = text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
        let english = words.contains { englishWords.contains($0) }
        return DetectedLanguage(code: english ? "en" : "es", confidence: confidence)
    }
}

/// Everything is confidently English.
struct AlwaysEnglish: LanguageRecognizing {
    func dominant(_ text: String) -> DetectedLanguage? {
        DetectedLanguage(code: "en", confidence: 0.99)
    }
}

// MARK: - Core

@MainActor func testAForeignSentenceIsDroppedFromACut() {
    var gate = MouthLanguageGate(language: .es, recognizer: FakeRecognizer())
    expectEq(gate.admit("Listo."), "Listo.", "idioma: se queda (y es evidencia de español)")
    expectEq(gate.admit("We need to answer why. Ya está."), "Ya está.",
             "15f-2 fila 4: la frase en inglés sale del corte")
    expectEq(gate.dropped, ["We need to answer why."], "idioma: queda registrada")
    expect(gate.admit("We need to answer why not.") == nil,
           "idioma: un corte entero en otro idioma no se dice")

    var fromHeard = MouthLanguageGate(
        language: .es, recognizer: FakeRecognizer(), heard: "por qué no abriste la terminal")
    expectEq(fromHeard.admit("We need to answer why. Abrí la terminal."), "Abrí la terminal.",
             "idioma: lo que dijo el usuario en español basta como evidencia desde el inicio")
}

@MainActor func testShortOrUnsureSentencesAreNeverDropped() {
    // Evidence from the user's words, so only the fragment rules can keep these.
    var gate = MouthLanguageGate(
        language: .es, recognizer: FakeRecognizer(englishWords: ["abrí", "safari"]),
        heard: "abre la terminal")
    var english = MouthLanguageGate(
        language: .es, recognizer: FakeRecognizer(), heard: "abre la terminal")
    _ = english.admit("Listo.")
    expectEq(english.admit("Hello."), "Hello.", "idioma: menos de cuatro palabras nunca se descarta")
    expectEq(english.admit("OK"), "OK", "idioma: OK tampoco")
    expectEq(english.admit(""), nil, "idioma: vacío es nada")
    expectEq(gate.admit("Abrí Safari."), "Abrí Safari.", "idioma: 'Abrí Safari' tampoco")
    var unsure = MouthLanguageGate(
        language: .es, recognizer: FakeRecognizer(confidence: 0.59), heard: "abre la terminal")
    expectEq(unsure.admit("We need to answer why."), "We need to answer why.",
             "idioma: bajo 0.6 de confianza no se descarta")
    struct Silent: LanguageRecognizing {
        func dominant(_ text: String) -> DetectedLanguage? { nil }
    }
    var silent = MouthLanguageGate(language: .es, recognizer: Silent(), heard: "hola")
    expectEq(silent.admit("Hola a todos los presentes."),
             "Hola a todos los presentes.", "idioma: sin veredicto no se descarta")
    expectEq(english.dropped + gate.dropped + unsure.dropped + silent.dropped, [],
             "idioma: nada descartado")
}

@MainActor func testTheAppLanguageIsNeverDropped() {
    var gate = MouthLanguageGate(language: .en, recognizer: AlwaysEnglish(), heard: "why")
    expectEq(gate.admit("We need to answer why. The file is there."),
             "We need to answer why. The file is there.", "idioma: en con app en, intacto")
    expectEq(gate.dropped, [], "idioma: nada descartado en el idioma de la app")
}

/// No evidence that the conversation is in the app language (the user spoke
/// another one, nothing in the app language said yet): the reply is said.
@MainActor func testWithoutEvidenceAForeignSentenceIsKept() {
    var gate = MouthLanguageGate(
        language: .es, recognizer: AlwaysEnglish(), heard: "open the terminal")
    expectEq(gate.admit("I opened the terminal for you."), "I opened the terminal for you.",
             "idioma: sin evidencia de español, se dice")
    expectEq(gate.dropped, [], "idioma: nada descartado")
}

@MainActor func testRemovingDroppedSentencesFromTheThreadText() {
    expectEq(MouthLanguageGate.removing(
        ["We need to answer why."], from: "Listo. We need to answer why. Ya está."),
             "Listo. Ya está.", "idioma: el hilo no guarda lo descartado")
    expectEq(MouthLanguageGate.removing([], from: "Listo."), "Listo.", "idioma: sin nada, igual")
    expectEq(MouthLanguageGate.removing(["No está."], from: "Listo."), "Listo.",
             "idioma: lo que no aparece no rompe")
}

// MARK: - ClassicRuntime

private func languageRuntime(
    reply: [String], synth: ScriptedSynth, thread: ScriptedThread,
    recognizer: any LanguageRecognizing
) -> ClassicRuntime {
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "por qué no abriste la terminal"
    let chat = ScriptedChat()
    chat.deltas = reply.map { .text($0) }
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: synth, chat: chat, thread: thread)
    runtime.languageRecognizer = recognizer
    return runtime
}

@MainActor func testRuntimeDropsTheLeakedReasoning() async {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-language-\(UUID().uuidString).log")
    await Log.capturing(to: url) {
        let synth = ScriptedSynth()
        let thread = ScriptedThread()
        let runtime = languageRuntime(
            reply: ["Listo. We need to answer why. ", "Ya está."],
            synth: synth, thread: thread, recognizer: FakeRecognizer())
        await runtime.submit(config: Config(language: .es)) { _ in }
        expectEq(synth.queue, ["Listo.", "Ya está."], "15f-2 fila 4: se habla solo el español")
        let log = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        expect(log.contains("mouth: dropped reason=language chars=22"),
               "15f-2 fila 4: log con motivo y tamaño")
        expect(!log.contains("We need"), "15f-2 fila 4: nunca el texto")
        expectEq(thread.turns.last?.content, "Listo. Ya está.",
                 "15f-2: el hilo guarda lo que se dijo")
    }
}

@MainActor func testRuntimeNeverDropsShortFragments() async {
    let synth = ScriptedSynth()
    let runtime = languageRuntime(
        reply: ["Abrí Safari. OK"], synth: synth, thread: ScriptedThread(),
        // The user spoke Spanish, so the gate is armed; both fragments read as English.
        recognizer: FakeRecognizer(englishWords: ["abrí", "safari", "ok"]))
    await runtime.submit(config: Config(language: .es)) { _ in }
    expectEq(synth.queue.joined(separator: " "), "Abrí Safari. OK",
             "15f-2: 'Abrí Safari' y 'OK' nunca se descartan")
}

@MainActor func testRuntimeLeavesAnEnglishReplyInEnglishAlone() async {
    let synth = ScriptedSynth()
    let reply = "I opened the terminal for you. It is ready to use now."
    let runtime = languageRuntime(
        reply: [reply], synth: synth, thread: ScriptedThread(), recognizer: AlwaysEnglish())
    await runtime.submit(config: Config(language: .en)) { _ in }
    expectEq(synth.queue.joined(separator: " "), reply, "15f-2: en con app en, intacto")
}

@MainActor func testRuntimeSaysAWhollyForeignReplyInOrder() async {
    let synth = ScriptedSynth()
    let reply = "I opened the terminal for you. It is ready to use now."
    let runtime = languageRuntime(
        reply: [reply], synth: synth, thread: ScriptedThread(), recognizer: AlwaysEnglish())
    await runtime.submit(config: Config(language: .es)) { _ in }
    expectEq(synth.queue.joined(separator: " "), reply,
             "15f-2: toda en otro idioma y sin evidencia de español se dice (mejor que silencio)")
}

// MARK: - Services adapter

@MainActor func testTheSystemRecognizerTellsTheLeakFromSpanish() {
    let system = NaturalLanguageRecognizer()
    let leak = system.dominant("We need to answer why not opening terminal first.")
    expectEq(leak?.code, "en", "NL: el razonamiento es inglés")
    expect((leak?.confidence ?? 0) >= 0.6, "NL: con confianza")
    for spanish in [
        "Ya abrí la terminal para ti.",
        "Listo, abrí Visual Studio Code en tu proyecto.",
        "Te abrí Google Chrome con la página de GitHub.",
        "Voy a pegar el reporte en Notion.",
    ] {
        var gate = MouthLanguageGate(
            language: .es, recognizer: system, heard: "abre la terminal por favor")
        expectEq(gate.admit(spanish), spanish,
                 "NL: español con nombres propios nunca se descarta")
    }
}
