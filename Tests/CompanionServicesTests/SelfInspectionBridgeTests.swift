import CompanionCore
import CompanionCoreTestSupport
import CompanionServices
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// Spec self-qa-inspeccion, PR-3: the `companion_*` family enters the bridge.
// Read bucket, the same session sheet, the gate with `said: ""`, an empty
// target in the log, and answers while Companion is in front, where the
// hands keep refusing.

private let companionNames = CompanionTool.allCases.map(\.rawValue)

private func helloLine(_ id: Int) -> String {
    #"{"id":\#(id),"method":"hello","params":{"token":"tok","client":"claude-code","protocol":1}}"#
}

private func callLine(_ id: Int, _ name: String, _ arguments: String = "{}") -> String {
    #"{"id":\#(id),"method":"call","params":{"name":"\#(name)","arguments":\#(arguments)}}"#
}

private func arguments(_ name: String) -> String {
    name == CompanionTool.lastMessageMatches.rawValue ? #"{"expected":"hola"}"# : "{}"
}

private func session(_ tools: any ParentToolExecuting, approvals: (any ApprovalsProvider)?) -> BridgeSession {
    BridgeSession(
        tools: tools, guard: ParentToolGuard(approvals: approvals),
        token: { "tok" }, language: { .en }, accessibility: { true })
}

/// A painted island and a thread, so every `companion_*` has something to
/// answer; its own equality budget so no other test spends it.
private func inspection() -> SelfInspectionRunner {
    let source = FakeSelfInspecting()
    source.painted = PaintedIsland(state: IslandState(size: .nudge), catalogText: nil)
    source.thread = [FakeSelfInspecting.message("hola")]
    return SelfInspectionRunner(
        source: source, recognizer: FakeRecognizer(), language: { .en },
        logTail: { _ in ["una linea"] }, equalityLimit: EqualityLimitBox())
}

@Test func companionToolsAreAllowlistedAndReadBucketed() {
    for name in companionNames {
        expect(BridgeScope.allows(name), "\(name): en la allowlist del puente")
        expect(BridgePolicy.readTools.contains(name), "\(name): gasta del presupuesto de lectura")
        expect(!BridgePolicy.writeTools.contains(name), "\(name): nunca cuenta como accion")
        expect(!BridgeScope.isLocalOnly(name), "\(name): no es solo local")
    }
    expect(BridgePolicy.unbucketed(BridgeScope.bridgeTools).isEmpty,
           "toda tool del puente tiene cubo: \(BridgePolicy.unbucketed(BridgeScope.bridgeTools).sorted())")
    let offered = Set(inspection().specs(.en).map(\.name))
    expect(offered.isSubset(of: BridgePolicy.readTools), "A6: lo que ofrece el runner es todo lectura")
}

/// R7: the first `companion_*` of a connection asks the same session sheet
/// as any other tool; a denial runs nothing.
@Test @MainActor func firstCompanionCallOpensSessionSheetAndDenialRunsNothing() async {
    for name in companionNames {
        let tools = FakeParentTools(handledNames: Set(companionNames), specNames: [], specs: inspection().specs(.en))
        let approvals = ScriptedApprovals(answer: false)
        let bridge = session(tools, approvals: approvals)
        _ = await bridge.handle(line: helloLine(1))
        let result = await bridge.handle(line: callLine(2, name, arguments(name)))
        expect(result.reply.contains(BridgeCode.deniedByUser), "\(name): denegada, denied_by_user")
        expect(approvals.requests.contains { $0.toolName == BridgePolicy.sessionApprovalTool },
               "\(name): la primera llamada pide la hoja de sesion")
        expect(tools.executeCalls.isEmpty, "\(name): denegada, no corre nada")
    }
}

/// R2: the bridge has no words of the user, so the gate always sees "".
@Test @MainActor func companionCallsReachTheGateWithEmptySaid() async {
    let tools = FakeParentTools(handledNames: Set(companionNames), specNames: [], specs: inspection().specs(.en))
    let bridge = session(tools, approvals: ScriptedApprovals(answer: true))
    _ = await bridge.handle(line: helloLine(1))
    for (offset, name) in companionNames.enumerated() {
        _ = await bridge.handle(line: callLine(offset + 2, name, arguments(name)))
    }
    expectEq(tools.saidSeen.count, companionNames.count, "cada llamada pasa por la puerta")
    expect(tools.saidSeen.allSatisfy(\.isEmpty), "la puerta siempre ve said vacio")
    expectEq(tools.executeCalls.count, companionNames.count, "aprobada la sesion, todas corren")
}

/// A1: with Companion in front the family answers and the hands still
/// refuse, through the same composition the app wires.
@Test @MainActor func companionToolsServeWhileCompanionIsInFrontAndHandsStaySelfInFront() async {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7))
    let parent = ParentToolRunner(
        workspace: FakeWorkspaceOpener(),
        hands: ScreenHands(
            injector: hands, reader: hands, keys: hands, windows: hands,
            trusted: { true }, target: { 7 }, bundleID: { _ in "com.apple.Notes" },
            selfInFront: { true }, screen: FakeScreen([]), see: { _ in ScreenBrief(summary: "x") }))
    let bridge = session(CompositeParentTools([parent, inspection()]), approvals: ScriptedApprovals(answer: true))
    let hello = await bridge.handle(line: helloLine(1))
    var id = 2
    for name in companionNames {
        expect(hello.reply.contains("\"\(name)\""), "\(name): hello la anuncia con Companion delante")
        let result = await bridge.handle(line: callLine(id, name, arguments(name)))
        expect(result.reply.contains(#""ok":true"#), "\(name): responde con Companion delante (\(result.reply))")
        id += 1
    }
    for name in ["click", "menu", "scroll", "type_text", "press_key", "focus_window", "look", "see"] {
        let result = await bridge.handle(line: callLine(id, name))
        expect(result.reply.contains(BridgeCode.selfInFront), "\(name): las manos siguen en self_in_front (\(result.reply))")
        id += 1
    }
}

/// R6: the bridge log line names the call and never carries content; the
/// runner leaves `target` empty.
@Test @MainActor func companionCallLogLineHasEmptyTarget() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("companion-log-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let log = dir.appendingPathComponent("bridge.log")
    let bridge = session(inspection(), approvals: ScriptedApprovals(answer: true))
    await Log.capturing(to: log) {
        _ = await bridge.handle(line: helloLine(1))
        for (offset, name) in companionNames.enumerated() {
            _ = await bridge.handle(line: callLine(offset + 2, name, arguments(name)))
        }
    }
    let lines = try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
    for name in companionNames {
        let call = lines.first { $0.contains("call \(name) ok=") }
        expect(call != nil, "\(name): el puente registra la llamada")
        expect(call?.contains("target= chars=") == true, "\(name): con target vacio (\(call ?? "nada"))")
    }
    let text = lines.joined(separator: "\n")
    expect(!text.contains("hola"), "el log nunca lleva el texto esperado ni el del hilo")
    expect(!text.contains("una linea"), "ni las lineas del log que devuelve")
}
