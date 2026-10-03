import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// Small fixes to the hands: a shortcut list instead of bare keys, menu items
// that are greyed out, scrolling sideways and into view, open_app that waits
// for the window, and no hands at all while the Mac is locked.

@Test @MainActor func handsFixesTests() async {
    await testWhitelistedChordsReachThePortWithTheirModifiers()
    await testAChordOutsideTheListNeverReachesThePort()
    await testNoChordInACommandApp()
    await testALockedMacRefusesEveryHand()
    await testADisabledMenuItemIsNotPressed()
    await testSidewaysAndIntoViewScrolls()
    await testOpenAppWaitsForTheWindowAndPinsThePid()
    await testOpenAppTimesOutWithWindowNotReady()
    await testOpenAppNeverGettingAPidTimesOut()
    await testOpenAppWhoseFrontNeverMovesTimesOut()
    await testACutTurnIsNotWindowNotReady()
    await testChordsStopWhenTheAppMovedOrTheEventCannotPost()
    await testScrollAndMenuEdges()
    await testOpenAppWithoutAProbeKeepsTheOldBehavior()
}

private let nodes = [ScanNode(role: "AXButton", subrole: "", label: "Nueva", value: nil, secure: false)]

private func runner(
    hands: FakeHands = FakeHands(field: FocusedField(app: "Notes", pid: 7)),
    screen: FakeScreen = FakeScreen(nodes),
    bundle: String = "com.apple.Notes",
    target: ScriptedTarget = ScriptedTarget([7]),
    locked: Bool = false,
    workspace: FakeWorkspaceOpener = FakeWorkspaceOpener(),
    launch: (any AppWindowProbing)? = nil,
    windowWait: WindowWait = .standard
) -> ParentToolRunner {
    ParentToolRunner(
        workspace: workspace,
        hands: ScreenHands(
            injector: hands, reader: hands, keys: hands, windows: hands,
            trusted: { true }, target: { target.next() }, bundleID: { _ in bundle },
            screen: screen, locked: { locked }, launch: launch, windowWait: windowWait))
}

@MainActor func testWhitelistedChordsReachThePortWithTheirModifiers() async {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7))
    let run = runner(hands: hands)
    let out = await run.execute(name: "press_key", argumentsJSON: #"{"key":"cmd+shift+n"}"#)
    expect(out.ok, "acorde: ok")
    expectEq(out.output, "pressed cmd+shift+n", "acorde: el resultado nombra el acorde")
    expectEq(hands.pressedChords.map(\.chord), [KeyChord(modifiers: [.command, .shift], key: .n)],
             "acorde: llega al puerto con exactamente sus modificadores")
    expectEq(hands.pressedChords.map(\.pid), [7], "acorde: al pid del turno")
    expect(hands.pressed.isEmpty, "acorde: no se manda tambien como tecla suelta")
}

