import CompanionCore
import CompanionCoreTestSupport
import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// DM1c-1 (wave-dm1-router.md §8). Pure routing first: `DecisionRoute.step`
// decides without touching anything. Then the gate: `DecisionGate.plan`
// races N1 (and N2 once) against a budget with no side effects, and
// `DecisionGate.run` acts ONLY through the doors the model already uses —
// `ParentToolRunner` and the `open_url` said-it gate — never around them.

// MARK: - DecisionRoute (pure)

@Test func dm1cIgnoreAndInformationalPassThrough() {
    let world = DecisionWorld()
    let ignored = makePlan(action: .none, disposition: .ignore)
    expectEq(
        DecisionRoute.step(for: ignored, world: world, canDelegate: true, systemSupports: { _ in false }),
        .passThrough(.ignored), "ignore pasa de largo")

    for action in [DecisionAction.listApps, .readSkill, .findPlaces] {
        let informational = makePlan(action: action, disposition: .act)
        expectEq(
            DecisionRoute.step(for: informational, world: world, canDelegate: true, systemSupports: { _ in false }),
            .passThrough(.informational), "\(action.rawValue) todavia necesita que el modelo hable")
    }
}

@Test func dm1cOpenAppRoutesToExecuteWithTheParentToolWireShape() {
    let world = DecisionWorld()
    let openApp = makePlan(action: .openApp, args: ["app": .text("Safari")], disposition: .act)
    let step = DecisionRoute.step(for: openApp, world: world, canDelegate: true, systemSupports: { _ in false })
    guard case .execute(let call, let routed) = step else {
        Issue.record("esperaba execute, fue \(step)")
        return
    }
    expectEq(call.name, ParentTool.openApp.rawValue, "el nombre del tool es el real, no el de Plan")
    expectEq(ToolArguments.parse(call.arguments)?["name"] as? String, "Safari", "la llave del wire es name")
    expectEq(routed, openApp, "el plan viaja intacto hasta el ejecutor")
}

@Test func dm1cClosedSetActsGoToSystemOnlyWhenSupported() {
    let world = DecisionWorld()
    let volume = makePlan(action: .volume, args: ["op": .text("up")], disposition: .act)
    expectEq(
        DecisionRoute.step(for: volume, world: world, canDelegate: true, systemSupports: { _ in false }),
        .passThrough(.noExecutor), "sin ejecutor todavia (DM1c-1)")
    expectEq(
        DecisionRoute.step(for: volume, world: world, canDelegate: true, systemSupports: { _ in true }),
        .system(volume), "con ejecutor, va directo a system")
}

@Test func dm1cConfirmOnlyWhenSystemSupportsIt() {
    let world = DecisionWorld()
    let trash = makePlan(
        action: .system, args: ["op": .text("empty_trash")], risk: .irreversible, disposition: .confirm)
    expectEq(
        DecisionRoute.step(for: trash, world: world, canDelegate: true, systemSupports: { _ in false }),
        .passThrough(.noExecutor), "nunca se pregunta por algo que nada puede ejecutar")
    expectEq(
        DecisionRoute.step(for: trash, world: world, canDelegate: true, systemSupports: { _ in true }),
        .confirm(trash), "con ejecutor, confirma por voz")
}

@Test func dm1cDelegateNeedsCanDelegateAndAGoal() {
    let world = DecisionWorld()
    let task = makePlan(action: .task, args: ["goal": .text("write a report")], disposition: .delegate)
    expectEq(
        DecisionRoute.step(for: task, world: world, canDelegate: false, systemSupports: { _ in false }),
        .passThrough(.noSpecialist), "sin especialista disponible, no delega")
    expectEq(
        DecisionRoute.step(for: task, world: world, canDelegate: true, systemSupports: { _ in false }),
        .delegate(Handoff(goal: "write a report", context: "")), "delega con el goal del plan")

    let noGoal = makePlan(action: .task, disposition: .delegate)
    expectEq(
        DecisionRoute.step(for: noGoal, world: world, canDelegate: true, systemSupports: { _ in false }),
        .passThrough(.failed), "sin goal no hay a que delegar")
}

