import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// Wave 15f-1 (TDD rows 1-3). In Karen's live test the hold brain wrote the
// `delegate` call as plain text — `{"goal":…,"context":…}`, sometimes after
// a short sentence — and the mouth read the JSON aloud while nothing was
// delegated. A goal object in the content is now the handoff; the mouth
// never receives any JSON candidate. Rule for braces: a `{` whose first
// non-blank character is `"` opens a JSON candidate that is never spoken;
// any other `{` is prose.
// Security review 2026-09-25 (HIGH-1): the content goal is a PROPOSAL now —
// it delegates only after the approval seam says yes; rows 1-2 approve it.

@Test @MainActor func mouthJSONTests() async {
    await testAPureGoalObjectIsTheHandoffAndNothingIsSpoken()
    await testProseBeforeTheObjectIsSpokenAndTheObjectDelegates()
    await testATruncatedObjectIsDroppedAndLogged()
    await testABraceInASentenceIsStillSpoken()
    await testAGoalObjectWithoutASpecialistIsDroppedNotSpoken()
    await testAnObjectPastTheCapIsDropped()
}

private final class HandoffBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Handoff] = []
    var all: [Handoff] { lock.withLock { items } }
    func append(_ h: Handoff) { lock.withLock { items.append(h) } }
}

private func jsonRuntime(
    _ deltas: [ChatDelta], synth: ScriptedSynth, thread: ScriptedThread = ScriptedThread(),
    delegated: HandoffBox? = HandoffBox(), approvals: FakeApprovals = FakeApprovals()
) -> ClassicRuntime {
    let transcriber = FakeTranscriber()
    transcriber.stoppedText = "pega el reporte"
    let chat = ScriptedChat()
    chat.deltas = deltas
    let runtime = ClassicRuntime(
        transcriber: transcriber, synthesizer: synth, chat: chat, thread: thread)
    if let delegated {
        runtime.onDelegate = { delegated.append($0) }
    }
    runtime.parentGuard = ParentToolGuard(approvals: approvals)
    return runtime
}

/// What the sheet or a spoken "yes" does to the proposal.
@MainActor private func approveProposal(_ approvals: FakeApprovals) async {
    await pumpUntilAsync("15f-1: la propuesta espera aprobación") { await approvals.waiting != nil }
    guard let waiting = await approvals.waiting else { return }
    _ = await approvals.resolve(requestId: waiting.requestId, approved: true)
}

private func logURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-\(name)-\(UUID().uuidString).log")
}

