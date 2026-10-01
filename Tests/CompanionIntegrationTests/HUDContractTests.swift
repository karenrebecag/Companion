import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import CompanionCoreTestSupport
import CompanionTestKit
import CompanionUITestSupport
import Foundation
import Testing

// Wave 12d. Los contratos del HUD que las waves 12a-12c dejaron en prosa,
// ahora como tests: cuatro kinds, Stop desde cualquiera, la puerta del
// padre que falla cerrada, el cuerpo de una tool fuera del historial.

@Test @MainActor func hudContractTests() async throws {
    testFourKindsAndNothingElse()
    testStopFromEveryKindIsIdle()
    await testTheGateFailsClosedWithoutAnActor()
    await testToolBodiesStayOutOfTheStore()
    testDeniedByUserIsAContractError()
    try testTheProjectionRuleCoversEveryField()
    try testTheLedgerKeepsEveryGate()
    testTheLedgerOnlyCountsTestsThatRun()
}

/// 2. Un `switch` sin `default`: un quinto kind o una fase nueva no compila
/// este test, y eso es el contrato (relay-hud-spec/00 §3, 05 §4).
@MainActor func testFourKindsAndNothingElse() {
    let kinds: [SessionKind] = [.idle, .hover, .listening, .processing(.pending)]
    var names: [String] = []
    for kind in kinds {
        switch kind {
        case .idle: names.append("idle")
        case .hover: names.append("hover")
        case .listening: names.append("listening")
        case .processing(let phase):
            switch phase {
            case .pending, .thinking, .speaking, .toolExecuting, .subAgentRunning, .completed:
                names.append("processing")
            }
        }
    }
    expectEq(names, ["idle", "hover", "listening", "processing"], "kinds: cuatro")
    let reasons: [InterruptReason] = [.userStopped, .userSteered, .failure(.sessionDropped)]
    for reason in reasons {
        switch reason {
        case .userStopped, .userSteered, .failure: break
        }
    }
}

/// 3. Desde cada kind alcanzable, `.stop` es Idle: sin encargo, sin cola,
/// sin hold, con la razón, y con los efectos que matan a los hijos.
@MainActor func testStopFromEveryKindIsIdle() {
    let request = ApprovalRequest(requestId: "r1", toolName: "run_shell", summary: "ls", inputJSON: "{}")
    let voice = { (state: TurnState) in
        SessionEvent.voice(TurnSnapshot(state: state, pipeline: .realtime))
    }
    let routes: [(String, [SessionEvent])] = [
        ("hover", [.hoverEntered]),
        ("listening", [.pressed]),
        ("pending", [.pressed, .released]),
        ("thinking", [.typedSubmitted]),
        ("speaking", [.typedSubmitted, .typedReplyStreaming]),
        ("toolExecuting", [.parentActing(targets: ["Safari"])]),
        ("voice speaking", [voice(.listening), voice(.speaking)]),
        ("subAgentRunning", [.job(.started(goal: "x"))]),
        ("subAgent + sheet", [.job(.started(goal: "x")), .job(.approvalRequested(request))]),
        ("completed", [.typedSubmitted, .typedReplyFinished]),
    ]
    for (name, route) in routes {
        var m = SessionMachine()
        for event in route { _ = m.handle(event) }
        expect(m.projection.kind != .idle, "stop desde \(name): el camino sale de idle")
        let hadJob = m.projection.job != nil
        let hadQueue = !m.projection.approvalQueue.isEmpty
        let fx = m.handle(.stop)
        expectEq(m.projection.kind, .idle, "stop desde \(name): idle")
        expect(m.projection.job == nil, "stop desde \(name): sin encargo")
        expect(m.projection.approvalQueue.isEmpty, "stop desde \(name): cola vacía")
        expect(!m.projection.holding, "stop desde \(name): sin hold")
        expectEq(m.projection.interruption, .userStopped, "stop desde \(name): la razón")
        expectEq(fx.contains(.cancelJob), hadJob, "stop desde \(name): cancela el hijo si lo había")
        expectEq(fx.contains(.resolveApproval(requestId: "r1", approved: false, remember: false)), hadQueue,
                 "stop desde \(name): deniega la cola si la había")
    }
}