@Test func dm1cArbitrateBuildsTheShortlistOrGivesUp() {
    let world = DecisionWorld(apps: ["Safari"], sites: [])
    let arbitrating = makePlan(
        action: .none, disposition: .arbitrate, actionMass: ["open_app": 0.6, "volume": 0.4])
    let step = DecisionRoute.step(for: arbitrating, world: world, canDelegate: true, systemSupports: { _ in false })
    guard case .arbitrate(let shortlist, let routed) = step else {
        Issue.record("esperaba arbitrate, fue \(step)")
        return
    }
    expect(shortlist.accepts("open_app:Safari"), "safari entra en la shortlist")
    expectEq(routed, arbitrating, "el plan original viaja con la shortlist")

    let empty = makePlan(action: .none, disposition: .arbitrate)
    expectEq(
        DecisionRoute.step(for: empty, world: world, canDelegate: true, systemSupports: { _ in false }),
        .passThrough(.unresolved), "sin masa no hay shortlist que ofrecer")
}

@Test func dm1cParentCallUsesTheRealWireKeysAndRefusesAMissingArg() {
    let openApp = makePlan(action: .openApp, args: ["app": .text("Safari")], disposition: .act)
    let appCall = DecisionRoute.parentCall(for: openApp)
    expectEq(appCall?.name, "open_app", "nombre real del tool")
    expectEq(ToolArguments.parse(appCall?.arguments ?? "")?["name"] as? String, "Safari", "llave name, no app")

    let openURL = makePlan(action: .openURL, args: ["url": .text("https://github.com")], disposition: .act)
    let urlCall = DecisionRoute.parentCall(for: openURL)
    expectEq(ToolArguments.parse(urlCall?.arguments ?? "")?["url"] as? String, "https://github.com", "llave url")

    let openFile = makePlan(action: .openFile, args: ["path": .text("~/Desktop/a.txt")], disposition: .act)
    let fileCall = DecisionRoute.parentCall(for: openFile)
    expectEq(ToolArguments.parse(fileCall?.arguments ?? "")?["path"] as? String, "~/Desktop/a.txt", "llave path")

    let missing = makePlan(action: .openApp, disposition: .act)
    expect(DecisionRoute.parentCall(for: missing) == nil, "sin argumento no hay llamada")

    let notParent = makePlan(action: .volume, args: ["op": .text("up")], disposition: .act)
    expect(DecisionRoute.parentCall(for: notParent) == nil, "volume no es un parent tool")
}

@Test func dm1cValidClosedSetRejectsAForgedIdOrSpan() {
    let realOp = makePlan(action: .volume, args: ["op": .text("up")], disposition: .act)
    expect(DecisionRoute.validClosedSet(realOp), "up esta en CandidateSets.volumeOps")
    let fakeOp = makePlan(action: .volume, args: ["op": .text("nuclear")], disposition: .act)
    expect(!DecisionRoute.validClosedSet(fakeOp), "nuclear no esta ofrecido en ningun lado")

    let realShortcut = makePlan(action: .shortcut, args: ["shortcut": .text("undo")], disposition: .act)
    expect(DecisionRoute.validClosedSet(realShortcut), "undo esta en CandidateSets.shortcuts")
    let fakeShortcut = makePlan(action: .shortcut, args: ["shortcut": .text("format_disk")], disposition: .act)
    expect(!DecisionRoute.validClosedSet(fakeShortcut), "format_disk no es un atajo ofrecido")

    let realType = makePlan(
        utterance: "escribe hola mundo", action: .typeText,
        args: ["text": .text("hola mundo"), "submit": .flag(false)], disposition: .act)
    expect(DecisionRoute.validClosedSet(realType), "el span esta literalmente en lo dicho")
    let fakeType = makePlan(
        utterance: "escribe hola mundo", action: .typeText,
        args: ["text": .text("borra todo"), "submit": .flag(false)], disposition: .act)
    expect(!DecisionRoute.validClosedSet(fakeType), "el span inventado no esta en lo dicho")

    let openApp = makePlan(action: .openApp, args: ["app": .text("Safari")], disposition: .act)
    expect(DecisionRoute.validClosedSet(openApp), "lo que no es closed-set pasa de largo")
}

