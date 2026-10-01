import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

// DM1c-2 (wave-dm1-router.md §8). `VoiceSession.attachDecision` wired into
// the classic hold: off by default, zero provider calls; on, N1 acts (or
// asks) through the SAME doors the model would have used, and the strong
// model never sees the turn. `COMPANION_DECISION=1` is the only switch
// before DM1c-3's Settings toggle exists — scoped tightly per test, and
// inert everywhere `attachDecision` never ran (the closure it wires is the
// only thing that reads it).

@Test @MainActor func voiceDecisionTests() async {
    await testDecisionOffNeverAsksTheProviderAndChatGetsTheTurn()
    await testDecisionOnOpensSafariThroughTheRouterWithoutTheChat()
    await testDecisionNoneActionPassesThroughToChat()
    await testDecisionTaskDelegatesToTheJobSubmitterWithoutTheChat()
    await testDecisionTaskWithoutJobsFallsBackToChat()
    await testWithoutAttachDecisionTheClassicPathIsUnchanged()
    await testDecisionConfirmThenYesEmptiesTrashOnce()
    await testDecisionConfirmThenYesThenLaterYesReachesChat()
    await testDecisionConfirmThenNoDeclinesWithoutActing()
    await testDecisionConfirmThenUnclearUtteranceRoutesNormally()
    await testDecisionOffNeverStartsAConfirmationEither()
    await testCerebrasBrainSkipsDecisionGateEvenWithTheToggleOn()
}

/// Row 12 (wave-15c §4): the toggle stays on, but with the hold's brain
/// already Cerebras (15c-7, the only fast brain since 15e-3),
/// `DecisionGate` is never called at all — the brain already picked the
/// tool by the time N1 would have started.
@MainActor func testCerebrasBrainSkipsDecisionGateEvenWithTheToggleOn() async {
    await expectFastBrainSkipsDecisionGate(key: .cerebras, value: "csk-test")
}

@MainActor func expectFastBrainSkipsDecisionGate(key: SecretKey, value: String) async {
    setenv("COMPANION_DECISION", "1", 1)
    defer { unsetenv("COMPANION_DECISION") }
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("companion-fastbrain-\(UUID().uuidString).log")
    await Log.capturing(to: url) {
        let counter = CallCounter()
        let gate = DecisionGate(
            provider: ScriptedDecision { _ in counter.increment(); return nil },
            arbiter: NoArbiter(),
            tools: ParentToolRunner(workspace: FakeWorkspaceOpener()),
            world: { DecisionWorld() },
            budget: .seconds(2))
        let h = makeVoiceHarness(key: nil)
        h.secrets.values[key] = value
        await h.session.attachDecision(gate)
        h.transcriber.stoppedText = "abre Safari"
        h.chat.rounds = [[.text("Listo.")]]
        await h.session.hold()
        await pumpUntil("fastBrain: listening") { h.watch.latest.state == .listening }
        await h.session.release()
        await pumpUntil("fastBrain: chat") { !h.chat.histories.isEmpty }
        await h.session.awaitClassicTurn()
        expectEq(counter.count, 0, "fastBrain: N1 nunca corre")
        expect(h.thread.turns.contains { $0.role == .assistant && $0.content.contains("Listo.") },
               "fastBrain: el turno igual contesta")
        let logged = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        expect(logged.contains("decision: pass reason=fastBrain"), "fastBrain: el log lo dice")
    }
}

