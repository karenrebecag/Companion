import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionTestKit
import Foundation
import Testing

// arrange_windows as the parent's tool: reads never ask, a move asks every
// time and runs only on the yes the sheet gave for that exact call, and the
// undo state lives in the runner, never in the model's arguments.

private func fixture() -> FakeWindowArranger {
    FakeWindowArranger(displays: [WindowFixtures.laptop], windows: [
        WindowFixtures.window(1, "Safari", "Apple"),
        WindowFixtures.window(2, "Code", "main.swift",
                              frame: WindowRect(x: 200, y: 150, width: 900, height: 700)),
    ])
}

private func call(_ json: String) -> ToolCallRef {
    ToolCallRef(id: UUID().uuidString, name: "arrange_windows", arguments: json)
}

private let arrange = #"{"action":"arrange","layout":"left-right","apps":["Safari","Code"]}"#

@Test func windowRunnerOffersOneToolAndReadsWithoutASheet() async {
    let runner = WindowArrangeRunner(arranging: fixture())
    expectEq(runner.specs(.es).map(\.name), ["arrange_windows"], "runner: one tool")
    expect(runner.handles("arrange_windows") && !runner.handles("open_app"), "runner: only its own name")
    for json in [#"{"action":"inventory"}"#, #"{"action":"list_layouts"}"#,
                 #"{"action":"arrange","layout":"full","apps":["Safari"],"dry_run":true}"#,
                 #"{"action":"arrange","layout":"diagonal","apps":["Safari"]}"#,
                 #"{"action":"undo"}"#] {
        expect(runner.approval(for: call(json), said: "") == nil, "no sheet: \(json)")
    }
    let listed = await runner.execute(name: "arrange_windows", argumentsJSON: #"{"action":"list_layouts"}"#)
    expect(listed.ok && listed.output.contains("centered:"), "list_layouts: runs unasked")
    let broken = await runner.execute(name: "arrange_windows", argumentsJSON: "not json at all")
    expect(!broken.ok && broken.output.hasPrefix("invalid_args"), "runner: unparseable arguments")
    let empty = await runner.execute(name: "arrange_windows", argumentsJSON: #"{"action":"undo"}"#)
    expect(!empty.ok && empty.output.hasPrefix("nothing_to_undo"), "undo: nothing yet, nothing asked")
}

@Test func windowRunnerMovesOnlyOnTheYesForThatCall() async {
    let fake = fixture()
    let runner = WindowArrangeRunner(arranging: fake)
    let unasked = await runner.execute(name: "arrange_windows", argumentsJSON: arrange)
    expect(!unasked.ok && unasked.output.hasPrefix("approval_required"), "arrange: no yes, no move")
    expect(fake.moves.isEmpty, "arrange: nothing moved without the sheet")

    let ask = call(arrange)
    guard let request = runner.approval(for: ask, said: "pon safari y code lado a lado") else {
        Issue.record("a real arrange asks"); return
    }
    expectEq(request.toolName, "arrange_windows", "sheet: the tool's own name")
    expectEq(request.summary, "arrange left-right on Display 1: Safari, Code", "sheet: what will move")
    runner.withdraw(ask)
    runner.granted(request)
    let withdrawn = await runner.execute(name: "arrange_windows", argumentsJSON: arrange)
    expect(!withdrawn.ok, "arrange: a withdrawn call stays refused")

    guard let again = runner.approval(for: call(arrange), said: "") else { return }
    runner.granted(again)
    let placed = await runner.execute(name: "arrange_windows", argumentsJSON: arrange)
    expect(placed.ok && placed.output.contains("(placed)"), "arrange: runs on the yes")
    expectEq(placed.target, "left-right", "arrange: the thread names the layout")
    expectEq(fake.moves.count, 2, "arrange: both windows moved")
    let replay = await runner.execute(name: "arrange_windows", argumentsJSON: arrange)
    expect(!replay.ok, "arrange: the yes is spent")

    let undoCall = call(#"{"action":"restore"}"#)
    guard let undoRequest = runner.approval(for: undoCall, said: "") else {
        Issue.record("undo asks once there is something to undo"); return
    }
    expectEq(undoRequest.summary, "undo the last window arrangement", "sheet: undo says so")
    runner.granted(undoRequest)
    let undone = await runner.execute(name: "arrange_windows", argumentsJSON: undoCall.arguments)
    expect(undone.ok && undone.output.contains("Restored 2 windows"), "undo: both back")
    expectEq(fake.frame(of: 2), WindowRect(x: 200, y: 150, width: 900, height: 700), "undo: where it was")
}

@Test func windowRunnerNamesThePermissionWhenNotTrusted() async {
    let fake = fixture()
    fake.setTrusted(false)
    let runner = WindowArrangeRunner(arranging: fake)
    let outcome = await runner.execute(name: "arrange_windows", argumentsJSON: #"{"action":"inventory"}"#)
    expect(!outcome.ok && outcome.output.hasPrefix("needs_accessibility"), "permission: its code first")
    expect(outcome.output.contains("Privacy & Security > Accessibility"), "permission: where to grant it")
}

@Test func windowRunnerYesCoversOnlyTheExactCall() async {
    let fake = fixture()
    let runner = WindowArrangeRunner(arranging: fake)
    guard let first = runner.approval(for: call(arrange), said: "") else {
        Issue.record("a real arrange asks"); return
    }
    runner.granted(first)
    _ = await runner.execute(name: "arrange_windows", argumentsJSON: arrange)
    guard let yes = runner.approval(for: call(arrange), said: "") else { return }
    runner.granted(yes)
    let moves = fake.moves.count
    let others = [
        #"{"action":"arrange","layout":"thirds","apps":["Safari","Code","Notes"]}"#,
        #"{"action":"undo"}"#,
        // Same call, keys in another order: a different string, so it asks again.
        #"{"apps":["Safari","Code"],"layout":"left-right","action":"arrange"}"#,
    ]
    for json in others {
        let outcome = await runner.execute(name: "arrange_windows", argumentsJSON: json)
        expect(!outcome.ok && outcome.output.hasPrefix("approval_required"), "binding: refused \(json)")
    }
    expectEq(fake.moves.count, moves, "binding: nothing moved on another call's yes")
    let own = await runner.execute(name: "arrange_windows", argumentsJSON: arrange)
    expect(own.ok, "binding: the approved call still runs, its yes was not spent by the others")
}

/// Handles nothing: the composite must route past it to the arranger.
private struct NoTools: ParentToolExecuting {
    func specs(_ language: AppLanguage) -> [ToolSpec] { [] }
    func handles(_ name: String) -> Bool { false }
    func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        .failed(.notFound(name))
    }
}

@Test func windowRunnerWorksInsideTheComposite() async {
    let fake = fixture()
    let tools = CompositeParentTools([NoTools(), WindowArrangeRunner(arranging: fake)])
    expect(tools.specs(.en).contains { $0.name == "arrange_windows" }, "composite: offered")
    let ask = call(arrange)
    guard let request = tools.approval(for: ask, said: "") else {
        Issue.record("the composite routes the approval"); return
    }
    tools.granted(request)
    let placed = await tools.execute(name: "arrange_windows", argumentsJSON: arrange)
    expect(placed.ok, "composite: approval, grant, execute")

    let cut = call(arrange)
    guard let pending = tools.approval(for: cut, said: "") else { return }
    tools.granted(pending)
    tools.withdraw(cut)
    let moves = fake.moves.count
    let after = await tools.execute(name: "arrange_windows", argumentsJSON: arrange)
    expect(!after.ok && after.output.hasPrefix("approval_required"), "composite: a cut withdraws the yes")
    expectEq(fake.moves.count, moves, "composite: nothing moved after the cut")
}

@Test func windowToolNeverCrossesTheBridge() {
    expect(BridgeScope.isLocalOnly("arrange_windows"), "bridge: local only")
    expect(BridgeScope.decided("arrange_windows"), "bridge: its exposure is decided")
    expect(!BridgeScope.allows("arrange_windows"), "bridge: not lent")
}