@Test func dm1cSpokenConfirmationReadsYesNoAndBacksOffOnAnythingElse() {
    for said in ["si", "sí, vaciala", "dale", "yes", "hazlo", "Sí"] {
        expectEq(SpokenConfirmation.reading(said), true, "«\(said)» es un si")
    }
    for said in ["no", "mejor no", "no, espera", "cancela"] {
        expectEq(SpokenConfirmation.reading(said), false, "«\(said)» es un no")
    }
    expect(SpokenConfirmation.reading("") == nil, "vacio no es una respuesta")
    expect(SpokenConfirmation.reading("abre Safari") == nil, "una orden nueva no es un si ni un no")
    expect(SpokenConfirmation.reading("sí pero no") == nil, "mixto no se decide solo")
}

@Test func dm1cDecisionCopyIsBilingualAndReusesParentToolCopy() {
    let trash = makePlan(
        action: .system, args: ["op": .text("empty_trash")], risk: .irreversible, disposition: .confirm)
    expectEq(DecisionCopy.question(for: trash, .en), "Empty the trash?", "pregunta en ingles")
    expectEq(DecisionCopy.question(for: trash, .es), "¿Vacío la papelera?", "pregunta en espanol")
    expectEq(DecisionCopy.declined(.en), "Okay, not doing it.", "declinado en ingles")
    expectEq(DecisionCopy.declined(.es), "Bien, no lo hago.", "declinado en espanol")
    expectEq(DecisionCopy.delegated(.en), "Passing this to the specialist…", "delegado en ingles")

    let outcome = ParentToolOutcome(ok: true, output: "opened Safari", target: "Safari")
    expectEq(DecisionCopy.acted(outcome, tool: "open_app", .en), "Opened Safari.",
             "acted reutiliza la misma copia que el modelo-en-el-loop")
}

// MARK: - DecisionGate (async, no side effects until `run`)

@Test func dm1cGatePlansSafariThenRunExecutesThroughTheRealRunner() async {
    let workspace = FakeWorkspaceOpener(installed: ["Safari"])
    let tools = ParentToolRunner(workspace: workspace)
    let gate = DecisionGate(
        provider: perfectOpenApp("Safari"),
        arbiter: FakeArbiter(result: nil),
        tools: tools,
        world: { DecisionWorld(apps: ["Safari"], sites: []) },
        budget: .seconds(2))

    let step = await gate.plan("abre Safari", canDelegate: false)
    guard case .execute(let call, _) = step else {
        Issue.record("esperaba execute, fue \(step)")
        return
    }
    expect(workspace.openedApps.isEmpty, "plan() no tiene efectos secundarios")

    let outcome = await gate.run(step, utterance: "abre Safari", language: .en)
    expectEq(
        outcome,
        .acted(ParentToolOutcome(ok: true, output: "opened Safari", target: "Safari"), call),
        "abre Safari por el runner real")
    expectEq(workspace.openedApps, ["Safari"], "el workspace de verdad recibio la apertura")
}

@Test func dm1cGateFallsBackWhenTheProviderAnswersNothing() async {
    let gate = DecisionGate(
        provider: ScriptedDecision { _ in nil },
        arbiter: FakeArbiter(result: nil),
        tools: ParentToolRunner(workspace: FakeWorkspaceOpener()),
        world: { DecisionWorld(apps: ["Safari"], sites: []) },
        budget: .seconds(2))
    let step = await gate.plan("abre Safari", canDelegate: false)
    expectEq(step, .passThrough(.unresolved), "sin juicio del proveedor no hay shortlist ni accion")
}

