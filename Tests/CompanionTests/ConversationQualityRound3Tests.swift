import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// Wave 16h-1, round 3: an unclosed internal tag quoted from a page must not
// silence the turn, a line break ends an instruction, the app says an effect
// the filter swallowed, and "Escribí" needs proof that the field CHANGED.

// MARK: - S-A: an unclosed tag removes only itself

@Test func testAnUnclosedTagIsRemovedAloneAndTheTextAfterItSurvives() {
    expectEq(SpeechFilter.clean("Ya lo hice. <steer> Moví el archivo."), "Ya lo hice. Moví el archivo.",
             "S-A: <steer> sin cierre")
    expectEq(SpeechFilter.clean("La página dice <context> y luego cerré la pestaña."),
             "La página dice y luego cerré la pestaña.", "S-A: <context> sin cierre")
    expectEq(SpeechFilter.clean("Copié <now> el texto a Notas."), "Copié el texto a Notas.", "S-A: <now>")
    expectEq(SpeechFilter.clean("Abrí <at href=\"x\"> Safari por ti."), "Abrí Safari por ti.", "S-A: <at …>")
}

@Test func testAnElementThatClosesInTheSameTextStillLosesItsContent() {
    expectEq(SpeechFilter.clean("Listo. <steer>no repitas</steer> Sigo."), "Listo. Sigo.", "S-A: con cierre, fuera")
}

@Test func testAnOpenTagHoldsAtMostOneSentenceAndThenGivesItBack() {
    var filter = SpeechFilter()
    expectEq(filter.admit("Listo. <steer>abrí Safari"), "Listo.", "S-A: lo que sigue al tag se retiene")
    expectEq(filter.flush(), "abrí Safari", "S-A: sin cierre, se devuelve al final del turno")
    var capped = SpeechFilter()
    _ = capped.admit("<steer>")
    let long = String(repeating: "palabra ", count: 40) + "fin."
    expectEq(capped.admit(long), long, "S-A: pasado el tope, todo se devuelve, sin contenido interno")
    expectEq(capped.flush(), "", "S-A: y no queda nada retenido")
}

@Test func testAnOpenTagThatClosesInALaterCutStillDropsItsContent() {
    var filter = SpeechFilter()
    expectEq(filter.admit("Listo. <steer>no repitas"), "Listo.", "S-A: abre")
    expectEq(filter.admit("nada de esto</steer> Sigo aquí."), "Sigo aquí.", "S-A: cierra dentro del tope")
}

// MARK: - S-B: a line break ends an instruction

@Test func testALineBreakEndsAnInstructionThatHasNoTerminator() {
    expectEq(SpeechFilter.clean("Acusa en una línea\nMoví el archivo."), "Moví el archivo.", "S-B: salto de línea")
    var filter = SpeechFilter()
    expectEq(filter.admit("Acusa en una línea\nMoví el archivo."), "Moví el archivo.", "S-B: en la voz también")
    expectEq(filter.admit("Y listo."), "Y listo.", "S-B: sin arrastre al siguiente corte")
}

// MARK: - M-A: proof needs the field to change

@Test func testTypedProofNeedsMoreOccurrencesThanBefore() {
    expect(TypedProof.verifies(typed: "hola", read: "hola mundo", before: 0), "prueba: aparece una vez más")
    expect(!TypedProof.verifies(typed: "hola", read: "hola mundo", before: 1), "prueba: ya estaba")
    expect(!TypedProof.verifies(typed: "sí", read: "sí", before: 1), "prueba: texto corto ya presente")
    expect(TypedProof.verifies(typed: "sí", read: "sí sí", before: 1), "prueba: el corto aumenta")
    expect(!TypedProof.verifies(typed: "hola", read: "hola", before: nil), "prueba: sin base no hay prueba")
    expect(!TypedProof.verifies(typed: "  ", read: "algo", before: 0), "prueba: nada escrito")
    expect(TypedProof.verifies(typed: "café", read: "un CAFE", before: 0), "prueba: sin acentos ni mayúsculas")
}

// MARK: - the runner takes the baseline

@Test @MainActor func testTheRunnerRecordsWhatTheFieldHeldBeforeTyping() async {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7), text: "hola viejo, hola")
    let out = await handsRunner(hands).execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
    expectEq(out.typedBefore, 2, "base: cuenta lo que ya había")
    expectEq(out.fieldPID, 7, "base: con el pid")
    let blank = FakeHands(field: FocusedField(app: "Notes", pid: 7), text: nil)
    let none = await handsRunner(blank).execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
    expectEq(none.typedBefore, nil, "base: campo ilegible, sin base")
    let read = await handsRunner(hands).execute(name: "read_focused", argumentsJSON: "{}")
    expectEq(read.fieldPID, 7, "base: la lectura lleva su pid")
}

// MARK: - integration through the classic turn

