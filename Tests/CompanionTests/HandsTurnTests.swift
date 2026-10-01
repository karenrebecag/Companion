import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Revisión 15g (2026-09-25): barge-in entre llamadas, la copia de "actuando",
// y lo que nunca se guarda en el hilo (títulos de ventana, texto escrito).

@Test @MainActor func handsTurnTests() async {
    await testABargeInStopsTheRemainingCalls()
    testActingCopyNeverNamesAKeyOrATitle()
    testAWindowTitleIsNeverInTheStatusLine()
    await testMalformedArgumentsAreNotEchoed()
    testReadFocusedReturnsTheTextAroundTheCaret()
}

/// Cancels the task that runs it, the way a press cuts the turn mid-round.
private final class CancellingTools: ParentToolExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []
    var ran: [String] { lock.withLock { names } }

    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { true }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        lock.withLock { names.append(name) }
        withUnsafeCurrentTask { $0?.cancel() }
        return ParentToolOutcome(ok: true, output: "typed 4 chars", tool: name)
    }
}

@MainActor func testABargeInStopsTheRemainingCalls() async {
    let runtime = ClassicRuntime(
        transcriber: FakeTranscriber(), synthesizer: ScriptedSynth(), chat: ScriptedChat(),
        thread: ScriptedThread())
    let tools = CancellingTools()
    let calls = [
        ToolCallRef(id: "a", name: "type_text", arguments: #"{"text":"hola"}"#),
        ToolCallRef(id: "b", name: "press_key", arguments: #"{"key":"return"}"#),
    ]
    let turns = await Task {
        var mouth = TurnMouth(language: .es, recognizer: runtime.languageRecognizer, heard: "escribe hola y envíalo")
        return await runtime.act(
            calls, said: "", heard: "escribe hola y envíalo", using: tools, language: .es, &mouth)
    }.value
    expectEq(tools.ran, ["type_text"], "barge-in: Return no se pulsa tras el corte")
    expectEq(turns.count, 3, "barge-in: cada llamada tiene su respuesta")
    expect(turns.last?.content.hasPrefix("cancelled") == true, "barge-in: la segunda, cancelada")
}

@MainActor func testActingCopyNeverNamesAKeyOrATitle() {
    let targets = [
        ToolCallRef(id: "a", name: "press_key", arguments: #"{"key":"return"}"#),
        ToolCallRef(id: "b", name: "focus_window", arguments: #"{"title":"Banco - Saldo"}"#),
    ].map { ParentTool.target(of: $0) }
    expectEq(ParentToolCopy.acting(targets, .es), "Actuando…", "actuando: sin tecla ni título")
    expectEq(ParentToolCopy.acting(targets, .en), "Acting…", "acting: no key, no title")
}

@MainActor func testAWindowTitleIsNeverInTheStatusLine() {
    let outcome = ParentToolOutcome(ok: true, output: "raised Banco - Saldo",
                                    target: "Banco - Saldo", tool: "focus_window")
    for language in [AppLanguage.es, .en] {
        let line = ParentToolCopy.status("focus_window", outcome, language)
        expect(!line.contains("Banco"), "estado: sin título (\(language))")
    }
}

@MainActor func testMalformedArgumentsAreNotEchoed() async {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7))
    let out = await handsRunner(hands).execute(
        name: "type_text", argumentsJSON: #"["mi clave secreta"]"#)
    expect(!out.output.contains("secreta"), "argumentos rotos: no se repite el texto")
    expect(out.output.hasPrefix("invalid_args:"), "argumentos rotos: sigue siendo invalid_args")
}

/// Review 2026-09-25 MEDIUM: the first 500 characters of a long field are
/// rarely where the user is typing; the prompt line of a terminal is at the end.
@MainActor func testReadFocusedReturnsTheTextAroundTheCaret() {
    let text = String(repeating: "a", count: 1500) + "CARET" + String(repeating: "b", count: 495)
        + "END"
    let atCaret = FocusedText.clip(text, caret: 1500)
    expect(atCaret.contains("CARET"), "cursor: el texto alrededor del cursor")
    expect(atCaret.count <= FocusedText.limit + 2, "cursor: dentro del tope")
    expect(atCaret.hasPrefix("…"), "cursor: marca lo cortado delante")
    let tail = FocusedText.clip(text)
    expect(tail.hasSuffix("END"), "sin cursor: el final")
    expect(tail.hasPrefix("…"), "sin cursor: marca lo cortado")
    expectEq(FocusedText.clip(tail), tail, "recortar dos veces no cambia nada")
    expectEq(FocusedText.clip(text, caret: 10_000).suffix(3), "END", "cursor fuera: el final")
}
