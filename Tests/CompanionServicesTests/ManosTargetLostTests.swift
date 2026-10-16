import CompanionCore
import CompanionCoreTestSupport
@testable import CompanionServices
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// QA en vivo 2026-10-16: open_file/open_url no fijaban la app que abrian, y un
// timeout de la hoja se contaba como un "no" de la usuaria.

private func openRunner(
    workspace: FakeWorkspaceOpener, hands: FakeHands, target: ScriptedTarget, launch: FakeAppWindows
) -> ParentToolRunner {
    ParentToolRunner(
        workspace: workspace,
        hands: ScreenHands(
            injector: hands, reader: hands, keys: hands, windows: hands,
            trusted: { true }, target: { target.next() }, bundleID: { _ in "com.apple.finder" },
            screen: FakeScreen([]), launch: launch, windowWait: WindowWait(timeout: 2, poll: 0.01)))
}

@Test @MainActor func openFileOfAFolderPinsTheAppItOpened() async {
    let hands = FakeHands(field: FocusedField(app: "Finder", pid: 9))
    let workspace = FakeWorkspaceOpener()
    workspace.opensWith = "Finder"
    // The terminal (7) is in front when the folder opens; Finder (9) takes
    // the front a moment later, as it does after a real open.
    let run = openRunner(
        workspace: workspace, hands: hands, target: ScriptedTarget([7, 7, 9]),
        launch: FakeAppWindows(pid: 9))
    let open = await run.execute(name: "open_file", argumentsJSON: #"{"path":"~/Downloads"}"#)
    expect(open.ok, "open_file: abre la carpeta \(open.output)")
    let typed = await run.execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
    expect(typed.ok, "open_file: la mano siguiente no queda sin app fijada \(typed.output)")
    expectEq(hands.injected.map(\.pid), [9], "open_file: lo escrito cae en el pid de Finder")
}

@Test @MainActor func openURLPinsTheBrowserItOpened() async {
    let hands = FakeHands(field: FocusedField(app: "Safari", pid: 9))
    let workspace = FakeWorkspaceOpener()
    workspace.opensWith = "Safari"
    let run = openRunner(
        workspace: workspace, hands: hands, target: ScriptedTarget([7, 7, 9]),
        launch: FakeAppWindows(pid: 9))
    let open = await run.execute(name: "open_url", argumentsJSON: #"{"url":"https://example.com"}"#)
    expect(open.ok, "open_url: abre la direccion \(open.output)")
    let typed = await run.execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
    expect(typed.ok, "open_url: la mano siguiente actua \(typed.output)")
    expectEq(hands.injected.map(\.pid), [9], "open_url: lo escrito cae en el navegador abierto")
}

@Test @MainActor func anOpenThatNeverReachesTheFrontStillSucceeds() async {
    let hands = FakeHands(field: FocusedField(app: "Finder", pid: 9))
    let workspace = FakeWorkspaceOpener()
    workspace.opensWith = "Finder"
    let run = ParentToolRunner(
        workspace: workspace,
        hands: ScreenHands(
            injector: hands, reader: hands, keys: hands, windows: hands,
            trusted: { true }, target: { 7 }, bundleID: { _ in "com.apple.finder" },
            screen: FakeScreen([]), launch: FakeAppWindows(pid: 9),
            windowWait: WindowWait(timeout: 0.05, poll: 0.01)))
    let open = await run.execute(name: "open_file", argumentsJSON: #"{"path":"~/Downloads"}"#)
    expect(open.ok, "open_file: abrir no promete ventana al frente, solo open_app \(open.output)")
}

private func openURLCall() -> ToolCallRef {
    ToolCallRef(id: "c1", name: "open_url", arguments: #"{"url":"https://example.com"}"#)
}

@Test @MainActor func aSheetTimeoutIsNotReportedAsTheUserSayingNo() async {
    let approvals = Approvals(clock: RealtimeClock(), timeout: 0.05)
    let guardian = ParentToolGuard(approvals: approvals)
    let verdict = await guardian.verdict(
        openURLCall(), said: "", language: .es, strictURL: true, parked: nil)
    expectEq(verdict.answer, .timedOut, "timeout: la hoja caduco")
    let output = verdict.denial?.output ?? ""
    expect(output.hasPrefix("\(BridgeCode.approvalTimeout):"), "timeout: codigo propio \(output)")
    expect(!output.contains(BridgeCode.deniedByUser) && !output.contains("No la reintentes"),
           "timeout: no dice que la usuaria rechazo ni prohibe reintentar \(output)")
}

@Test @MainActor func aRealNoStaysDeniedByUser() async {
    let guardian = ParentToolGuard(approvals: ScriptedApprovals(answer: false))
    let verdict = await guardian.verdict(
        openURLCall(), said: "", language: .es, strictURL: true, parked: nil)
    expectEq(verdict.answer, .denied, "no: la usuaria nego")
    expect(verdict.denial?.output.hasPrefix("\(BridgeCode.deniedByUser):") == true,
           "no: sigue siendo denied_by_user \(verdict.denial?.output ?? "")")
}
