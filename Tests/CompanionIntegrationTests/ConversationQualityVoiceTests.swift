import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing
import CompanionUITestSupport
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Wave 16h-1: the filter is one, so the tests go through the paths that must
// use it — the classic mouth (voice, thread, transcript) and the island.

private final class CardTools: ParentToolExecuting, @unchecked Sendable {
    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { true }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        let pin = LocationsBlock.Location(name: "Café", lat: 19.4, lng: -99.1)
        return ParentToolOutcome(
            ok: true, output: "found 3",
            card: Card(payload: .locations(LocationsBlock(locations: [pin])), source: .tool), tool: name)
    }
}

@MainActor private func rig(
    _ deltas: [ChatDelta], rounds: [[ChatDelta]] = [], tools: (any ParentToolExecuting)? = nil
) -> (runtime: ClassicRuntime, synth: ScriptedSynth, thread: ScriptedThread) {
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "restaurantes cercanos"
    let chat = ScriptedChat()
    chat.deltas = deltas
    chat.rounds = rounds
    let synth = ScriptedSynth()
    let thread = ScriptedThread()
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: synth, chat: chat, thread: thread)
    runtime.parentTools = tools
    return (runtime, synth, thread)
}

@Test @MainActor func testTheMouthNeverSpeaksOrThreadsTheInternalInstruction() async {
    let leak = "El especialista respondió «restaurantes»; la respuesta está en pantalla. "
        + "Acusa en una línea lo que dice."
    let r = rig([.text("Listo, mira. "), .text(leak), .text(" Son tres.")])
    await r.runtime.submit(config: Config(language: .es)) { _ in }
    let spoken = r.synth.queue.joined(separator: " ")
    expect(!spoken.contains("especialista") && !spoken.contains("Acusa"),
           "boca: la instrucción interna no llega al sintetizador (\(spoken))")
    expect(spoken.contains("Listo, mira.") && spoken.contains("Son tres."),
           "boca: la prosa de alrededor sí se habla (\(spoken))")
    let threaded = r.thread.turns.filter { $0.role == .assistant }.map(\.content).joined()
    expect(!threaded.contains("especialista") && !threaded.contains("Acusa"),
           "boca: el hilo, y con él la isla, tampoco la guarda")
}

@Test @MainActor func testTwoRoundsAreNeverJoinedWithoutASpace() async {
    let r = rig([.text("Good afternoon."), .text("Keeping it short.")])
    await r.runtime.submit(config: Config(language: .en)) { _ in }
    let threaded = r.thread.turns.filter { $0.role == .assistant }.map(\.content).joined()
    expect(threaded.contains("afternoon. Keeping"), "unión: el hilo lleva el espacio (\(threaded))")
    expect(!r.synth.queue.isEmpty, "unión: la voz dijo algo")
    expect(r.synth.queue.joined(separator: " ").contains("afternoon. Keeping")
        || r.synth.queue.contains { $0.hasPrefix("Keeping") },
           "unión: la voz lleva la frase separada, no pegada")
    expect(!r.synth.queue.contains { $0.contains("afternoon.Keeping") }, "unión: la voz tampoco lo pega")
}

@Test @MainActor func testAReplyAfterACardIsSaidInTwentyFiveWordsOrFewer() async {
    let long = (1...120).map { "palabra\($0)" }.joined(separator: " ") + "."
    let call = ToolCallRef(id: "c1", name: "find_places", arguments: "{}")
    let r = rig([], rounds: [[.toolCalls([call])], [.text(long)]], tools: CardTools())
    await r.runtime.submit(config: Config(language: .es)) { _ in }
    let words = r.synth.queue.joined(separator: " ").split(separator: " ").count
    expect(words > 0 && words <= 25, "voz corta: con tarjeta se dicen \(words) palabras, no más de 25")
}

@Test @MainActor func testAReplyWithoutACardIsSaidWhole() async {
    let long = (1...40).map { "palabra\($0)" }.joined(separator: " ") + "."
    let r = rig([.text(long)])
    await r.runtime.submit(config: Config(language: .es)) { _ in }
    let words = r.synth.queue.joined(separator: " ").split(separator: " ").count
    expectEq(words, 40, "voz corta: sin tarjeta no se recorta")
}