@MainActor func testDecisionOffNeverAsksTheProviderAndChatGetsTheTurn() async {
    unsetenv("COMPANION_DECISION")
    let counter = CallCounter()
    let gate = DecisionGate(
        provider: ScriptedDecision { _ in counter.increment(); return nil },
        arbiter: NoArbiter(),
        tools: ParentToolRunner(workspace: FakeWorkspaceOpener()),
        world: { DecisionWorld() },
        budget: .seconds(2))
    let h = makeVoiceHarness()
    await h.session.attachDecision(gate)
    h.transcriber.stoppedText = "abre Safari"
    h.chat.rounds = [[.text("Listo.")]]
    await h.session.hold()
    await pumpUntil("decision off: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("decision off: chat") { !h.chat.histories.isEmpty }
    // 15b-10: `classic.submit` runs detached — wait for the turn itself,
    // not just its first side effect, before reading the thread.
    await h.session.awaitClassicTurn()
    expectEq(counter.count, 0, "decision off: el proveedor nunca corre")
    expect(h.thread.turns.contains { $0.role == .assistant && $0.content.contains("Listo.") },
           "decision off: el camino de hoy responde igual")
}

@MainActor func testDecisionOnOpensSafariThroughTheRouterWithoutTheChat() async {
    setenv("COMPANION_DECISION", "1", 1)
    defer { unsetenv("COMPANION_DECISION") }
    let opener = FakeWorkspaceOpener(installed: ["Safari"])
    let tools = ParentToolRunner(workspace: opener)
    let provider = ScriptedDecision { question in
        switch question.id {
        case DecisionHead.action: return peaked("open_app", question.offeredIds)
        case DecisionHead.app: return peaked("Safari", question.offeredIds)
        default: return nil
        }
    }
    let gate = DecisionGate(
        provider: provider, arbiter: NoArbiter(), tools: tools,
        world: { DecisionWorld(apps: ["Safari"], sites: []) },
        budget: .seconds(2))
    let h = makeVoiceHarness()
    let seen = SessionEventBox(h.session.events)
    await h.session.attachDecision(gate)
    h.transcriber.stoppedText = "abre Safari"
    await h.session.hold()
    await pumpUntil("decision on: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("decision on: opened") { opener.openedApps == ["Safari"] }
    expect(h.chat.histories.isEmpty, "decision on: el modelo fuerte nunca ve el turno")
    // 15b-3: sin caché el sintetizador dice el acuse corto; el hilo sigue
    // llevando la respuesta completa.
    await pumpUntil("decision on: synth habla") { h.synth.queue.contains("Done.") }
    expect(h.thread.turns.contains { $0.role == .assistant && $0.content == "Opened Safari." },
           "decision on: el hilo lleva la respuesta completa")
    expect(
        !seen.events.contains { if case .job(.approvalRequested, _) = $0 { true } else { false } },
        "decision on: sin hoja")
    await pumpUntil("decision on: parentActing") {
        seen.events.contains { if case .parentActing = $0 { true } else { false } }
    }
    expect(seen.events.contains { $0 == .parentActed }, "decision on: y parentActed")
    expect(await h.session.timeline.committed != nil, "decision on: el commit quedó marcado")
    expect(await h.session.timeline.decision != nil, "decision on: N1 marcó su instante")
}

@MainActor func testDecisionNoneActionPassesThroughToChat() async {
    setenv("COMPANION_DECISION", "1", 1)
    defer { unsetenv("COMPANION_DECISION") }
    let provider = ScriptedDecision { question in
        question.id == DecisionHead.action ? peaked("none", question.offeredIds) : nil
    }
    let gate = DecisionGate(
        provider: provider, arbiter: NoArbiter(),
        tools: ParentToolRunner(workspace: FakeWorkspaceOpener()),
        world: { DecisionWorld() }, budget: .seconds(2))
    let h = makeVoiceHarness()
    await h.session.attachDecision(gate)
    h.transcriber.stoppedText = "hola"
    h.chat.rounds = [[.text("Hola.")]]
    await h.session.hold()
    await pumpUntil("none: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("none: chat") { !h.chat.histories.isEmpty }
    await h.session.awaitClassicTurn()
    expect(h.thread.turns.contains { $0.role == .assistant && $0.content.contains("Hola.") },
           "none: el modelo fuerte contesta")
}

@MainActor func testDecisionTaskDelegatesToTheJobSubmitterWithoutTheChat() async {
    setenv("COMPANION_DECISION", "1", 1)
    defer { unsetenv("COMPANION_DECISION") }
    let provider = taskProvider()
    let gate = DecisionGate(
        provider: provider, arbiter: NoArbiter(),
        tools: ParentToolRunner(workspace: FakeWorkspaceOpener()),
        world: { DecisionWorld() }, budget: .seconds(2))
    let jobs = CapturingSubmitter()
    let h = makeVoiceHarness(jobs: jobs)
    await h.session.attachDecision(gate)
    h.transcriber.stoppedText = "crea un archivo"
    await h.session.hold()
    await pumpUntil("task: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("task: el submitter vio el encargo") { jobs.goals == ["crea un archivo"] }
    // HIGH-B (code review 2026-09-25): the job's end may ask the model for a
    // summary of the RESULT; the user's own turn still never reaches it.
    expect(!h.chat.histories.joined().contains { $0.content.contains("crea un archivo") },
           "task: el modelo fuerte nunca ve el turno")
}

@MainActor func testDecisionTaskWithoutJobsFallsBackToChat() async {
    setenv("COMPANION_DECISION", "1", 1)
    defer { unsetenv("COMPANION_DECISION") }
    let provider = taskProvider()
    let gate = DecisionGate(
        provider: provider, arbiter: NoArbiter(),
        tools: ParentToolRunner(workspace: FakeWorkspaceOpener()),
        world: { DecisionWorld() }, budget: .seconds(2))
    let h = makeVoiceHarness()
    await h.session.attachDecision(gate)
    h.transcriber.stoppedText = "crea un archivo"
    h.chat.rounds = [[.text("Hecho.")]]
    await h.session.hold()
    await pumpUntil("task sin jobs: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("task sin jobs: chat") { !h.chat.histories.isEmpty }
    await h.session.awaitClassicTurn()
    expect(h.thread.turns.contains { $0.role == .assistant && $0.content.contains("Hecho.") },
           "task sin jobs: sin especialista, contesta el modelo")
}

@MainActor func testWithoutAttachDecisionTheClassicPathIsUnchanged() async {
    setenv("COMPANION_DECISION", "1", 1)
    defer { unsetenv("COMPANION_DECISION") }
    let h = makeVoiceHarness()
    h.transcriber.stoppedText = "abre Safari"
    h.chat.rounds = [[.text("Listo.")]]
    await h.session.hold()
    await pumpUntil("sin attach: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("sin attach: chat") { !h.chat.histories.isEmpty }
    await h.session.awaitClassicTurn()
    expect(h.thread.turns.contains { $0.role == .assistant && $0.content.contains("Listo.") },
           "sin attach: nadie interceptó el turno — decide es nil")
}

// DM1c-4 (wave-dm1-router.md §8): irreversible plans confirm by voice — the
// gate stores the question, nothing runs while it is open, and the classic
// hold's NEXT turn answers it before N1 ever sees the words.

@MainActor func testDecisionConfirmThenYesEmptiesTrashOnce() async {
    setenv("COMPANION_DECISION", "1", 1)
    defer { unsetenv("COMPANION_DECISION") }
    let system = RecordingSystemActing()
    let gate = DecisionGate(
        provider: trashProvider(), arbiter: NoArbiter(),
        tools: ParentToolRunner(workspace: FakeWorkspaceOpener()),
        system: system, world: { DecisionWorld() }, budget: .seconds(2))
    let h = makeVoiceHarness(language: .es)
    let seen = SessionEventBox(h.session.events)
    await h.session.attachDecision(gate)

    h.transcriber.stoppedText = "vacia la papelera"
    await h.session.hold()
    await pumpUntil("confirm: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("confirm: pregunta") { h.synth.queue.contains("¿Vacío la papelera?") }
    expectEq(system.actCount, 0, "confirm: nada corre mientras se pregunta")
    expect(
        !seen.events.contains { if case .job(.approvalRequested, _) = $0 { true } else { false } },
        "confirm: sin hoja")

    h.transcriber.stoppedText = "si"
    await h.session.hold()
    await pumpUntil("si: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("si: la papelera se vacio") { system.actCount == 1 }
    // 15b-3: acuse corto en español; el hilo lleva el resultado completo.
    await pumpUntil("si: se habla el resultado") { h.synth.queue.contains("Listo.") }
    expect(h.thread.turns.contains { $0.role == .assistant && $0.content == "Hecho: system." },
           "si: el hilo lleva el resultado completo")
}

/// wave-dm1-router.md §8: a confirmation is answered by the very NEXT turn
/// only. Once the confirmed "sí" has run, pending clears — a later, unrelated
/// "sí" must reach chat/N1 like any other turn, never replay the cached
/// outcome.
@MainActor func testDecisionConfirmThenYesThenLaterYesReachesChat() async {
    setenv("COMPANION_DECISION", "1", 1)
    defer { unsetenv("COMPANION_DECISION") }
    let system = RecordingSystemActing()
    // Only answers about the trash order; any other utterance (a bare
    // "si" once the question is gone) gets no vote and falls through.
    let provider = ScriptedDecision { question in
        guard question.instructions.localizedCaseInsensitiveContains("papelera") else { return nil }
        switch question.id {
        case DecisionHead.action: return peaked("system", question.offeredIds)
        case DecisionHead.system: return peaked("empty_trash", question.offeredIds)
        default: return nil
        }
    }
    let gate = DecisionGate(
        provider: provider, arbiter: NoArbiter(),
        tools: ParentToolRunner(workspace: FakeWorkspaceOpener()),
        system: system, world: { DecisionWorld() }, budget: .seconds(2))
    let h = makeVoiceHarness(language: .es)
    await h.session.attachDecision(gate)

    h.transcriber.stoppedText = "vacia la papelera"
    await h.session.hold()
    await pumpUntil("later si: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("later si: pregunta") { h.synth.queue.contains("¿Vacío la papelera?") }

    h.transcriber.stoppedText = "si"
    await h.session.hold()
    await pumpUntil("later si: listening 2") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("later si: la papelera se vacio") { system.actCount == 1 }

    h.transcriber.stoppedText = "si"
    h.chat.rounds = [[.text("Hola.")]]
    await h.session.hold()
    await pumpUntil("later si: listening 3") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("later si: chat") { !h.chat.histories.isEmpty }
    await h.session.awaitClassicTurn()
    expectEq(system.actCount, 1, "later si: la papelera no se vuelve a vaciar")
    expect(h.thread.turns.contains { $0.role == .assistant && $0.content.contains("Hola.") },
           "later si: un si sin pregunta abierta llega al modelo fuerte")
}

@MainActor func testDecisionConfirmThenNoDeclinesWithoutActing() async {
    setenv("COMPANION_DECISION", "1", 1)
    defer { unsetenv("COMPANION_DECISION") }
    let system = RecordingSystemActing()
    let gate = DecisionGate(
        provider: trashProvider(), arbiter: NoArbiter(),
        tools: ParentToolRunner(workspace: FakeWorkspaceOpener()),
        system: system, world: { DecisionWorld() }, budget: .seconds(2))
    let h = makeVoiceHarness()
    await h.session.attachDecision(gate)

    h.transcriber.stoppedText = "vacia la papelera"
    await h.session.hold()
    await pumpUntil("no: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("no: pregunta") { h.synth.queue.contains("Empty the trash?") }

    h.transcriber.stoppedText = "no"
    await h.session.hold()
    await pumpUntil("no: listening 2") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("no: declinado") { h.synth.queue.contains("Okay, not doing it.") }
    expectEq(system.actCount, 0, "no: nunca se ejecuta")
}

@MainActor func testDecisionConfirmThenUnclearUtteranceRoutesNormally() async {
    setenv("COMPANION_DECISION", "1", 1)
    defer { unsetenv("COMPANION_DECISION") }
    let system = RecordingSystemActing()
    let opener = FakeWorkspaceOpener(installed: ["Safari"])
    let provider = ScriptedDecision { question in
        let asksAboutTrash = question.instructions.localizedCaseInsensitiveContains("papelera")
        switch question.id {
        case DecisionHead.action:
            return peaked(asksAboutTrash ? "system" : "open_app", question.offeredIds)
        case DecisionHead.system:
            return peaked("empty_trash", question.offeredIds)
        case DecisionHead.app:
            return peaked("Safari", question.offeredIds)
        default: return nil
        }
    }
    let gate = DecisionGate(
        provider: provider, arbiter: NoArbiter(), tools: ParentToolRunner(workspace: opener),
        system: system, world: { DecisionWorld(apps: ["Safari"], sites: []) }, budget: .seconds(2))
    let h = makeVoiceHarness()
    await h.session.attachDecision(gate)

    h.transcriber.stoppedText = "vacia la papelera"
    await h.session.hold()
    await pumpUntil("unclear: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("unclear: pregunta") { h.synth.queue.contains("Empty the trash?") }

    h.transcriber.stoppedText = "abre Safari"
    await h.session.hold()
    await pumpUntil("unclear: listening 2") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("unclear: safari se abrio") { opener.openedApps == ["Safari"] }
    expectEq(system.actCount, 0, "unclear: la papelera nunca se vacio")
}

@MainActor func testDecisionOffNeverStartsAConfirmationEither() async {
    unsetenv("COMPANION_DECISION")
    let system = RecordingSystemActing()
    let gate = DecisionGate(
        provider: trashProvider(), arbiter: NoArbiter(),
        tools: ParentToolRunner(workspace: FakeWorkspaceOpener()),
        system: system, world: { DecisionWorld() }, budget: .seconds(2))
    let h = makeVoiceHarness()
    await h.session.attachDecision(gate)
    h.transcriber.stoppedText = "vacia la papelera"
    h.chat.rounds = [[.text("No puedo hacer eso.")]]
    await h.session.hold()
    await pumpUntil("toggle off: listening") { h.watch.latest.state == .listening }
    await h.session.release()
    await pumpUntil("toggle off: chat") { !h.chat.histories.isEmpty }
    await h.session.awaitClassicTurn()
    expectEq(system.actCount, 0, "toggle off: el ejecutor de sistema nunca corre")
    expect(
        h.thread.turns.contains { $0.role == .assistant && $0.content.contains("No puedo hacer eso.") },
        "toggle off: el modelo fuerte responde igual")
}

// MARK: - DecisionGate.answerConfirmation (pure gate, no voice harness)

@Test func dm1c4ConfirmThenNoDeclinesWithoutActing() async {
    let system = RecordingSystemActing()
    let gate = DecisionGate(
        provider: trashProvider(), arbiter: NoArbiter(),
        tools: ParentToolRunner(workspace: FakeWorkspaceOpener()),
        system: system, world: { DecisionWorld() }, budget: .seconds(2))
    let step = await gate.plan("vacia la papelera", canDelegate: false)
    let outcome = await gate.run(step, utterance: "vacia la papelera", language: .es)
    expectEq(outcome, .confirm("¿Vacío la papelera?"), "la pregunta se arma antes de tocar nada")
    expectEq(system.actCount, 0, "nada corre mientras se pregunta")

    let answer = await gate.answerConfirmation("no")
    expectEq(answer, .declined, "un no declina")
    expectEq(system.actCount, 0, "declinar no ejecuta nada")
}

@Test func dm1c4UnclearAnswerClearsPendingAndFallsThrough() async {
    let system = RecordingSystemActing()
    let gate = DecisionGate(
        provider: trashProvider(), arbiter: NoArbiter(),
        tools: ParentToolRunner(workspace: FakeWorkspaceOpener()),
        system: system, world: { DecisionWorld() }, budget: .seconds(2))
    _ = await gate.run(
        await gate.plan("vacia la papelera", canDelegate: false),
        utterance: "vacia la papelera", language: .es)

    let answer = await gate.answerConfirmation("que hora es")
    expect(answer == nil, "una orden nueva no es una respuesta a la pregunta")

    let second = await gate.answerConfirmation("si")
    expect(second == nil, "el pending ya se limpio; un si suelto no tiene a que responder")
    expectEq(system.actCount, 0, "nunca se ejecuto")
}

@Test func dm1c4ReplayingYesTwiceRunsOnlyOnce() async {
    let system = RecordingSystemActing()
    let gate = DecisionGate(
        provider: trashProvider(), arbiter: NoArbiter(),
        tools: ParentToolRunner(workspace: FakeWorkspaceOpener()),
        system: system, world: { DecisionWorld() }, budget: .seconds(2))
    _ = await gate.run(
        await gate.plan("vacia la papelera", canDelegate: false),
        utterance: "vacia la papelera", language: .en)

    let first = await gate.answerConfirmation("si")
    expect(first != nil, "the first si answers the open question")
    expectEq(system.actCount, 1, "the mutation ran exactly once")

    // wave-dm1-router.md §8: a confirmation is answered by the very next
    // turn only — pending clears right after the confirmed run, so a later
    // "si" is an unrelated turn, not a replay of the stale outcome.
    let second = await gate.answerConfirmation("si")
    expect(second == nil, "nothing is pending anymore; the second si is a normal turn")
    expectEq(system.actCount, 1, "the second si never re-runs the mutation")
}

@Test func dm1c4ConfirmationExpiresAfterSixtySeconds() async {
    let system = RecordingSystemActing()
    let clock = MutableClock(Date())
    let gate = DecisionGate(
        provider: trashProvider(), arbiter: NoArbiter(),
        tools: ParentToolRunner(workspace: FakeWorkspaceOpener()),
        system: system, world: { DecisionWorld() }, budget: .seconds(2),
        now: { clock.now })
    _ = await gate.run(
        await gate.plan("vacia la papelera", canDelegate: false),
        utterance: "vacia la papelera", language: .en)

    clock.now = clock.now.addingTimeInterval(61)
    let answer = await gate.answerConfirmation("si")
    expect(answer == nil, "la confirmacion vencida no cuenta como respuesta")
    expectEq(system.actCount, 0, "nada corrio despues de vencer")
}

// MARK: - SystemActionRunner (the DM1c-4 executor)

@Test func dm1c4SystemActionRunnerSupportsOnlyEmptyTrashAndQuitApp() {
    let runner = SystemActionRunner(
        selfBundleID: "com.karen.companion", frontmostOtherPID: { 4242 })
    expect(
        runner.supports(closedSetPlan(action: .system, key: "op", value: "empty_trash")),
        "empty_trash esta soportado")
    expect(
        runner.supports(closedSetPlan(action: .shortcut, key: "shortcut", value: "quit_app")),
        "quit_app esta soportado")
    expect(
        !runner.supports(closedSetPlan(action: .volume, key: "op", value: "up")),
        "volume no tiene ejecutor aqui (DM1d)")
    expect(
        !runner.supports(closedSetPlan(action: .system, key: "op", value: "nuclear")),
        "un op fuera del conjunto cerrado nunca se soporta")
}

@Test func dm1c4QuitAppNeverTargetsCompanionsOwnPid() async {
    let app = FakeTerminatingApp(bundleIdentifier: "com.other.app")
    let runner = SystemActionRunner(
        selfBundleID: "com.karen.companion", selfPID: 111,
        frontmostOtherPID: { 111 },  // somehow the sensor reported our own pid
        runningApplication: { _ in app })
    let ok = await runner.act(closedSetPlan(action: .shortcut, key: "shortcut", value: "quit_app"))
    expect(!ok, "el pid propio nunca se termina")
    expectEq(app.terminateCount, 0, "terminate() jamas se llamo")
}

@Test func dm1c4QuitAppNeverTargetsCompanionsOwnBundle() async {
    let app = FakeTerminatingApp(bundleIdentifier: "com.karen.companion")
    let runner = SystemActionRunner(
        selfBundleID: "com.karen.companion", selfPID: 111,
        frontmostOtherPID: { 222 },  // a different pid, but somehow the same bundle
        runningApplication: { _ in app })
    let ok = await runner.act(closedSetPlan(action: .shortcut, key: "shortcut", value: "quit_app"))
    expect(!ok, "el bundle id propio nunca se termina")
    expectEq(app.terminateCount, 0, "terminate() jamas se llamo")
}

@Test func dm1c4QuitAppTargetsTheFrontmostOtherApp() async {
    let app = FakeTerminatingApp(bundleIdentifier: "com.other.app")
    let runner = SystemActionRunner(
        selfBundleID: "com.karen.companion", selfPID: 111,
        frontmostOtherPID: { 4242 },
        runningApplication: { pid in pid == 4242 ? app : nil })
    let ok = await runner.act(closedSetPlan(action: .shortcut, key: "shortcut", value: "quit_app"))
    expect(ok, "termina la app que estaba al frente")
    expectEq(app.terminateCount, 1, "terminate() se llamo una vez")
}

// MARK: - fakes and helpers

private func taskProvider() -> ScriptedDecision {
    ScriptedDecision { question in
        switch question.id {
        case DecisionHead.action: return peaked("task", question.offeredIds)
        case DecisionHead.goal: return peaked("c0", question.offeredIds)
        default: return nil
        }
    }
}

private struct NoArbiter: Arbitrating {
    func arbitrate(
        utterance: String, shortlist: ArbitrationShortlist
    ) async -> (entry: ShortlistEntry, confidence: Double)? { nil }
}

final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int { lock.withLock { _count } }
    func increment() { lock.withLock { _count += 1 } }
}

/// A local copy of `PlanTests.peaked` / `DecisionGateTests.peakedDecision`:
/// same shape, both file-private to their own files.
private func peaked(_ choice: String, _ ids: [String]) -> DecisionAnswer? {
    guard !ids.isEmpty, Set(ids).contains(choice) else { return nil }
    var distribution: [String: Double] = [:]
    if ids.count == 1 {
        distribution[choice] = 1
    } else {
        let share = 0.01 / Double(ids.count - 1)
        var rest = 0.0
        for id in ids where id != choice {
            distribution[id] = share
            rest += share
        }
        distribution[choice] = 1 - rest
    }
    return DecisionAnswer(
        choice: choice, distribution: distribution,
        confidence: DecisionMath.sharpness(distribution)
    ).validated(against: ids)
}

/// DM1c-4 fakes and helpers.

private func trashProvider() -> ScriptedDecision {
    ScriptedDecision { question in
        switch question.id {
        case DecisionHead.action: return peaked("system", question.offeredIds)
        case DecisionHead.system: return peaked("empty_trash", question.offeredIds)
        default: return nil
        }
    }
}

private func closedSetPlan(action: DecisionAction, key: String, value: String) -> Plan {
    Plan(
        utterance: "orden", action: action, args: [key: .text(value)],
        confidence: 0.9, risk: .irreversible, disposition: .confirm)
}

final class RecordingSystemActing: SystemActing, @unchecked Sendable {
    private let lock = NSLock()
    private var _actCount = 0
    var supportsAnswer = true
    var actResult = true
    var actCount: Int { lock.withLock { _actCount } }

    func supports(_ plan: Plan) -> Bool { supportsAnswer }
    func act(_ plan: Plan) async -> Bool {
        lock.withLock { _actCount += 1 }
        return actResult
    }
}

/// Injected for `DecisionGate`'s `now:` seam — advanced by hand instead of
/// sleeping the test 60 real seconds.
final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ start: Date) { value = start }
    var now: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

private final class FakeTerminatingApp: AppTerminating, @unchecked Sendable {
    let bundleIdentifier: String?
    private let lock = NSLock()
    private var _terminateCount = 0
    var terminateCount: Int { lock.withLock { _terminateCount } }

    init(bundleIdentifier: String?) { self.bundleIdentifier = bundleIdentifier }

    func terminate() -> Bool {
        lock.withLock { _terminateCount += 1 }
        return true
    }
}
