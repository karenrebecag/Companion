import CompanionCore
@testable import CompanionServices
import CompanionCoreTestSupport
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// Each hand that acts closes its result with what changed, read from the
// app's own notifications, instead of telling the model to look again.

@Test @MainActor func handsChangeTests() async {
    await testClickResultCarriesWhatChanged()
    await testTheWatchOpensBeforeTheAction()
    await testNothingObservedSaysDoNotRepeat()
    await testAFailedActionNeverWaits()
    await testMenuTypeAndKeyCarryTheLineToo()
    await testWithoutAWatcherTheResultsAreAsBefore()
    await testTheSpecifiedTimingReachesTheWatch()
    await testEveryFailedHandCancelsItsWatch()
    await testAWatcherThatCannotWatchSaysSo()
    await testTypedTextNeverComesBackThroughATitle()
}

/// Notes the click in the watcher's order so a test can see the watch was
/// already open when the hand moved.
private final class OrderedScreen: ScreenActing, @unchecked Sendable {
    let inner: FakeScreen
    let watcher: FakeChangeWatcher
    init(_ inner: FakeScreen, _ watcher: FakeChangeWatcher) {
        self.inner = inner
        self.watcher = watcher
    }
    func walk(pid: Int32) -> ScreenWalk? { inner.walk(pid: pid) }
    func click(node: Int, generation: Int, pid: Int32, label: String) -> ClickOutcome {
        watcher.note("click")
        return inner.click(node: node, generation: generation, pid: pid, label: label)
    }
    func scroll(node: Int?, generation: Int, direction: ScrollDirection, pid: Int32) -> Bool {
        inner.scroll(node: node, generation: generation, direction: direction, pid: pid)
    }
    func menuTitle(path: [String], pid: Int32) -> String? { inner.menuTitle(path: path, pid: pid) }
    func menu(path: [String], pid: Int32, expecting: String) -> String? {
        inner.menu(path: path, pid: pid, expecting: expecting)
    }
}

private let nodes = [
    ScanNode(role: "AXButton", subrole: "", label: "Nueva", value: nil, secure: false),
]

private func runner(
    watcher: FakeChangeWatcher?, screen: FakeScreen = FakeScreen(nodes),
    hands: FakeHands = FakeHands(field: FocusedField(app: "Notes", pid: 7))
) -> ParentToolRunner {
    let acting: any ScreenActing = watcher.map { OrderedScreen(screen, $0) } ?? screen
    return ParentToolRunner(
        workspace: FakeWorkspaceOpener(),
        hands: ScreenHands(
            injector: hands, reader: hands, keys: hands, windows: hands,
            trusted: { true }, target: { 7 }, bundleID: { _ in "com.apple.Notes" },
            screen: acting, changes: watcher))
}

private let windowOpened = ChangeReport(
    changes: [AXChange(kind: .windowAppeared, title: "Nota nueva")], watching: true)