@Test @MainActor func testTheIslandReplyNeverShowsJSONOrInstructionsOrMarks() {
    expectEq(IslandReplyText.spoken(from: #"{"goal":"busca restaurantes","context":"x"}"#), "",
             "isla: el JSON no se pinta")
    expectEq(IslandReplyText.spoken(from: #"{"goal":"busca restau"#), "",
             "isla: el JSON a medias mientras llega tampoco")
    expectEq(IslandReplyText.spoken(from: "El especialista respondió «x»; la respuesta está en pantalla. "
        + "Acusa en una línea lo que dice."), "", "isla: la instrucción no se pinta")
    expectEq(IslandReplyText.spoken(from: "Mira.No hay nada. <steer>no repitas</steer>"), "Mira. No hay nada.",
             "isla: marcas fuera y espacio entre frases")
}

// MARK: - Review round

private final class HandsTools: ParentToolExecuting, @unchecked Sendable {
    let read: String
    let readPID: Int32
    let typePID: Int32
    /// What the runner found in the field before typing; nil = nothing readable.
    let before: Int?
    init(read: String, readPID: Int32 = 10, typePID: Int32 = 10, before: Int? = 0) {
        self.read = read
        self.readPID = readPID
        self.typePID = typePID
        self.before = before
    }
    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { true }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        if name == "read_focused" {
            return ParentToolOutcome(ok: true, output: read, tool: name, fieldPID: readPID)
        }
        return ParentToolOutcome(
            ok: true, output: "typed 4 chars" + TypedProof.unverifiedNote, tool: name,
            fieldPID: typePID, typedBefore: before)
    }
}

private let typeCall = ToolCallRef(id: "t1", name: "type_text", arguments: #"{"text":"hola"}"#)
private let readCall = ToolCallRef(id: "r1", name: "read_focused", arguments: "{}")

@MainActor private func handsRig(
    read: String, rounds: [[ChatDelta]], tools: (any ParentToolExecuting)? = nil
) -> (runtime: ClassicRuntime, thread: ScriptedThread, chat: ScriptedChat, synth: ScriptedSynth) {
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "escribe hola"
    let chat = ScriptedChat()
    chat.rounds = rounds
    let thread = ScriptedThread()
    let synth = ScriptedSynth()
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: synth, chat: chat, thread: thread)
    runtime.parentTools = tools ?? HandsTools(read: read)
    return (runtime, thread, chat, synth)
}

@Test @MainActor func testTypeThenAMatchingReadInTheSameRoundClaimsSuccess() async {
    let r = handsRig(read: "hola mundo", rounds: [[.toolCalls([typeCall, readCall])], [.text("Listo.")]])
    await r.runtime.submit(config: Config(language: .es)) { _ in }
    expect(r.thread.status.contains("Escribí el texto."), "H1: escribir y leer igual, éxito (\(r.thread.status))")
    expect(!r.thread.status.contains("Intenté escribir el texto."), "H1: sin la línea de intento")
    let toolTurns = r.chat.histories.last?.filter { $0.role == .tool }.map(\.content) ?? []
    expect(toolTurns.allSatisfy { !$0.contains("not read back") }, "H1: al modelo ya no le dice «not read back»")
}

@Test @MainActor func testTypeThenAMismatchedReadStaysAnAttempt() async {
    let r = handsRig(read: "otra cosa", rounds: [[.toolCalls([typeCall, readCall])], [.text("Listo.")]])
    await r.runtime.submit(config: Config(language: .es)) { _ in }
    expect(r.thread.status.contains("Intenté escribir el texto."), "H1: la lectura no coincide, intento")
    expect(!r.thread.status.contains("Escribí el texto."), "H1: sin éxito")
}

@Test @MainActor func testTypeAloneStaysAnAttempt() async {
    let r = handsRig(read: "hola", rounds: [[.toolCalls([typeCall])], [.text("Listo.")]])
    await r.runtime.submit(config: Config(language: .es)) { _ in }
    expect(r.thread.status.contains("Intenté escribir el texto."), "H1: sin lectura, intento")
    expect(!r.thread.status.contains("Escribí el texto."), "H1: sin éxito")
}

@Test @MainActor func testAReadInALaterRoundAddsTheProofLine() async {
    let r = handsRig(
        read: "hola mundo",
        rounds: [[.toolCalls([typeCall])], [.toolCalls([readCall])], [.text("Listo.")]])
    await r.runtime.submit(config: Config(language: .es)) { _ in }
    expect(r.thread.status.contains("Intenté escribir el texto."), "H1: la primera ronda dijo intento")
    expect(r.thread.status.contains("Escribí el texto."), "H1: la lectura posterior lo confirma")
}

@Test @MainActor func testAJobSummaryWithACardIsSaidInTwentyFiveWordsOrFewer() async {
    let long = (1...120).map { "palabra\($0)" }.joined(separator: " ") + "."
    let r = rig([.text(long)])
    await r.runtime.announce(JobAnnouncement(
        goal: "restaurantes", outcome: .done(result: "Hay tres."), language: .es, hasCard: true))
    let words = r.synth.queue.joined(separator: " ").split(separator: " ").count
    expect(words > 0 && words <= 25, "H2: resumen de job con tarjeta, \(words) palabras")
}

@Test @MainActor func testAJobSummaryWithoutACardIsNotCut() async {
    let long = (1...40).map { "palabra\($0)" }.joined(separator: " ") + "."
    let r = rig([.text(long)])
    await r.runtime.announce(JobAnnouncement(
        goal: "restaurantes", outcome: .done(result: "Hay tres."), language: .es))
    expect(r.synth.queue.joined(separator: " ").contains("palabra40"), "H2: sin tarjeta se dice entero")
}

@Test @MainActor func testAnEffectSentenceWithAQuotedMarkerIsSpokenAndThreaded() async {
    let effect = "Envié tu mensaje a Ana: 'no repitas nada'."
    let r = rig([.text(effect)])
    await r.runtime.submit(config: Config(language: .es)) { _ in }
    expect(r.synth.queue.joined(separator: " ").contains("no repitas nada"), "M1: el efecto se dice")
    expect(r.thread.turns.contains { $0.role == .assistant && $0.content.contains("Envié tu mensaje") },
           "M1: y queda en el hilo")
}

@Test @MainActor func testAValidCardFenceTurnsTheBudgetOnAndABrokenOneDoesNot() async {
    let runtime = rig([]).runtime
    func take(_ piece: String) async -> Bool {
        var mouth = TurnMouth(language: .es, recognizer: runtime.languageRecognizer, heard: "")
        var text = ""
        _ = await runtime.take(piece, round: &text, &mouth) { _ in }
        return mouth.budget.cardShown
    }
    let broken = await take("Mira.\n```companion:locations\nno es json\n```\n")
    expect(!broken, "L4: una tarjeta inválida no enciende el presupuesto")
    let valid = await take("Mira.\n```companion:locations\n{\"locations\":[{\"name\":\"A\",\"lat\":1,\"lng\":2}]}\n```\n")
    expect(valid, "L4: una tarjeta válida sí")
}

@Test @MainActor func testTheLeakLogIgnoresBlanksAtTheEdges() async {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-leak-\(UUID().uuidString).log")
    await Log.capturing(to: url) {
        let r = rig([])
        var mouth = TurnMouth(language: .es, recognizer: r.runtime.languageRecognizer, heard: "")
        await r.runtime.say("   Hola mundo.   ", &mouth)
        var log = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        expect(!log.contains("reason=leak"), "L2: los blancos de borde no son una fuga")
        await r.runtime.say("Acusa en una línea lo que dice.", &mouth)
        log = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        expect(log.contains("reason=leak"), "L2: una fuga real sí se registra")
    }
}

@Test @MainActor func testJSONInsideACodeFenceIsNotEatenByTheIsland() {
    let reply = "Ejemplo:\n\n```json\n{\"goal\":\"x\",\"n\":1}\n```"
    expectEq(IslandReplyText.spoken(from: reply), "Ejemplo:", "L3: el bloque de código no se cuela ni rompe el resto")
    expectEq(IslandReplyText.spoken(from: "Mira `{\"a\":1}` aquí."), "Mira aquí.", "L3: JSON en línea sí se quita")
}