@Test func dm1cGateTimesOutWithinBudgetWhenTheProviderIsSlow() async {
    struct SlowProvider: DecisionProvider {
        func answer(_ question: DecisionQuestion) async -> DecisionAnswer? {
            try? await Task.sleep(for: .seconds(5))
            return nil
        }
    }
    let gate = DecisionGate(
        provider: SlowProvider(),
        arbiter: FakeArbiter(result: nil),
        tools: ParentToolRunner(workspace: FakeWorkspaceOpener()),
        world: { DecisionWorld() },
        budget: .milliseconds(80))
    let start = Date()
    let step = await gate.plan("abre Safari", canDelegate: false)
    let elapsed = Date().timeIntervalSince(start)
    expectEq(step, .passThrough(.timedOut), "el proveedor lento nunca decide a tiempo")
    expect(elapsed < 1, "vuelve en el orden del budget, no del proveedor (\(elapsed)s)")
}

@Test func dm1cForgedAppNameOpensNothing() async {
    let workspace = FakeWorkspaceOpener(installed: ["Safari"])
    let tools = ParentToolRunner(workspace: workspace)
    let gate = DecisionGate(
        provider: ScriptedDecision { _ in nil },
        arbiter: FakeArbiter(result: nil),
        tools: tools,
        world: { DecisionWorld() },
        budget: .seconds(1))
    let forged = makePlan(action: .openApp, args: ["app": .text("../x;rm")], disposition: .act)
    guard let call = DecisionRoute.parentCall(for: forged) else {
        Issue.record("parentCall no deberia rechazar aqui: ParentToolPolicy es quien decide")
        return
    }
    let outcome = await gate.run(.execute(call, forged), utterance: "abre ../x;rm", language: .en)
    guard case .acted(let result, _) = outcome else {
        Issue.record("esperaba acted con ok:false, fue \(outcome)")
        return
    }
    expect(!result.ok, "ParentToolPolicy rechaza el nombre forjado")
    expect(workspace.openedApps.isEmpty, "no se abrio nada")
}

@Test func dm1cOpenURLForAHostNotSaidIsNotExecuted() async {
    let workspace = FakeWorkspaceOpener()
    let gate = DecisionGate(
        provider: ScriptedDecision { _ in nil },
        arbiter: FakeArbiter(result: nil),
        tools: ParentToolRunner(workspace: workspace),
        world: { DecisionWorld() },
        budget: .seconds(1))
    let injected = makePlan(action: .openURL, args: ["url": .text("https://evil.example.com")], disposition: .act)
    guard let call = DecisionRoute.parentCall(for: injected) else {
        Issue.record("parentCall deberia construirse")
        return
    }
    let outcome = await gate.run(.execute(call, injected), utterance: "abre google", language: .en)
    expectEq(outcome, .passThrough(.noExecutor), "el host no fue dicho; el gate se abstiene")
    expect(workspace.openedURLs.isEmpty, "no se abrio nada")
}

@Test func dm1cOpenURLForAHostTheUserSaidExecutes() async {
    let workspace = FakeWorkspaceOpener()
    let gate = DecisionGate(
        provider: ScriptedDecision { _ in nil },
        arbiter: FakeArbiter(result: nil),
        tools: ParentToolRunner(workspace: workspace),
        world: { DecisionWorld() },
        budget: .seconds(1))
    let named = makePlan(action: .openURL, args: ["url": .text("https://www.github.com")], disposition: .act)
    guard let call = DecisionRoute.parentCall(for: named) else {
        Issue.record("parentCall deberia construirse")
        return
    }
    let outcome = await gate.run(.execute(call, named), utterance: "abre github", language: .en)
    guard case .acted(let result, _) = outcome else {
        Issue.record("esperaba acted, fue \(outcome)")
        return
    }
    expect(result.ok, "github si fue dicho")
    expectEq(workspace.openedURLs, [URL(string: "https://www.github.com")!], "se abrio de verdad")
}