@MainActor func testClickResultCarriesWhatChanged() async {
    let watcher = FakeChangeWatcher(report: windowOpened)
    let run = runner(watcher: watcher)
    _ = await run.execute(name: "look", argumentsJSON: "{}")
    let out = await run.execute(name: "click", argumentsJSON: #"{"id":1}"#)
    expect(out.ok, "click: ok")
    expect(out.output.contains("clicked [1]"), "click: sigue diciendo que pulso")
    expect(out.output.contains("Nota nueva"), "click: dice la ventana que aparecio")
    expect(!out.output.contains("look again"), "click: ya no manda al modelo a mirar de nuevo")
    expectEq(watcher.begun, [7], "click: un observador para el pid del turno")
}

@MainActor func testTheWatchOpensBeforeTheAction() async {
    let watcher = FakeChangeWatcher(report: windowOpened)
    let run = runner(watcher: watcher)
    _ = await run.execute(name: "look", argumentsJSON: "{}")
    _ = await run.execute(name: "click", argumentsJSON: #"{"id":1}"#)
    expectEq(watcher.order, ["begin", "click", "settle"], "click: observar, actuar, esperar")
}

@MainActor func testNothingObservedSaysDoNotRepeat() async {
    let watcher = FakeChangeWatcher(report: ChangeReport(changes: [], watching: true))
    let run = runner(watcher: watcher)
    _ = await run.execute(name: "look", argumentsJSON: "{}")
    let out = await run.execute(name: "click", argumentsJSON: #"{"id":1}"#)
    expect(out.ok, "nada observado: sigue siendo ok, no es un fallo")
    expect(out.output.lowercased().contains("do not repeat"), "nada observado: no repitas")
}

@MainActor func testAFailedActionNeverWaits() async {
    let watcher = FakeChangeWatcher(report: windowOpened)
    let screen = FakeScreen(nodes)
    let run = runner(watcher: watcher, screen: screen)
    _ = await run.execute(name: "look", argumentsJSON: "{}")
    _ = screen.walk(pid: 7)
    let out = await run.execute(name: "click", argumentsJSON: #"{"id":1}"#)
    expect(!out.ok, "fallo: el click viejo falla")
    expectEq(watcher.settled, 0, "fallo: no se espera un segundo por una accion que no ocurrio")
    expect(!out.output.contains("Nota nueva"), "fallo: ningun cambio inventado")
}

@MainActor func testMenuTypeAndKeyCarryTheLineToo() async {
    let watcher = FakeChangeWatcher(report: windowOpened)
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7))
    let run = runner(watcher: watcher, hands: hands)

    let menu = await run.execute(name: "menu", argumentsJSON: #"{"path":"Archivo > Nueva nota"}"#)
    expect(menu.ok && menu.output.contains("Nota nueva"), "menu: lleva la linea de cambio")

    let typed = await run.execute(name: "type_text", argumentsJSON: #"{"text":"secreto"}"#)
    expect(typed.ok && typed.output.contains("a new window appeared"), "type_text: lleva la linea de cambio, sin titulos")
    expect(!typed.output.contains("Nota nueva"), "type_text: el titulo no se muestra")
    expect(!typed.output.contains("secreto"), "type_text: el texto tecleado nunca vuelve en el resultado")

    let key = await run.execute(name: "press_key", argumentsJSON: #"{"key":"tab"}"#)
    expect(key.ok && key.output.contains("Nota nueva"), "press_key: lleva la linea de cambio")
    expectEq(watcher.settled, 3, "uno por mano que actuo")
}

@MainActor func testWithoutAWatcherTheResultsAreAsBefore() async {
    let run = runner(watcher: nil)
    _ = await run.execute(name: "look", argumentsJSON: "{}")
    let out = await run.execute(name: "click", argumentsJSON: #"{"id":1}"#)
    expect(out.output.contains("look again"), "sin observador: el comportamiento anterior")
}

@MainActor func testTheSpecifiedTimingReachesTheWatch() async {
    let watcher = FakeChangeWatcher(report: windowOpened)
    let run = runner(watcher: watcher)
    _ = await run.execute(name: "look", argumentsJSON: "{}")
    _ = await run.execute(name: "click", argumentsJSON: #"{"id":1}"#)
    _ = await run.execute(name: "menu", argumentsJSON: #"{"path":"Archivo > Nueva nota"}"#)
    _ = await run.execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
    _ = await run.execute(name: "press_key", argumentsJSON: #"{"key":"tab"}"#)
    expectEq(watcher.timings, Array(repeating: SettleTiming.standard, count: 4),
             "tiempos: las cuatro manos esperan con el presupuesto especificado")
}

@MainActor func testEveryFailedHandCancelsItsWatch() async {
    let watcher = FakeChangeWatcher(report: windowOpened)
    let screen = FakeScreen(nodes)
    screen.menuTitles = []
    let hands = FakeHands(field: nil)
    let run = runner(watcher: watcher, screen: screen, hands: hands)

    _ = await run.execute(name: "look", argumentsJSON: "{}")
    _ = screen.walk(pid: 7)
    let click = await run.execute(name: "click", argumentsJSON: #"{"id":1}"#)
    expect(!click.ok && !click.output.contains("Nota nueva"), "click fallido: sin linea de cambio")
    expectEq(watcher.order, ["begin", "click"], "click fallido: se abrio el watch, se intento y nunca se espero")

    let menu = await run.execute(name: "menu", argumentsJSON: #"{"path":"Archivo > Nada"}"#)
    expect(!menu.ok && !menu.output.contains("Nota nueva"), "menu fallido: sin linea de cambio")

    let typed = await run.execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
    expect(!typed.ok && !typed.output.contains("Nota nueva"), "type_text fallido: sin linea de cambio")

    let key = await run.execute(name: "press_key", argumentsJSON: #"{"key":"no-existe"}"#)
    expect(!key.ok && !key.output.contains("Nota nueva"), "press_key fallido: sin linea de cambio")

    expectEq(watcher.settled, 0, "fallos: ninguna espera")
    expectEq(watcher.cancelled, watcher.begun.count, "fallos: cada watch abierto se cancela")
}

@MainActor func testAWatcherThatCannotWatchSaysSo() async {
    let watcher = FakeChangeWatcher(report: ChangeReport(changes: [], watching: false))
    let run = runner(watcher: watcher)
    _ = await run.execute(name: "look", argumentsJSON: "{}")
    let out = await run.execute(name: "click", argumentsJSON: #"{"id":1}"#)
    expect(out.ok, "sin observador: la mano sigue siendo ok")
    expect(out.output.contains("could not watch"), "sin observador: lo dice")
    expect(!out.output.lowercased().contains("do not repeat")
           && !out.output.contains("no accessibility change"),
           "sin observador: no afirma que nada cambio ni prohibe repetir")
    expectEq(out.output, "clicked [1] button \"Nueva\".\ncould not watch for changes in this app; "
        + "look to check the result.", "sin observador: salida exacta del click")
}

@MainActor func testTypedTextNeverComesBackThroughATitle() async {
    let echo = ChangeReport(changes: [AXChange(kind: .titleChanged, title: "secreto")], watching: true)
    let watcher = FakeChangeWatcher(report: echo)
    let run = runner(watcher: watcher)
    let typed = await run.execute(name: "type_text", argumentsJSON: #"{"text":"secreto"}"#)
    expect(typed.ok && !typed.output.contains("secreto"),
           "type_text: un titulo que refleja lo escrito no vuelve al modelo")
    let key = await run.execute(name: "press_key", argumentsJSON: #"{"key":"tab"}"#)
    expect(key.output.contains("secreto"), "press_key: los titulos si se muestran, no hay texto propio que filtrar")
}