private final class FixtureTools: ParentToolExecuting, @unchecked Sendable {
    let read: String
    let readPID: Int32
    let before: Int?
    init(read: String, readPID: Int32 = 10, before: Int? = 0) {
        self.read = read
        self.readPID = readPID
        self.before = before
    }
    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { true }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        switch name {
        case "read_focused":
            return ParentToolOutcome(ok: true, output: read, tool: name, fieldPID: readPID)
        case "type_text":
            return ParentToolOutcome(
                ok: true, output: "typed 4 chars" + TypedProof.unverifiedNote, tool: name,
                fieldPID: 10, typedBefore: before)
        default:
            return ParentToolOutcome(ok: true, output: "opened", target: "Safari", tool: name)
        }
    }
}

private final class GatedTools: ParentToolExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: CheckedContinuation<Void, Never>?
    private var opened = false
    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { true }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        if name == "list_apps" {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if opened {
                    lock.unlock()
                    continuation.resume()
                } else {
                    waiting = continuation
                    lock.unlock()
                }
            }
        }
        return ParentToolOutcome(ok: true, output: "opened", target: "Safari", tool: name)
    }
    func release() {
        lock.lock()
        opened = true
        let continuation = waiting
        waiting = nil
        lock.unlock()
        continuation?.resume()
    }
}

@MainActor private func turn(
    _ rounds: [[ChatDelta]], tools: any ParentToolExecuting
) -> (runtime: ClassicRuntime, thread: ScriptedThread, synth: ScriptedSynth) {
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "abre Safari"
    let chat = ScriptedChat()
    chat.rounds = rounds
    let thread = ScriptedThread()
    let synth = ScriptedSynth()
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: synth, chat: chat, thread: thread)
    runtime.parentTools = tools
    return (runtime, thread, synth)
}

