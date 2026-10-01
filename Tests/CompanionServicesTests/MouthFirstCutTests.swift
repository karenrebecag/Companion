import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Wave 15d-5 (TDD rows 6-8). The hold's first utterance used to wait for
// ". " and 25 characters, so the first audio sat behind a whole sentence of
// tokens. The first cut now lands at the first comma/semicolon/colon, at 40
// characters on a whole word, or 400 ms after the first token; after that
// the sentence rule is the same as before.

@Test @MainActor func mouthFirstCutTests() async {
    testFirstCutAtTheComma()
    testFirstCutAtFortyCharsOnAWholeWord()
    testFirstCutWaitsOnADecimalOrAnOpenEnd()
    testFirstCutEdges()
    testMouthBufferSwitchesToTheSentenceRuleAfterTheFirstCut()
    testMouthBufferStallTakesWhatIsThereOnlyOnce()
    testMouthBufferStallNeverSplitsAWord()
    await testRuntimeFirstUtteranceEndsAtTheComma()
    await testRuntimeFirstUtteranceCutsAtFortyChars()
    await testRuntimeSpeaksWhatIsBufferedWhenTheStreamStalls()
    await testRuntimeLaterUtterancesKeepTheSentenceRule()
}

// MARK: - Core

@MainActor func testFirstCutAtTheComma() {
    let cut = SentenceSplitter.takeFirstCut("Abrí Safari, y también")
    expectEq(cut?.sentence, "Abrí Safari,", "15d-5 fila 6: corta en la coma")
    expectEq(cut?.rest, "y también", "15d-5 fila 6: el resto sin espacios de más")
    expectEq(SentenceSplitter.takeFirstCut("Listo; ya está")?.sentence, "Listo;",
             "15d-5: punto y coma también corta")
    expectEq(SentenceSplitter.takeFirstCut("Mira: esto")?.sentence, "Mira:",
             "15d-5: dos puntos también cortan")
    expectEq(SentenceSplitter.takeFirstCut("Sí. Ahora")?.sentence, "Sí.",
             "15d-5: un punto corto también es un primer corte")
}

@MainActor func testFirstCutAtFortyCharsOnAWholeWord() {
    let text = "Hoy vamos a revisar juntos todos los pendientes de la semana"
    expect(text.count >= 60, "15d-5 fila 7: el stream de prueba mide 60")
    let cut = SentenceSplitter.takeFirstCut(text)
    expectEq(cut?.sentence, "Hoy vamos a revisar juntos todos los",
             "15d-5 fila 7: corta a los 40 en palabra entera")
    expectEq(cut?.rest, "pendientes de la semana", "15d-5 fila 7: la palabra partida queda")
    let exact = String(repeating: "a", count: 40) + " b"
    expectEq(SentenceSplitter.takeFirstCut(exact)?.sentence, String(repeating: "a", count: 40),
             "15d-5: una palabra que termina justo en 40 se corta ahí")
    let long = String(repeating: "x", count: 45) + " y"
    expectEq(SentenceSplitter.takeFirstCut(long)?.sentence, String(repeating: "x", count: 45),
             "15d-5: una palabra de más de 40 se dice entera")
}

@MainActor func testFirstCutWaitsOnADecimalOrAnOpenEnd() {
    expect(SentenceSplitter.takeFirstCut("Son las 10:30") == nil,
           "15d-5: una hora no es un corte")
    expect(SentenceSplitter.takeFirstCut("Cuesta 3,5") == nil,
           "15d-5: un decimal con coma no es un corte")
    expect(SentenceSplitter.takeFirstCut("Abrí Safari,") == nil,
           "15d-5: coma al final espera el siguiente token")
    expect(SentenceSplitter.takeFirstCut(String(repeating: "a", count: 40)) == nil,
           "15d-5: 40 sin espacio detrás todavía puede ser una palabra partida")
}

@MainActor func testFirstCutEdges() {
    expect(SentenceSplitter.takeFirstCut("") == nil, "15d-5: vacío no corta")
    expect(SentenceSplitter.takeFirstCut("   ") == nil, "15d-5: solo espacios no corta")
    expect(SentenceSplitter.takeFirstCut(", hola") == nil,
           "15d-5: una coma sin palabra delante no es una frase")
    expectEq(SentenceSplitter.takeFirstCut("Hola 👋, ¿qué tal?")?.sentence, "Hola 👋,",
             "15d-5: emoji y unicode no rompen el corte")
    expectEq(SentenceSplitter.takeFirstCut("Primera línea\nsegunda")?.sentence, "Primera línea",
             "15d-5: un salto de línea corta")
}

@MainActor func testMouthBufferSwitchesToTheSentenceRuleAfterTheFirstCut() {
    var mouth = MouthBuffer()
    expect(!mouth.awaitsFirstCut, "15d-5: sin texto no hay nada que cronometrar")
    expectEq(mouth.append("Abrí"), [], "15d-5: una palabra sola espera")
    expect(mouth.awaitsFirstCut, "15d-5: con una palabra el reloj corre")
    expectEq(mouth.append(" Safari, y también abrí Notas, que"), ["Abrí Safari,"],
             "15d-5: primer corte a la coma")
    expect(!mouth.awaitsFirstCut, "15d-5: tras el primer corte ya no hay reloj")
    expectEq(mouth.append(" es otra cosa. Y"), ["y también abrí Notas, que es otra cosa."],
             "15d-5: después, la regla de oración (la coma ya no corta)")
    expectEq(mouth.drain(), "Y", "15d-5: drain devuelve lo que queda")
    expect(mouth.drain() == nil, "15d-5: drain vacío es nil")
}

