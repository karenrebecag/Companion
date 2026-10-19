import CompanionCore
import CompanionServices
@testable import CompanionUI
import Foundation
import Testing
import CompanionUITestSupport
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

@Test @MainActor func voiceSessionTests() async {
    await testClassicParentToolLoopsOneRound()
    await testClassicFlushesFragmentBeforeNextRound()
    await testClassicTurnCarriesContext()
    await testClassicForeignURLOpensWithoutASheet()
}

@MainActor func testClassicParentToolLoopsOneRound() async {
    let opener = FakeWorkspaceOpener(installed: ["Safari"])
    // Spanish turn: the receipt and the model's reply must share a language,
    // or the reply does not restate the receipt and is rightly spoken.
    let h = makeVoiceHarness(key: nil, language: .es, parentTools: ParentToolRunner(workspace: opener))
    h.chat.rounds = [
        [.toolCalls([ToolCallRef(id: "c1", name: "open_app", arguments: #"{"name":"Safari"}"#)])],
        [.text("Listo, abrí Safari.")],
    ]
    h.transcriber.stoppedText = "abre safari"
    await h.session.start()
    await pumpUntil("padre cl: listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .classic
    }
    await h.session.advance()
    // 15d-5: the first utterance now ends at the comma.
    // Feedback inmediato: the reply restates the receipt, so it is not spoken;
    // the thread gets it once the round ends.
    await pumpUntil("padre cl: terminó la segunda ronda") {
        h.thread.turns.contains { $0.role == .assistant && $0.content.contains("abrí Safari.") }
    }
    expectEq(h.synth.queue, [], "padre cl: la respuesta que repite el recibo no suena")
    expectEq(opener.openedApps, ["Safari"], "padre cl: se abrió")
    expectEq(h.chat.histories.count, 2, "padre cl: dos rondas")
    expect(h.chat.histories[1].contains { $0.role == .tool && $0.toolCallID == "c1" },
           "padre cl: la ronda 2 vio el resultado")
    expect(h.chat.toolsSeen.map(\.name).contains("open_app"), "padre cl: anuncia open_app")
    expect(!h.chat.toolsSeen.map(\.name).contains("delegate"),
           "padre cl: sin jobs no anuncia delegate")
    expect(h.thread.status.contains { $0.contains("Safari") }, "padre cl: línea de estado")
}

@MainActor func testClassicFlushesFragmentBeforeNextRound() async {
    let opener = FakeWorkspaceOpener(installed: ["Safari"])
    // Spanish turn: the receipt and the model's reply must share a language,
    // or the reply does not restate the receipt and is rightly spoken.
    let h = makeVoiceHarness(key: nil, language: .es, parentTools: ParentToolRunner(workspace: opener))
    h.chat.rounds = [
        [.text("Voy a abrir Safari"),
         .toolCalls([ToolCallRef(id: "c1", name: "open_app", arguments: #"{"name":"Safari"}"#)])],
        [.text("Listo.")],
    ]
    h.transcriber.stoppedText = "abre safari"
    await h.session.start()
    await pumpUntil("flush cl: listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .classic
    }
    await h.session.advance()
    await pumpUntil("flush cl: terminó la segunda ronda") {
        h.thread.turns.contains { $0.role == .assistant && $0.content.contains("Listo.") }
    }
    // "Listo." restates the receipt and stays silent; the fragment still
    // gets said before the next round.
    expectEq(h.synth.queue, ["Voy a abrir Safari"], "flush cl: el fragmento se dice, el recibo ya cubre el cierre")
}

final class JobEventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [JobEvent] = []
    var events: [JobEvent] { lock.lock(); defer { lock.unlock() }; return _events }
    func append(_ event: JobEvent) { lock.lock(); _events.append(event); lock.unlock() }
}

// MARK: - Wave 10a: el turno de voz lleva contexto

@MainActor func testClassicTurnCarriesContext() async {
    let sensor = FakeContextSensor(TurnContext(source: .typed, focusedApp: "Notes"))
    let h = makeVoiceHarness(key: nil, sensor: sensor)
    h.chat.rounds = [[.text("Listo.")]]
    h.transcriber.stoppedText = "resume esto"
    await h.session.start()
    await pumpUntil("ctx cl: listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .classic
    }
    await h.session.advance()
    await pumpUntil("ctx cl: habló") { h.synth.queue.contains("Listo.") }
    let last = h.chat.histories.first?.last
    expect(last?.role == .user && last?.content.contains("<context source=\"voice\"") == true,
           "ctx cl: el último turno lleva el bloque con fuente voz")
    expect(last?.content.hasSuffix("resume esto") == true, "ctx cl: el texto al final")
    expect(h.thread.turns.contains { $0.role == .user && $0.content == "resume esto" },
           "ctx cl: el hilo recibe el texto crudo")
    expect(h.thread.turns.contains { $0.role == .assistant && $0.content.contains("Listo.") },
           "ctx cl: y la respuesta")
}

final class RecordingMemoryStore: MemoryStore, @unchecked Sendable {
    private let lock = NSLock()
    private var _sessions: [String] = []
    var sessions: [String] { lock.lock(); defer { lock.unlock() }; return _sessions }
    func load() -> MemoryPack { MemoryPack(core: "", recentSessions: [], notes: []) }
    func appendSession(_ summary: String) throws { lock.lock(); _sessions.append(summary); lock.unlock() }
}

// MARK: - open_url por voz: abrir es navegar, sin hoja

/// Clasico: un host que la usuaria no dijo se abre sin pedir hoja.
@MainActor func testClassicForeignURLOpensWithoutASheet() async {
    let opener = FakeWorkspaceOpener()
    let approvals = FakeApprovals()
    let box = JobEventBox()
    let h = makeVoiceHarness(
        key: nil, parentTools: ParentToolRunner(workspace: opener),
        onJobEvent: { box.append($0) }, approvals: approvals)
    h.chat.rounds = [
        [.toolCalls([ToolCallRef(id: "c1", name: "open_url", arguments: #"{"url":"https://evil.example/x"}"#)])],
        [.text("Listo.")],
    ]
    h.transcriber.stoppedText = "busca el clima"
    await h.session.start()
    await pumpUntil("sin hoja cl: listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .classic
    }
    let turn = Task { await h.session.advance() }
    await pumpUntil("sin hoja cl: abre") { !opener.openedURLs.isEmpty }
    expectEq(opener.openedURLs.map(\.absoluteString), ["https://evil.example/x"], "sin hoja cl: abre")
    expect(!box.events.contains { if case .approvalRequested = $0 { true } else { false } }, "sin hoja cl: no hubo solicitud")
    await turn.value
}