private let typeHola = ToolCallRef(id: "t1", name: "type_text", arguments: #"{"text":"hola"}"#)
private let readField = ToolCallRef(id: "r1", name: "read_focused", arguments: "{}")
private let openSafari = ToolCallRef(id: "o1", name: "open_app", arguments: #"{"name":"Safari"}"#)

@Test @MainActor func testAFieldThatAlreadyHeldTheTextIsNotProof() async {
    let tools = FixtureTools(read: "hola mundo", before: 1)
    let r = turn([[.toolCalls([typeHola, readField])], [.text("Listo.")]], tools: tools)
    await r.runtime.submit(config: Config(language: .es)) { _ in }
    expect(r.thread.status.contains("Intenté escribir el texto."), "M-A: ya estaba, intento (\(r.thread.status))")
    expect(!r.thread.status.contains("Escribí el texto."), "M-A: sin éxito")
}

@Test @MainActor func testAShortTextThatWasAlreadyThereIsNotProof() async {
    let call = ToolCallRef(id: "t1", name: "type_text", arguments: #"{"text":"sí"}"#)
    let tools = FixtureTools(read: "sí", before: 1)
    let r = turn([[.toolCalls([call, readField])], [.text("Listo.")]], tools: tools)
    await r.runtime.submit(config: Config(language: .es)) { _ in }
    expect(!r.thread.status.contains("Escribí el texto."), "M-A: «sí» preexistente no prueba nada")
}

@Test @MainActor func testAReadFromAnotherWindowIsNotProof() async {
    let tools = FixtureTools(read: "hola mundo", readPID: 99)
    let r = turn([[.toolCalls([typeHola, readField])], [.text("Listo.")]], tools: tools)
    await r.runtime.submit(config: Config(language: .es)) { _ in }
    expect(!r.thread.status.contains("Escribí el texto."), "M-A: otro pid no prueba")
    expect(r.thread.status.contains("Intenté escribir el texto."), "M-A: intento")
}

@Test @MainActor func testTypingWithNoReadableBaselineStaysAnAttempt() async {
    let tools = FixtureTools(read: "hola mundo", before: nil)
    let r = turn([[.toolCalls([typeHola, readField])], [.text("Listo.")]], tools: tools)
    await r.runtime.submit(config: Config(language: .es)) { _ in }
    expect(!r.thread.status.contains("Escribí el texto."), "M-A: sin base, intento")
}

@Test @MainActor func testAChangedFieldInTheSameWindowIsProof() async {
    let tools = FixtureTools(read: "hola mundo")
    let r = turn([[.toolCalls([typeHola, readField])], [.text("Listo.")]], tools: tools)
    await r.runtime.submit(config: Config(language: .es)) { _ in }
    expect(r.thread.status.contains("Escribí el texto."), "M-A: el caso bueno")
}

// MARK: - L2: one line per proof

@Test @MainActor func testTwoIdenticalTypingsConfirmedByOneReadGiveOneLine() async {
    let second = ToolCallRef(id: "t2", name: "type_text", arguments: #"{"text":"hola"}"#)
    let r = turn([[.toolCalls([typeHola, second, readField])], [.text("Listo.")]],
                 tools: FixtureTools(read: "hola hola"))
    await r.runtime.submit(config: Config(language: .es)) { _ in }
    expectEq(r.thread.status.filter { $0 == "Escribí el texto." }.count, 1, "L2: una línea, no dos (\(r.thread.status))")
}

@Test @MainActor func testTwoIdenticalTypingsConfirmedByALaterRoundGiveOneLine() async {
    let second = ToolCallRef(id: "t2", name: "type_text", arguments: #"{"text":"hola"}"#)
    let r = turn([[.toolCalls([typeHola, second])], [.toolCalls([readField])], [.text("Listo.")]],
                 tools: FixtureTools(read: "hola hola"))
    await r.runtime.submit(config: Config(language: .es)) { _ in }
    expectEq(r.thread.status.filter { $0 == "Escribí el texto." }.count, 1, "L2: la lectura tardía, una línea")
}

// MARK: - M-B: statuses at once

@Test @MainActor func testAStatusLineIsEmittedAsSoonAsItsToolFinishes() async {
    let tools = GatedTools()
    let slow = ToolCallRef(id: "u1", name: "list_apps", arguments: "{}")
    let r = turn([[.toolCalls([openSafari, slow])], [.text("Listo.")]], tools: tools)
    let running = Task { await r.runtime.submit(config: Config(language: .es)) { _ in } }
    await pumpUntilAsync("M-B: la primera línea llega con la segunda tool aún esperando") {
        r.thread.status.contains("Abrí Safari.")
    }
    expect(!r.thread.status.contains { $0.hasPrefix("Listé") }, "M-B: la segunda sigue en curso")
    tools.release()
    await running.value
    expectEq(r.thread.status.count, 2, "M-B: las dos líneas al final")
}

// MARK: - S-C: the app says an effect the filter swallowed

@Test @MainActor func testAnEffectTheFilterSwallowedIsSaidByTheApp() async {
    let r = turn([[.toolCalls([openSafari])], [.text("Acusa en una línea: abrí Safari.")]],
                 tools: FixtureTools(read: ""))
    await r.runtime.submit(config: Config(language: .es)) { _ in }
    expect(r.synth.queue.contains("Abrí Safari."), "S-C: la voz dice el efecto (\(r.synth.queue))")
    expect(r.thread.turns.contains { $0.role == .assistant && $0.content.contains("Abrí Safari.") },
           "S-C: y el hilo lo lleva")
}

@Test @MainActor func testAnEffectSentenceSurvivesAnUnclosedTagBeforeIt() async {
    let r = turn([[.toolCalls([openSafari])], [.text("Mira <steer> Abrí Safari.")]], tools: FixtureTools(read: ""))
    await r.runtime.submit(config: Config(language: .es)) { _ in }
    expect(r.synth.queue.joined(separator: " ").contains("Abrí Safari."), "S-C: <steer> sin cerrar, el efecto se dice")
    expect(r.thread.turns.contains { $0.role == .assistant && $0.content.contains("Abrí Safari.") }, "S-C: e hilo")
}

@Test @MainActor func testAnEffectSentenceSurvivesAMarkerOnItsOwnLine() async {
    let r = turn([[.toolCalls([openSafari])], [.text("Acusa en una línea\nAbrí Safari.")]], tools: FixtureTools(read: ""))
    await r.runtime.submit(config: Config(language: .es)) { _ in }
    expect(r.synth.queue.joined(separator: " ").contains("Abrí Safari."), "S-C: marcador en su línea, el efecto se dice")
}

@Test @MainActor func testNothingIsAddedWhenTheFilterDroppedNothing() async {
    let r = turn([[.toolCalls([openSafari])], [.text("Abrí Safari.")]], tools: FixtureTools(read: ""))
    await r.runtime.submit(config: Config(language: .es)) { _ in }
    expectEq(r.synth.queue.filter { $0 == "Abrí Safari." }.count, 1, "S-C: sin descarte, sin frase de más")
}

// MARK: - L1: a card of the job reaches the announcement

private struct CardSubmitter: JobSubmitter {
    let card: Bool
    func submit(_ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation) async throws -> JobResult {
        if card {
            let pin = LocationsBlock.Location(name: "Café", lat: 19.4, lng: -99.1)
            events.yield(.card(Card(payload: .locations(LocationsBlock(locations: [pin])), source: .tool)))
        }
        events.finish()
        return JobResult(output: "Hay tres.", isError: false)
    }
    func cancel() async {}
    func resolveApproval(requestId: String, approved: Bool) async {}
    var isBusy: Bool { get async { false } }
}

private final class AnnouncementBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [JobAnnouncement] = []
    var all: [JobAnnouncement] { lock.withLock { items } }
    func append(_ item: JobAnnouncement) { lock.withLock { items.append(item) } }
}

@Test @MainActor func testACardEventOfTheJobReachesTheAnnouncement() async {
    for card in [true, false] {
        let box = AnnouncementBox()
        await VoiceJobBridge.run(
            Handoff(goal: "restaurantes", context: ""), jobs: CardSubmitter(card: card),
            thread: ScriptedThread(), announce: { box.append($0) })
        expectEq(box.all.last?.hasCard, card, "L1: hasCard sigue al evento .card del job (\(card))")
    }
}
