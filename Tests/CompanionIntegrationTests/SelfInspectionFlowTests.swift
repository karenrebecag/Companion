import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import CompanionCoreTestSupport
import CompanionServicesTestSupport
import CompanionUITestSupport
import CompanionTestKit
import Foundation
import Testing

// Spec self-qa-inspeccion, PR-6: the composition the app wires, end to end.
// A real session model and chat behind the UI source, the runner over it,
// and the bridge in front: inspecting never touches a pending approval, and
// no user or model text leaves through any `companion_*`.

private let sentinel = "SENTINEL-7f3a-ZXQ"
private let companionNames = CompanionTool.allCases.map(\.rawValue)

private func arguments(_ name: String) -> String {
    name == CompanionTool.lastMessageMatches.rawValue ? #"{"expected":"\#(sentinel)"}"# : "{}"
}

/// A chat whose session asks its approvals through `approvals`, so a
/// resolution by anyone would show up there.
@MainActor private func chat(session: SessionModel) -> ChatViewModel {
    ChatViewModel(
        chat: FakeChatProvider(), secrets: TestSecretStore([.openAI: "sk-test"]),
        store: MemoryConversationStore(), config: Config(), session: session)
}

/// The runner exactly as `installBridge` builds it, with fakes only where the
/// app reads the machine (language detection, the log file) and its own
/// equality budget so no other test spends it.
@MainActor private func runner(_ model: ChatViewModel, mirror: InspectionMirror) -> SelfInspectionRunner {
    SelfInspectionRunner(
        source: SelfInspectionSource(session: model.session, chat: model, mirror: mirror),
        recognizer: FakeRecognizer(), language: { .en }, logTail: { _ in [] },
        equalityLimit: EqualityLimitBox())
}

private func request(summary: String = sentinel) -> ApprovalRequest {
    ApprovalRequest(requestId: "pending-1", toolName: "write_file", summary: summary, inputJSON: #"{"path":"\#(sentinel)"}"#)
}

/// R1: every `companion_*` reads; none answers, withdraws or reorders the
/// approval Karen has not decided yet.
@Test @MainActor func pendingApprovalIsUntouchedByEveryCompanionTool() async {
    let approvals = ScriptedApprovals(park: true)
    let session = SessionModel(jobs: nil, approvals: approvals)
    let model = chat(session: session)
    session.send(.job(.started(goal: sentinel)))
    session.send(.job(.approvalRequested(request())))
    let before = session.projection.approvalQueue.map(\.requestId)
    expectEq(before, ["pending-1"], "premisa: hay una aprobacion pendiente")
    let served = runner(model, mirror: InspectionMirror())
    for name in companionNames {
        let outcome = await served.execute(name: name, argumentsJSON: arguments(name))
        expectEq(outcome.target, "", "\(name): sin contenido en target")
    }
    expectEq(session.projection.approval?.requestId, "pending-1", "la aprobacion sigue pendiente")
    expectEq(session.projection.approvalQueue.map(\.requestId), before, "la cola no cambia")
    expect(approvals.resolutions.isEmpty, "nadie resolvio nada: \(approvals.resolutions)")
}

/// The App target is an executable no test can import, so its wiring is
/// pinned by reading the source (same approach as the gate that checks the
/// root wires `ContextPreference.locationChannelOn`). A2: the runner is built
/// once, for the bridge list, and never offered to the conversation.
@Test func theAppWiresTheRunnerIntoTheBridgeOnlyAndTheViewsIntoTheMirror() throws {
    let root = try #require(Conformance.repoRoot(), "sin la raiz del repo no se comprueba nada")
    let app = root.appendingPathComponent("Sources/CompanionApp")
    let main = try String(contentsOf: app.appendingPathComponent("CompanionMain.swift"), encoding: .utf8)
    let window = try String(contentsOf: app.appendingPathComponent("CompanionMainWindow.swift"), encoding: .utf8)
    let everyAppFile = try Conformance.swiftFiles(in: app).map { try String(contentsOf: $0, encoding: .utf8) }
    expect(everyAppFile.count >= 2, "el barrido de la App lee archivos (\(everyAppFile.count))")
    let runnerSites = everyAppFile.map { occurrences(of: "SelfInspectionRunner(", in: $0) }.reduce(0, +)
    expectEq(runnerSites, 1, "la App construye el runner una sola vez")
    let bridge = try #require(main.range(of: "private func installBridge"), "installBridge existe")
    let afterBridge = main[bridge.lowerBound...]
    let bridgeBody = afterBridge.prefix(upTo: afterBridge.range(of: "\n    }\n")?.upperBound ?? afterBridge.endIndex)
    expect(bridgeBody.contains("SelfInspectionRunner("), "el runner entra en la lista del puente, en installBridge")
    expect(bridgeBody.contains("CompositeParentTools(["), "compuesto junto a las manos y el navegador")
    // The source must read the mirror the views write; a fresh one here
    // would leave the island and the screen unanswered forever.
    expect(bridgeBody.contains("mirror: inspection"), "el runner lee el mismo espejo que escriben las vistas")
    expectEq(occurrences(of: "inspector", in: main), occurrences(of: "inspector", in: String(bridgeBody)),
             "el runner no sale de installBridge (nunca a las tools de la conversacion)")
    expect(main.contains("InspectionMirror()"), "el delegado crea el espejo")
    expectEq(occurrences(of: "mirror: inspection", in: window), 2, "la ventana y la isla reciben el espejo")
}

private func occurrences(of needle: String, in text: String) -> Int {
    text.components(separatedBy: needle).count - 1
}

/// A7 end to end: text with the sentinel in the thread, the job goal, the
/// approval and the painted island; nothing of it crosses the bridge.
@Test @MainActor func sentinelNeverLeavesThroughTheBridge() async {
    let session = SessionModel(jobs: nil, approvals: nil)
    let model = chat(session: session)
    model.messages = [
        ChatMessage(role: .user, text: sentinel),
        ChatMessage(role: .assistant, text: "respuesta con \(sentinel)"),
    ]
    session.send(.job(.started(goal: sentinel)))
    session.send(.job(.approvalRequested(request())))
    let mirror = InspectionMirror()
    mirror.paint(IslandState(size: .card, line: .followUp(sentinel)))
    mirror.show(page: .home, settingsOpen: false, settingsTab: .general)
    let sheets = ScriptedApprovals(answer: true)
    let bridge = BridgeSession(
        tools: runner(model, mirror: mirror), guard: ParentToolGuard(approvals: sheets),
        token: { "tok" }, language: { .en }, accessibility: { true })
    _ = await bridge.handle(line: #"{"id":1,"method":"hello","params":{"token":"tok","client":"claude-code","protocol":1}}"#)
    for (offset, name) in companionNames.enumerated() {
        let line = #"{"id":\#(offset + 2),"method":"call","params":{"name":"\#(name)","arguments":\#(arguments(name))}}"#
        let result = await bridge.handle(line: line)
        expect(result.reply.contains(#""ok":true"#), "\(name): responde (\(result.reply))")
        expect(!result.reply.contains(sentinel), "\(name): el centinela no sale por el puente")
    }
    // A6 at the bridge: the only sheet is the session's; no `companion_*`
    // asks one of its own.
    expectEq(sheets.requests.map(\.toolName), [BridgePolicy.sessionApprovalTool], "solo la hoja de sesion")
}