/// 4. Sin actor de permisos, la puerta del padre deniega en Services y en
/// UI, y el modelo lee la misma instrucción (relay-hud-spec/05 §10, G8).
@MainActor func testTheGateFailsClosedWithoutAnActor() async {
    let call = ToolCallRef(id: "c1", name: "open_url", arguments: #"{"url":"https://evil.example/?q=1"}"#)
    let guardless = ParentToolGuard(approvals: nil)
    let outcome = await guardless.check(call, said: "resume esto", language: .en)
    expect(outcome?.ok == false, "cerrada: Services deniega")
    expect(outcome?.output.hasPrefix("denied_by_user:") == true, "cerrada: con el código del contrato")
    expectEq(outcome?.target, "https://evil.example/?q=1", "cerrada: nombra el objetivo")

    let opener = FakeWorkspaceOpener()
    let chat = FakeChatProvider(replies: [
        .success([.toolCalls([call])]), .success([.text("Entendido.")]),
    ])
    let vm = primed(chat: chat, parentTools: ParentToolRunner(workspace: opener))
    vm.draft = "resume esto"
    vm.send()
    await pumpUntil("cerrada: idle") { !vm.busy }
    expect(opener.openedURLs.isEmpty, "cerrada: UI no abre")
    let answer = chat.histories.last?.first { $0.role == .tool }
    expectEq(answer?.content, ContractError.deniedByUser(.en).wire, "cerrada: el modelo lee el contrato")
}

/// 5. `read_skill` devuelve el cuerpo al modelo (memoria del turno) y el
/// historial guardado no lo lleva (relay-hud-spec/05 §10, G7; G3).
@MainActor func testToolBodiesStayOutOfTheStore() async {
    let marker = "SKILL-BODY-MARKER-12d"
    let card = SkillCard(name: "writing-content", description: "Writes.",
                         path: "/x/writing-content/SKILL.md", kind: .skill, origin: .system)
    let reader = FakeSkillReader(cards: [card], bodies: ["writing-content": "# Write\n" + marker])
    let tools = ParentToolRunner(workspace: FakeWorkspaceOpener(), skills: reader)
    let call = ToolCallRef(id: "c1", name: "read_skill", arguments: #"{"name":"writing-content"}"#)
    let chat = FakeChatProvider(replies: [
        .success([.toolCalls([call])]), .success([.text("Leída.")]),
    ])
    let store = MemoryConversationStore()
    let vm = primed(chat: chat, store: store, parentTools: tools)
    vm.draft = "escribe un post"
    vm.send()
    await pumpUntil("cuerpo: idle") { !vm.busy }
    expect(vm.historyForTests().contains { $0.role == .tool && $0.content.contains(marker) },
           "cuerpo: el modelo lo lee en el turno")
    let saved = try? store.load(vm.conversationId)
    expect(saved != nil, "cuerpo: la conversación se guardó")
    expect(saved?.messages.contains { $0.text.contains(marker) } == false,
           "cuerpo: el historial guardado no lo lleva")
    expect(saved?.messages.allSatisfy { ["user", "assistant", "status"].contains($0.role) } == true,
           "cuerpo: solo usuario, asistente y estado en disco")
}

/// 6. La denegación es un `ContractError` con el mismo wire de siempre.
@MainActor func testDeniedByUserIsAContractError() {
    for language in [AppLanguage.en, .es] {
        let error = ContractError.deniedByUser(language)
        expectEq(error.code, "denied_by_user", "contrato: el código")
        expectEq(error.wire, Escalation.deniedByUser(language), "contrato: el wire no cambia")
        expect(!error.message.hasPrefix("denied_by_user"), "contrato: el mensaje no repite el código")
    }
    // Golden strings: `Escalation.deniedByUser` is defined through the
    // contract error, so comparing the two proves nothing on its own.
    expectEq(ContractError.deniedByUser(.en).wire,
             "denied_by_user: the user refused this action. Do not retry it or work "
             + "around it; either take a different route that needs no permission, "
             + "or stop and say what you could not do.",
             "contrato: el wire en inglés es el de siempre")
    expectEq(ContractError.deniedByUser(.es).wire,
             "denied_by_user: la usuaria rechazó esta acción. No la reintentes ni la "
             + "rodees; toma otra ruta que no necesite permiso, o detente y di qué no "
             + "pudiste hacer.",
             "contrato: el wire en español es el de siempre")
}

/// 7. El contrato de la retícula vigila los doce campos de la proyección y
/// que la UI no active la app.
@MainActor func testTheProjectionRuleCoversEveryField() throws {
    guard let root = Conformance.repoRoot() else { return }
    let contract = try Conformance.contract(at: root)
    let rule = try #require(contract.rules["session-kind-write"]).pattern
    for field in ["kind", "job", "approvalQueue", "cards", "interruption", "voice",
                  "notice", "holding", "partial", "targets", "pipeline", "dictation"] {
        expect(Conformance.count(rule, in: ["projection.\(field) = x"]) == 1,
               "regla: cubre projection.\(field)")
    }
    expect(Conformance.count(rule, in: ["let kind = projection.kind", "projection.kind == .idle"]) == 0,
           "regla: leer no es escribir")
    expect(Conformance.count(rule, in: ["projection.approvalQueue += [request]",
                                        "projection.targets -= [target]",
                                        "projection.cards[0] = card",
                                        "projection.cards.insert(card, at: 0)",
                                        "projection.cards.removeAll()",
                                        "projection.targets.removeFirst()"]) == 6,
           "regla: sumar, restar, indexar, insertar y vaciar también son escribir")
    let activation = try #require(contract.rules["main-activation"]).pattern
    expect(Conformance.count(activation, in: ["NSApp.activate(ignoringOtherApps: true)", "window.makeKeyAndOrderFront(nil)"]) == 2,
           "regla: la activación de la app se ve")
    expect(Conformance.count(activation, in: [
        "NSApplication.shared.activate(options: .activateIgnoringOtherApps)",
        "NSRunningApplication.current.activate(options: [])",
        "NSApplication.shared.activate()",
        "window.makeKey()",
        "window.orderFront(nil)",
    ]) == 5, "regla: las formas modernas de robar el foco también se ven")
    expect(Conformance.count(activation, in: ["orderFrontRegardless()", "panel.orderOut(nil)"]) == 0,
           "regla: mostrar la island sin foco no cuenta")
}

/// 9. El libro solo da por buena una prueba que corre: `@Test` o invocada
/// desde una. Un nombre en un comentario, o una función que nadie llama, no
/// cuenta.
@MainActor func testTheLedgerOnlyCountsTestsThatRun() {
    let lines = Conformance.logicalLines(of: """
        @Test func discovered() {}
        func helper() {}
        @Test func runner() {
            helper()
        }
        func orphan() {}
        // func ghost() {}
        /// Doc that mentions func doc(
        """)
    expect(Conformance.testRuns("discovered", in: lines), "libro: una @Test corre")
    expect(Conformance.testRuns("helper", in: lines), "libro: una función invocada corre")
    expect(!Conformance.testRuns("orphan", in: lines), "libro: declarada y nunca invocada no corre")
    expect(!Conformance.testRuns("ghost", in: lines), "libro: un comentario no es una prueba")
    expect(!Conformance.testRuns("doc", in: lines), "libro: un doc no es una prueba")
    expect(!Conformance.testRuns("missing", in: lines), "libro: lo que no existe no corre")
}

/// 8. El libro de puertas tiene exactamente las de la spec (12d §3.1 más la
/// de 12e): borrar una puerta encogería el contrato sin que el runner lo notara.
@MainActor func testTheLedgerKeepsEveryGate() throws {
    guard let root = Conformance.repoRoot() else { return }
    let ledger = try Conformance.gates(at: root)
    let ids = ledger.gates.map(\.id)
    expectEq(ids, HUDGates.expected, "puertas: las de relay-hud-spec/05 §10, 00 §3 y 12e, en orden")
    expectEq(Set(ids).count, ids.count, "puertas: sin repetidas")
}