@Test func dm1cN2ArbitratesOnceThenConfirmsOnlyWhenSystemSupportsIt() async {
    let world = DecisionWorld(apps: ["Safari"], sites: [])
    let tools = ParentToolRunner(workspace: FakeWorkspaceOpener(installed: ["Safari"]))
    // Any judge that lands on `.arbitrate` will do: N2's own answer is what
    // the fake below controls, independent of the real shortlist's content.
    let directedNone = ScriptedDecision { question in
        question.id == DecisionHead.action ? peakedDecision("none", question.offeredIds) : nil
    }

    let refusing = DecisionGate(
        provider: directedNone, arbiter: FakeArbiter(result: nil), tools: tools,
        world: { world }, budget: .seconds(1))
    expectEq(
        await refusing.plan("abre Safari", canDelegate: false), .passThrough(.failed),
        "un id fuera de la shortlist no produce un paso ejecutable")

    let picking = DecisionGate(
        provider: directedNone,
        arbiter: FakeArbiter(result: (
            entry: ShortlistEntry(id: "open_app:Safari", action: .openApp, args: ["app": .text("Safari")], mass: 0.6),
            confidence: 0.95)),
        tools: tools, world: { world }, budget: .seconds(1))
    let pickedStep = await picking.plan("abre Safari", canDelegate: false)
    guard case .execute(let call, _) = pickedStep else {
        Issue.record("esperaba execute, fue \(pickedStep)")
        return
    }
    expectEq(call.name, "open_app", "N2 tambien abre por el tool real")

    let trashEntry = ShortlistEntry(
        id: "system:empty_trash", action: .system, args: ["op": .text("empty_trash")], mass: 0.6)
    let confirming = FakeArbiter(result: (entry: trashEntry, confidence: 0.99))

    let withoutExecutor = DecisionGate(
        provider: directedNone, arbiter: confirming, tools: tools, world: { world }, budget: .seconds(1))
    expectEq(
        await withoutExecutor.plan("vacia la papelera", canDelegate: false), .passThrough(.noExecutor),
        "0.99 de N2 no salta la falta de ejecutor")

    let withExecutor = DecisionGate(
        provider: directedNone, arbiter: confirming, tools: tools,
        system: FakeSystemActing(supportsAnswer: true, actAnswer: true),
        world: { world }, budget: .seconds(1))
    let confirmStep = await withExecutor.plan("vacia la papelera", canDelegate: false)
    guard case .confirm(let confirmedPlan) = confirmStep else {
        Issue.record("esperaba confirm, fue \(confirmStep)")
        return
    }
    expectEq(confirmedPlan.confidence, 0.99, "el 0.99 de N2 llega intacto al plan")
    let outcome = await withExecutor.run(confirmStep, utterance: "vacia la papelera", language: .es)
    expectEq(outcome, .confirm("¿Vacío la papelera?"), "la pregunta se arma con la copia de Core")
}

// MARK: - fakes and helpers

private struct FakeArbiter: Arbitrating {
    var result: (entry: ShortlistEntry, confidence: Double)?

    func arbitrate(
        utterance: String, shortlist: ArbitrationShortlist
    ) async -> (entry: ShortlistEntry, confidence: Double)? {
        result
    }
}

private struct FakeSystemActing: SystemActing {
    var supportsAnswer: Bool
    var actAnswer: Bool

    func supports(_ plan: Plan) -> Bool { supportsAnswer }
    func act(_ plan: Plan) async -> Bool { actAnswer }
}

private func makePlan(
    utterance: String = "abre Safari", action: DecisionAction, args: [String: PlanValue] = [:],
    confidence: Double = 0.9, risk: PlanRisk = .reversible, disposition: PlanDisposition,
    actionMass: [String: Double] = [:]
) -> Plan {
    Plan(
        utterance: utterance, action: action, args: args, confidence: confidence, risk: risk,
        disposition: disposition, actionMass: actionMass)
}

private func perfectOpenApp(_ app: String) -> ScriptedDecision {
    ScriptedDecision { question in
        switch question.id {
        case DecisionHead.action: return peakedDecision("open_app", question.offeredIds)
        case DecisionHead.app: return peakedDecision(app, question.offeredIds)
        default: return nil
        }
    }
}

/// A local copy of `PlanTests.peaked`: same shape, but that one is file-private.
private func peakedDecision(_ choice: String, _ ids: [String]) -> DecisionAnswer? {
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