@MainActor func testAChordOutsideTheListNeverReachesThePort() async {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7))
    let run = runner(hands: hands)
    for key in ["cmd+w", "cmd+q", "ctrl+n", "cmd+s", "cmd+shift+z", "cmd+a"] {
        let out = await run.execute(name: "press_key", argumentsJSON: #"{"key":"\#(key)"}"#)
        expect(!out.ok && out.output.hasPrefix("chord_not_allowed:"), "fuera de lista: \(key) rechazado")
    }
    expect(hands.pressedChords.isEmpty && hands.pressed.isEmpty,
           "fuera de lista: nada llego al puerto de eventos")
    let plain = await run.execute(name: "press_key", argumentsJSON: #"{"key":"tab"}"#)
    expect(plain.ok && hands.pressed.map(\.key) == [.tab], "tecla suelta: sigue igual")
}

@MainActor func testNoChordInACommandApp() async {
    let hands = FakeHands(field: FocusedField(app: "Terminal", pid: 7))
    let run = runner(hands: hands, bundle: "com.apple.Terminal")
    let out = await run.execute(name: "press_key", argumentsJSON: #"{"key":"cmd+n"}"#)
    expect(!out.ok && out.output.hasPrefix("chord_not_allowed:"), "terminal: ningun acorde")
    expect(hands.pressedChords.isEmpty, "terminal: nada llego al puerto")
    for bundle in ["com.microsoft.VSCode", "com.googlecode.iterm2"] {
        let other = FakeHands(field: FocusedField(app: "App", pid: 7))
        let again = await runner(hands: other, bundle: bundle)
            .execute(name: "press_key", argumentsJSON: #"{"key":"cmd+f"}"#)
        expect(!again.ok && other.pressedChords.isEmpty, "app de comandos \(bundle): ningun acorde")
    }
}

@MainActor func testALockedMacRefusesEveryHand() async {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7), text: "x")
    let screen = FakeScreen(nodes)
    let run = runner(hands: hands, screen: screen, locked: true)
    for (name, args) in [("look", "{}"), ("click", #"{"id":0}"#), ("type_text", #"{"text":"hola"}"#),
                         ("press_key", #"{"key":"tab"}"#), ("read_focused", "{}"),
                         ("scroll", #"{"direction":"down"}"#), ("menu", #"{"path":"A > B"}"#),
                         ("focus_window", #"{"title":"x"}"#)] {
        let out = await run.execute(name: name, argumentsJSON: args)
        expect(!out.ok && out.output.hasPrefix("screen_locked:"), "bloqueada: \(name) se niega")
    }
    expect(hands.injected.isEmpty && hands.pressed.isEmpty && hands.raised.isEmpty
           && screen.clicks.isEmpty && screen.scrolls.isEmpty && screen.menus.isEmpty,
           "bloqueada: ningun puerto recibio nada")
    let unlocked = runner(hands: hands, screen: screen, locked: false)
    let ok = await unlocked.execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
    expect(ok.ok, "desbloqueada: las manos vuelven a actuar")
}

@MainActor func testADisabledMenuItemIsNotPressed() async {
    let screen = FakeScreen(nodes)
    screen.disabledMenus = ["Pegar"]
    let run = runner(screen: screen)
    let out = await run.execute(name: "menu", argumentsJSON: #"{"path":"Edición > Pegar"}"#)
    expect(!out.ok && out.output.hasPrefix("menu_disabled:"), "menu: item gris da menu_disabled")
    expect(screen.menus.isEmpty, "menu: el item gris no se pulsa")
    let enabled = await run.execute(name: "menu", argumentsJSON: #"{"path":"Edición > Copiar"}"#)
    expect(enabled.ok && screen.menus.count == 1, "menu: uno habilitado se pulsa")
}

@MainActor func testSidewaysAndIntoViewScrolls() async {
    let screen = FakeScreen(nodes)
    let run = runner(screen: screen)
    _ = await run.execute(name: "look", argumentsJSON: "{}")
    for direction in ["left", "right"] {
        let out = await run.execute(name: "scroll", argumentsJSON: #"{"direction":"\#(direction)"}"#)
        expectEq(out.output, "scrolled \(direction); look again", "scroll \(direction): ok y su texto")
    }
    let into = await run.execute(name: "scroll", argumentsJSON: #"{"direction":"into_view","id":1}"#)
    expect(into.ok && into.output == "brought into view; look again", "into_view: ok con id y su texto")
    expectEq(screen.scrolls.map(\.direction), [.left, .right, .intoView], "scroll: las tres llegan al adaptador")
    let bare = await run.execute(name: "scroll", argumentsJSON: #"{"direction":"into_view"}"#)
    expect(!bare.ok && bare.output.hasPrefix("invalid_args:"), "into_view sin id: pide el id")
    expectEq(screen.scrolls.count, 3, "into_view sin id: no llega al adaptador")
}

@MainActor func testOpenAppWaitsForTheWindowAndPinsThePid() async {
    let hands = FakeHands(field: FocusedField(app: "Notas", pid: 9))
    // The front moves to the new app only on the fourth read: a late activation.
    let target = ScriptedTarget([7, 7, 7, 9])
    let run = runner(
        hands: hands, target: target, workspace: FakeWorkspaceOpener(installed: ["Notas"]),
        launch: FakeAppWindows(pid: 9, pidAfter: 1, windowAfter: 2),
        windowWait: WindowWait(timeout: 2, poll: 0.01))
    let open = await run.execute(name: "open_app", argumentsJSON: #"{"name":"Notas"}"#)
    expect(open.ok, "open_app: ok cuando hay ventana")
    let typed = await run.execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
    expect(typed.ok, "open_app: la mano siguiente actua")
    expectEq(hands.injected.map(\.pid), [9], "open_app: lo escrito cae en el pid recien abierto, no en la app anterior")
}

@MainActor func testOpenAppTimesOutWithWindowNotReady() async {
    let hands = FakeHands(field: FocusedField(app: "Notas", pid: 9))
    let run = runner(
        hands: hands, target: ScriptedTarget([7]), workspace: FakeWorkspaceOpener(installed: ["Notas"]),
        launch: FakeAppWindows(pid: 9, pidAfter: 0, windowAfter: 1_000_000),
        windowWait: WindowWait(timeout: 0.1, poll: 0.01))
    let open = await run.execute(name: "open_app", argumentsJSON: #"{"name":"Notas"}"#)
    expect(!open.ok && open.output.hasPrefix("window_not_ready:"), "open_app: plazo vencido da window_not_ready")
    expect(hands.injected.isEmpty, "open_app: nada se escribio en la app anterior")
}

@MainActor func testOpenAppNeverGettingAPidTimesOut() async {
    let hands = FakeHands(field: FocusedField(app: "Notas", pid: 9))
    let windows = FakeAppWindows(pid: 9, pidAfter: .max)
    let run = runner(
        hands: hands, target: ScriptedTarget([7]), workspace: FakeWorkspaceOpener(installed: ["Notas"]),
        launch: windows, windowWait: WindowWait(timeout: 0.1, poll: 0.01))
    let open = await run.execute(name: "open_app", argumentsJSON: #"{"name":"Notas"}"#)
    expect(!open.ok && open.output.hasPrefix("window_not_ready:"), "sin pid: window_not_ready")
    expectEq(open.target, "Notas", "sin pid: el resultado nombra la app")
    expect(windows.reads.pid > 1, "sin pid: miro varias veces antes de rendirse")
    let typed = await run.execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
    expect(hands.injected.allSatisfy { $0.pid != 9 }, "sin pid: nada se escribe en la app que nunca estuvo lista")
    expect(!typed.ok, "sin pid: la mano siguiente no escribe en ningun lado")
}

@MainActor func testOpenAppWhoseFrontNeverMovesTimesOut() async {
    let hands = FakeHands(field: FocusedField(app: "Notas", pid: 9))
    let run = runner(
        hands: hands, target: ScriptedTarget([7]), workspace: FakeWorkspaceOpener(installed: ["Notas"]),
        launch: FakeAppWindows(pid: 9), windowWait: WindowWait(timeout: 0.1, poll: 0.01))
    let open = await run.execute(name: "open_app", argumentsJSON: #"{"name":"Notas"}"#)
    expect(!open.ok && open.output.hasPrefix("window_not_ready:"),
           "el frente no se mueve: pid y ventana listos no bastan, window_not_ready")
}

@MainActor func testACutTurnIsNotWindowNotReady() async {
    let hands = FakeHands(field: FocusedField(app: "Notas", pid: 9))
    let run = runner(
        hands: hands, target: ScriptedTarget([7]), workspace: FakeWorkspaceOpener(installed: ["Notas"]),
        launch: FakeAppWindows(pid: 9, pidAfter: .max), windowWait: WindowWait(timeout: 30, poll: 0.01))
    let task = Task { await run.execute(name: "open_app", argumentsJSON: #"{"name":"Notas"}"#) }
    await settle(0.05)
    let started = Date()
    task.cancel()
    let open = await task.value
    expect(Date().timeIntervalSince(started) < 1, "turno cortado: open_app vuelve en seguida")
    expect(!open.ok && open.output.hasPrefix("cancelled:"), "turno cortado: no se dice que la app no tiene ventana")
}

@MainActor func testChordsStopWhenTheAppMovedOrTheEventCannotPost() async {
    let moved = FakeHands(field: FocusedField(app: "Notes", pid: 7))
    // The first read resolves the target, the second (right before posting) finds another app in front.
    let out = await runner(hands: moved, target: ScriptedTarget([7, 8]))
        .execute(name: "press_key", argumentsJSON: #"{"key":"cmd+n"}"#)
    expect(!out.ok && out.output.hasPrefix("target_changed:"), "acorde: app movida, target_changed")
    expect(moved.pressedChords.isEmpty, "acorde: app movida, nada se manda")

    let broken = FakeHands(field: FocusedField(app: "Notes", pid: 7))
    broken.chordsPost = false
    let refused = await runner(hands: broken)
        .execute(name: "press_key", argumentsJSON: #"{"key":"cmd+n"}"#)
    expect(!refused.ok && refused.output.hasPrefix("refused:"), "acorde: el evento no se pudo mandar, refused")

    let missing = await runner().execute(name: "press_key", argumentsJSON: #"{"key":5}"#)
    expect(!missing.ok && missing.output.hasPrefix("invalid_args:"), "sin tecla de texto: sigue el camino de NamedKey")
}

@MainActor func testScrollAndMenuEdges() async {
    let screen = FakeScreen(nodes)
    screen.disabledMenus = ["Cerrar"]
    let run = runner(screen: screen)
    _ = await run.execute(name: "look", argumentsJSON: "{}")
    let stale = await run.execute(name: "scroll", argumentsJSON: #"{"direction":"into_view","id":99}"#)
    expect(!stale.ok && stale.output.hasPrefix("invalid_args:"), "into_view con un id que no existe: invalid_args")
    expect(screen.scrolls.isEmpty, "into_view con un id que no existe: no llega al adaptador")
    let bad = await run.execute(name: "scroll", argumentsJSON: #"{"direction":"diagonal"}"#)
    expect(bad.output.hasPrefix("invalid_args:") && bad.output.contains("into_view")
           && bad.output.contains("left"), "direccion invalida: la lista nombra todas las validas")

    // A greyed-out destructive item answers menu_disabled before it can spend or need an approval.
    let closed = await run.execute(name: "menu", argumentsJSON: #"{"path":"Archivo > Cerrar"}"#)
    expect(!closed.ok && closed.output.hasPrefix("menu_disabled:"), "menu gris y destructivo: menu_disabled primero")
    expect(screen.menus.isEmpty, "menu gris y destructivo: nada se pulsa")
    expectEq(screen.menu(path: ["Archivo", "Cerrar"], pid: 7, expecting: "Cerrar"), nil,
             "menu gris: ni siquiera el adaptador lo pulsa al re-resolver")
}

@MainActor func testOpenAppWithoutAProbeKeepsTheOldBehavior() async {
    let hands = FakeHands(field: FocusedField(app: "Notas", pid: 9))
    let workspace = FakeWorkspaceOpener(installed: ["Notas"])
    let run = runner(hands: hands, workspace: workspace)
    let started = Date()
    let open = await run.execute(name: "open_app", argumentsJSON: #"{"name":"Notas"}"#)
    expect(open.ok && workspace.openedApps == ["Notas"], "sin sonda: open_app vuelve como antes")
    expect(Date().timeIntervalSince(started) < 1, "sin sonda: no espera")
    let missing = await runner(hands: hands, workspace: workspace,
                               launch: FakeAppWindows(pid: 9, pidAfter: .max),
                               windowWait: WindowWait(timeout: 5, poll: 0.01))
        .execute(name: "open_app", argumentsJSON: #"{"name":"NoExiste"}"#)
    expect(!missing.ok && !missing.output.hasPrefix("window_not_ready:"),
           "app que no existe: falla por no encontrada, sin esperar la ventana")
}