@MainActor func testMouthBufferStallTakesWhatIsThereOnlyOnce() {
    var mouth = MouthBuffer()
    expect(mouth.takeStalled() == nil, "15d-5 fila 8: sin texto no hay nada que decir")
    _ = mouth.append("Claro que sí ")
    expectEq(mouth.takeStalled(), "Claro que sí", "15d-5 fila 8: se enuncia lo que hay")
    expect(mouth.takeStalled() == nil, "15d-5: el reloj solo vale para el primer corte")
    expectEq(mouth.append(" y, además"), [], "15d-5: tras el reloj, la coma ya no corta")
}

/// Code review 2026-09-24 (medio): a stall can land mid-token ("Claro que
/// s" + "í"). The stall speaks up to the last whitespace and keeps the
/// tail for the next cut; a buffer with no whitespace at all is one word
/// and is said whole.
@MainActor func testMouthBufferStallNeverSplitsAWord() {
    var mouth = MouthBuffer()
    _ = mouth.append("Claro que s")
    expectEq(mouth.takeStalled(), "Claro que", "stall: corta en el último espacio")
    expectEq(mouth.pending, "s", "stall: la palabra a medias se queda")
    expectEq(mouth.append("í, ya."), [], "stall: después, la regla de oración")
    expectEq(mouth.drain(), "sí, ya.", "stall: la palabra llega entera")

    var single = MouthBuffer()
    _ = single.append("  Perfecto")
    expectEq(single.takeStalled(), "Perfecto", "stall: sin espacio interior se dice entera")
    expectEq(single.pending, "", "stall: no queda nada")

    var unicode = MouthBuffer()
    _ = unicode.append("Hola 👋 ma\tña")
    expectEq(unicode.takeStalled(), "Hola 👋 ma", "stall: un tab también es frontera")
    expectEq(unicode.pending, "ña", "stall: el resto tras el tab")
}

// MARK: - ClassicRuntime

private func mouthRuntime(
    _ chat: any ChatProvider, synth: ScriptedSynth, heard: String = "abre Safari"
) -> ClassicRuntime {
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = heard
    return ClassicRuntime(
        transcriber: transcriber, synthesizer: synth, chat: chat, thread: ScriptedThread())
}

@MainActor func testRuntimeFirstUtteranceEndsAtTheComma() async {
    let chat = ScriptedChat()
    chat.deltas = [.text("Abrí Safari, y también abrí Notas para ti. Listo.")]
    let synth = ScriptedSynth()
    await mouthRuntime(chat, synth: synth).submit(config: Config(language: .es)) { _ in }
    expectEq(synth.queue, ["Abrí Safari,", "y también abrí Notas para ti.", "Listo."],
             "15d-5 fila 6: la primera frase sale a la coma")
}

@MainActor func testRuntimeFirstUtteranceCutsAtFortyChars() async {
    let chat = ScriptedChat()
    chat.deltas = [.text("Hoy vamos a revisar juntos todos los pendientes de la semana")]
    let synth = ScriptedSynth()
    await mouthRuntime(chat, synth: synth).submit(config: Config(language: .es)) { _ in }
    expectEq(synth.queue.first, "Hoy vamos a revisar juntos todos los",
             "15d-5 fila 7: corte a los 40")
}

@MainActor func testRuntimeSpeaksWhatIsBufferedWhenTheStreamStalls() async {
    let synth = ScriptedSynth()
    let chat = StallingChat(synth: synth, first: "Claro que sí", then: " ya lo abro.")
    let runtime = mouthRuntime(chat, synth: synth)
    runtime.firstCutWait = {}
    await runtime.submit(config: Config(language: .es)) { _ in }
    expectEq(chat.queueWhenResumed, ["Claro que"],
             "15d-5 fila 8: con el stream parado, se enuncia lo que hay antes de que siga")
    expectEq(synth.queue, ["Claro que", "sí ya lo abro."],
             "15d-5: lo que llega después sale por la regla de siempre")
}

@MainActor func testRuntimeLaterUtterancesKeepTheSentenceRule() async {
    let chat = ScriptedChat()
    chat.rounds = [[.text("Listo, abrí Safari, "), .text("y también Notas. Ahora")]]
    let synth = ScriptedSynth()
    await mouthRuntime(chat, synth: synth).submit(config: Config(language: .es)) { _ in }
    expectEq(synth.queue, ["Listo,", "abrí Safari, y también Notas.", "Ahora"],
             "15d-5: solo el primer corte es temprano")
}

/// Yields `first`, then holds the stream open until the mouth has spoken
/// (bounded, so a missing timer fails instead of hanging), then finishes.
final class StallingChat: ChatProvider, @unchecked Sendable {
    let synth: ScriptedSynth
    let first: String
    let then: String
    private let lock = NSLock()
    private var _queueWhenResumed: [String] = []
    var queueWhenResumed: [String] { lock.withLock { _queueWhenResumed } }

    init(synth: ScriptedSynth, first: String, then: String) {
        self.synth = synth
        self.first = first
        self.then = then
    }

    func stream(_ history: [Turn], tools: [ToolSpec]) -> AsyncThrowingStream<ChatDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                continuation.yield(.text(first))
                let deadline = Date().addingTimeInterval(2)
                while synth.queue.isEmpty, Date() < deadline {
                    do { try await Task.sleep(nanoseconds: 2_000_000) } catch { break }
                }
                lock.withLock { _queueWhenResumed = synth.queue }
                continuation.yield(.text(then))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func verify(_ key: String, provider: ProviderDescriptor) async throws {}
}