private func read(_ url: URL) -> String {
    (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}

@MainActor func testAPureGoalObjectIsTheHandoffAndNothingIsSpoken() async {
    let synth = ScriptedSynth()
    let thread = ScriptedThread()
    let delegated = HandoffBox()
    let approvals = FakeApprovals()
    // Split across deltas the way SSE delivers it.
    let runtime = jsonRuntime(
        [.text("{\"go"), .text("al\": \"x\",\n \"con"), .text("text\":\"y\"}")],
        synth: synth, thread: thread, delegated: delegated, approvals: approvals)
    await runtime.submit(config: Config(language: .es)) { _ in }
    await approveProposal(approvals)
    await pumpUntil("15f-1 fila 1: aprobado, delega") { !delegated.all.isEmpty }
    expectEq(delegated.all, [Handoff(goal: "x", context: "y")],
             "15f-1 fila 1: el objeto con goal es el handoff, tras el sí")
    expectEq(synth.queue, ["¿Lo delego?"],
             "15f-1 fila 1: la boca no recibe el JSON, solo la pregunta propia")
    expect(!thread.stream.contains("{"), "15f-1 fila 1: el hilo tampoco pinta el JSON")
    expect(!thread.turns.contains { $0.content.contains("goal") },
           "15f-1 fila 1: ni lo guarda como respuesta")
}

@MainActor func testProseBeforeTheObjectIsSpokenAndTheObjectDelegates() async {
    let synth = ScriptedSynth()
    let delegated = HandoffBox()
    let approvals = FakeApprovals()
    let runtime = jsonRuntime(
        [.text("Voy a pegarlo."), .text("{\"goal\":\"pega el reporte\"}")],
        synth: synth, delegated: delegated, approvals: approvals)
    await runtime.submit(config: Config(language: .es)) { _ in }
    await approveProposal(approvals)
    await pumpUntil("15f-1 fila 2: aprobado, delega") { !delegated.all.isEmpty }
    expectEq(synth.queue, ["Voy a pegarlo.", "¿Lo delego?"],
             "15f-1 fila 2: se habla la frase y la pregunta")
    expectEq(delegated.all.map(\.goal), ["pega el reporte"],
             "15f-1 fila 2: y el JSON se convierte en handoff")

    let spaced = ScriptedSynth()
    let second = HandoffBox()
    let secondApprovals = FakeApprovals()
    let withNewline = jsonRuntime(
        [.text("Voy a pegarlo.\n\n  {\"goal\": \"pega\", \"context\": \"reporte\"}\n")],
        synth: spaced, delegated: second, approvals: secondApprovals)
    await withNewline.submit(config: Config(language: .es)) { _ in }
    await approveProposal(secondApprovals)
    await pumpUntil("15f-1 fila 2: aprobado, delega") { !second.all.isEmpty }
    expectEq(spaced.queue, ["Voy a pegarlo.", "¿Lo delego?"],
             "15f-1 fila 2: con saltos de línea también")
    expectEq(second.all, [Handoff(goal: "pega", context: "reporte")],
             "15f-1 fila 2: goal y context")
}

@MainActor func testATruncatedObjectIsDroppedAndLogged() async {
    let url = logURL("json-truncated")
    await Log.capturing(to: url) {
        let synth = ScriptedSynth()
        let delegated = HandoffBox()
        let runtime = jsonRuntime(
            [.text("Voy a pegarlo. "), .text("{\"goal\":\"pega el rep")],
            synth: synth, delegated: delegated)
        await runtime.submit(config: Config(language: .es)) { _ in }
        expectEq(delegated.all, [], "15f-1 fila 3: no escala")
        expectEq(synth.queue, ["Voy a pegarlo."], "15f-1 fila 3: el JSON truncado no se habla")
        let log = read(url)
        expect(log.contains("mouth: dropped reason=json chars=20"),
               "15f-1 fila 3: log con motivo y tamaño")
        expect(!log.contains("pega el rep"), "15f-1 fila 3: nunca el texto")
    }
}

/// The rule pinned: a brace not followed by a quote is prose.
@MainActor func testABraceInASentenceIsStillSpoken() async {
    let synth = ScriptedSynth()
    let delegated = HandoffBox()
    let runtime = jsonRuntime(
        [.text("En Swift usa llaves { } para el bloque. Y {esto} "), .text("también.")],
        synth: synth, delegated: delegated)
    await runtime.submit(config: Config(language: .es)) { _ in }
    let said = synth.queue.joined(separator: " ")
    expect(said.contains("llaves { } para"), "15f-1: una llave suelta en prosa se habla")
    expect(said.contains("Y {esto} también."), "15f-1: y una llave con palabra dentro también")
    expectEq(delegated.all, [], "15f-1: la prosa nunca delega")
}

@MainActor func testAGoalObjectWithoutASpecialistIsDroppedNotSpoken() async {
    let url = logURL("json-no-specialist")
    await Log.capturing(to: url) {
        let synth = ScriptedSynth()
        let runtime = jsonRuntime(
            [.text("Claro. {\"goal\":\"x\"}")], synth: synth, delegated: nil)
        await runtime.submit(config: Config(language: .es)) { _ in }
        expectEq(synth.queue, ["Claro."], "15f-1: sin especialista el JSON tampoco se habla")
        expect(read(url).contains("mouth: dropped reason=json"),
               "15f-1: y queda contado en el log")
    }
}

@MainActor func testAnObjectPastTheCapIsDropped() async {
    let url = logURL("json-cap")
    await Log.capturing(to: url) {
        let synth = ScriptedSynth()
        let delegated = HandoffBox()
        let long = String(repeating: "a", count: 2100)
        let runtime = jsonRuntime(
            [.text("Listo. {\"goal\":\"\(long)"), .text("\"} Ya.")],
            synth: synth, delegated: delegated)
        await runtime.submit(config: Config(language: .es)) { _ in }
        expectEq(delegated.all, [], "15f-1: un objeto de más de 2000 no escala")
        expect(!synth.queue.contains { $0.contains("aaaa") }, "15f-1: ni se habla")
        expect(synth.queue.contains("Ya."), "15f-1: la prosa de después sí")
        expect(read(url).contains("mouth: dropped reason=json chars=2111"),
               "15f-1: se cuenta entero")
    }
}
