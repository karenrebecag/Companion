import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import CompanionCoreTestSupport
import CompanionServicesTestSupport
import CompanionTestKit
import CompanionUITestSupport
import Foundation
import Testing

// Wave 15g (spec §5, filas 1-9 y 11). Las manos del padre sobre la app que
// estaba delante: escribir, pulsar una tecla, levantar una ventana, leer el
// campo enfocado. Nunca en un campo seguro, nunca en Companion, nunca si la
// usuaria cambió de app; en una terminal, Return y multilínea piden permiso.

@Test @MainActor func screenHandsTests() async {
    await testTypeTextLandsInTheTargetPidWithoutReturn()
    await testTypeTextRefusesASecureFieldAndNeverLogsTheText()
    await testCompanionItselfIsNeverATarget()
    await testATargetThatMovedIsRefused()
    await testMultilineTypingInATerminalNeedsTheSheet()
    await testReturnNeedsTheSheetOnlyInATerminal()
    await testAKeyOutsideTheClosedListIsRejected()
    await testFocusWindowRaisesTheMatchingOne()
    testTheHandsAreNotOfferedWithoutAccessibility()
    await testReadFocusedIsClippedAndNeverSecure()
    await testNoFocusedFieldIsSaidPlainly()
    await testTheTypedChatAsksBeforeReturnInATerminal()
}

private func call(_ name: String, _ json: String) -> ToolCallRef {
    ToolCallRef(id: "c1", name: name, arguments: json)
}

/// 1.
@MainActor func testTypeTextLandsInTheTargetPidWithoutReturn() async {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7))
    let runner = handsRunner(hands)
    let out = await runner.execute(name: "type_text", argumentsJSON: #"{"text":"hola mundo"}"#)
    expect(out.ok, "type_text: ok")
    expectEq(hands.injected.map(\.text), ["hola mundo"], "type_text: el texto tal cual")
    expectEq(hands.injected.map(\.pid), [7], "type_text: al pid de la app de delante")
    expect(hands.pressed.isEmpty, "type_text: sin Return implícito")
    expectEq(out.output, "typed 10 chars (not read back)", "type_text: el cerebro sabe que nadie lo comprobó")
    expectEq(ParentTool.target(of: call("type_text", #"{"text":"secreto"}"#)), "",
             "type_text: la línea de estado nunca muestra el texto")
    expect(!ParentToolCopy.status("type_text", out, .es).contains("hola"),
           "type_text: el estado tampoco")
}

/// 2.
@MainActor func testTypeTextRefusesASecureFieldAndNeverLogsTheText() async {
    let hands = FakeHands(field: FocusedField(app: "Safari", pid: 7, secure: true))
    let runner = handsRunner(hands)
    let log = FileManager.default.temporaryDirectory
        .appendingPathComponent("hands-\(UUID().uuidString).log")
    let out = await Log.capturing(to: log) {
        await runner.execute(name: "type_text", argumentsJSON: #"{"text":"hunter2"}"#)
    }
    expect(!out.ok, "seguro: falla")
    expect(out.output.hasPrefix("secure_field:"), "seguro: código estable")
    expect(hands.injected.isEmpty, "seguro: nada inyectado")
    let lines = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
    expect(!lines.contains("hunter2"), "seguro: el log no lleva el texto")
    expect(lines.contains("chars=7"), "seguro: el log lleva la cuenta")
}

/// 3.
@MainActor func testCompanionItselfIsNeverATarget() async {
    let own = ProcessInfo.processInfo.processIdentifier
    let hands = FakeHands(field: FocusedField(app: "Companion", pid: own))
    let runner = handsRunner(hands, target: ScriptedTarget([own]))
    let out = await runner.execute(name: "type_text", argumentsJSON: #"{"text":"x"}"#)
    expect(!out.ok, "propia: rechazada")
    expect(hands.injected.isEmpty, "propia: nada inyectado")
    let none = await handsRunner(hands, target: ScriptedTarget([nil]))
        .execute(name: "press_key", argumentsJSON: #"{"key":"tab"}"#)
    expect(!none.ok, "sin app previa: rechazada")
    expect(hands.pressed.isEmpty, "sin app previa: nada pulsado")
    // The adapter refuses its own process on its own, not only the runner.
    let ax = AXTextInjector(selfBundleID: "com.karen.companion.test", trust: { true })
    expect(ax?.focusedField(pid: own) == nil, "adaptador: su propio pid no es campo")
    expect(ax?.read(pid: own) == nil, "adaptador: ni se lee")
    expectEq(ax?.press(.tab, pid: own), false, "adaptador: ni recibe teclas")
}

/// 4.
@MainActor func testATargetThatMovedIsRefused() async {
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7))
    let runner = handsRunner(hands, target: ScriptedTarget([7, 8]))
    let out = await runner.execute(name: "type_text", argumentsJSON: #"{"text":"hola"}"#)
    expect(!out.ok, "movida: rechazada")
    expect(out.output.hasPrefix("target_changed:"), "movida: código estable")
    expect(out.output.contains("look again"), "M1: dice que hacer: \(out.output)")
    expect(hands.injected.isEmpty, "movida: nada inyectado")
}

/// 5.
@MainActor func testMultilineTypingInATerminalNeedsTheSheet() async {
    let hands = FakeHands(field: FocusedField(app: "Terminal", pid: 7))
    let runner = handsRunner(hands, bundle: "com.apple.Terminal")
    let multi = call("type_text", #"{"text":"ls\nrm -rf x"}"#)
    let request = runner.approval(for: multi, said: "escribe ls")
    expectEq(request?.toolName, "type_text", "terminal: multilínea pide la hoja")
    expect(request?.summary.contains("ls") == false, "terminal: el resumen no lleva el texto")
    expect(request.map { ChatCopy.approvalDetail(tool: $0.toolName, inputJSON: $0.inputJSON) }?
        .contains("rm -rf x") == true, "terminal: la hoja muestra el comando a juzgar")

    let guardian = ParentToolGuard(approvals: DenyingApprovals())
    let denied = await guardian.check(multi, said: "escribe ls", language: .es, tools: runner)
    expect(denied?.output.hasPrefix("denied_by_user") == true, "terminal: denegada es denegada")
    expect(hands.injected.isEmpty, "terminal: denegada no escribe")

    let unasked = await runner.execute(name: multi.name, argumentsJSON: multi.arguments)
    expect(unasked.output.hasPrefix("approval_required:"),
           "terminal: sin pasar por la hoja, el runner se cierra solo")
    expect(hands.injected.isEmpty, "terminal: nada escrito sin permiso")

    let approved = ParentToolGuard(approvals: ApprovingApprovals())
    let pass = await approved.check(multi, said: "escribe ls", language: .es, tools: runner)
    expect(pass == nil, "terminal: aprobada sigue")
    let out = await runner.execute(name: multi.name, argumentsJSON: multi.arguments)
    expect(out.ok, "terminal: aprobada escribe")
    expectEq(hands.injected.count, 1, "terminal: una vez")

    let again = await runner.execute(name: multi.name, argumentsJSON: multi.arguments)
    expect(again.output.hasPrefix("approval_required:"), "terminal: el permiso se gasta")

    let single = call("type_text", #"{"text":"ls -la"}"#)
    expect(runner.approval(for: single, said: "escribe ls -la") == nil,
           "terminal: una línea dicha sin Return no pide nada")
}

/// 6.
@MainActor func testReturnNeedsTheSheetOnlyInATerminal() async {
    let enter = call("press_key", #"{"key":"return"}"#)
    let terminal = FakeHands(field: FocusedField(app: "iTerm2", pid: 7))
    let termRunner = handsRunner(terminal, bundle: "com.googlecode.iterm2")
    let request = termRunner.approval(for: enter, said: "dale enter")
    expectEq(request?.toolName, "press_key", "Return en terminal: hoja")
    expectEq(request.map { ChatCopy.approvalDetail(tool: $0.toolName, inputJSON: $0.inputJSON) },
             "return · iTerm2", "Return en terminal: la hoja nombra la tecla y la app")
    let tab = termRunner.approval(for: call("press_key", #"{"key":"tab"}"#), said: "tab")
    expect(tab == nil, "Tab en terminal: directo")

    let notes = FakeHands(field: FocusedField(app: "Notes", pid: 7))
    let notesRunner = handsRunner(notes)
    expect(notesRunner.approval(for: enter, said: "dale enter") == nil, "Return en Notas: directo")
    let out = await notesRunner.execute(name: enter.name, argumentsJSON: enter.arguments)
    expect(out.ok, "Return en Notas: ok")
    expectEq(notes.pressed.map(\.key), [.return], "Return en Notas: una tecla")
    expectEq(notes.pressed.map(\.pid), [7], "Return en Notas: al pid de delante")
    expectEq(out.output, "pressed return", "Return en Notas: el cerebro lo puede decir")
}

/// 7.
@MainActor func testAKeyOutsideTheClosedListIsRejected() async {
    expectEq(NamedKey.allCases.map(\.rawValue),
             ["return", "tab", "escape", "up", "down", "left", "right", "backspace"],
             "teclas: la lista cerrada")
    expect(rejected("f4"), "teclas: f4 no está")
    expect(rejected("cmd+q"), "teclas: ni un atajo")
    expectEq(try? NamedKey.parse(" Return "), .return, "teclas: mayúsculas y espacios no importan")
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7))
    let out = await handsRunner(hands).execute(name: "press_key", argumentsJSON: #"{"key":"f4"}"#)
    expect(out.output.hasPrefix("invalid_args:"), "teclas: f4 rechazada por esquema")
    expect(out.output.contains("backspace"), "teclas: el error lista las válidas")
    expect(hands.pressed.isEmpty, "teclas: nada pulsado")
    expectEq(AXTextInjector.keyCode(.return), 36, "teclas: Return es 36")
    expectEq(Set(NamedKey.allCases.map(AXTextInjector.keyCode)).count, 8, "teclas: 8 códigos distintos")
}

private func rejected(_ key: String) -> Bool {
    do {
        _ = try NamedKey.parse(key)
        return false
    } catch {
        return error.code == "invalid_args"
    }
}

/// 8.
@MainActor func testFocusWindowRaisesTheMatchingOne() async {
    let titles = ["companion-next — zsh", "Jev-voice — bash"]
    expectEq(WindowTitles.match(titles, containing: "jev"), 1, "ventana: sin mayúsculas")
    expectEq(WindowTitles.match(["Canción.txt"], containing: "cancion"), 0, "ventana: sin acentos")
    expectEq(WindowTitles.match(titles, containing: "  "), nil, "ventana: vacío no coincide")
    expectEq(WindowTitles.match(titles, containing: "safari"), nil, "ventana: ninguna")

    let hands = FakeHands(windows: titles)
    let runner = handsRunner(hands, bundle: "com.apple.Terminal")
    let out = await runner.execute(name: "focus_window", argumentsJSON: #"{"title":"Jev"}"#)
    expect(out.ok, "ventana: ok")
    expectEq(hands.raised.map(\.title), ["Jev-voice — bash"], "ventana: la que coincide")
    expectEq(hands.raised.map(\.pid), [7], "ventana: en la app de delante")
    expect(runner.approval(for: call("focus_window", #"{"title":"Jev"}"#), said: "") == nil,
           "ventana: nunca pide permiso")
    let missing = await runner.execute(name: "focus_window", argumentsJSON: #"{"title":"Xcode"}"#)
    expect(missing.output.hasPrefix("window_not_found:"), "ventana: no encontrada lo dice")
}

/// 9.
@MainActor func testTheHandsAreNotOfferedWithoutAccessibility() {
    let hands = ["type_text", "press_key", "focus_window", "read_focused"]
    let untrusted = handsRunner(FakeHands(), trusted: false)
    let names = Set(untrusted.specs(.es).map(\.name))
    expect(names.isDisjoint(with: hands), "sin AX: no se anuncian")
    expect(!hands.contains(where: untrusted.handles), "sin AX: ni se aceptan")
    let bare = ParentToolRunner(workspace: FakeWorkspaceOpener())
    expect(Set(bare.specs(.en).map(\.name)).isDisjoint(with: hands), "sin inyector: tampoco")
    expect(names.contains("open_app"), "sin AX: el resto sigue")
    let trusted = handsRunner(FakeHands())
    expect(Set(trusted.specs(.en).map(\.name)).isSuperset(of: hands), "con AX: las cuatro")
    let press = trusted.specs(.es).first { $0.name == "press_key" }
    expect(press?.description.contains("backspace") == true, "esquema: la lista cerrada va en la descripción")
}

/// 11.
@MainActor func testReadFocusedIsClippedAndNeverSecure() async {
    let long = String(repeating: "a", count: 800)
    let hands = FakeHands(field: FocusedField(app: "Notes", pid: 7), text: long)
    let out = await handsRunner(hands).execute(name: "read_focused", argumentsJSON: "{}")
    expect(out.ok, "leer: ok")
    expect(out.output.count <= FocusedText.limit + 1, "leer: recortado a 500")
    expectEq(FocusedText.limit, 500, "leer: el tope es 500")
    expectEq(FocusedText.clip("  hola \n"), "hola", "leer: sin blancos de borde")

    let secure = FakeHands(field: FocusedField(app: "Safari", pid: 7, secure: true), text: "pw")
    expect(secure.read(pid: 7) == nil, "leer: el puerto no devuelve un campo seguro")
    let refused = await handsRunner(secure).execute(name: "read_focused", argumentsJSON: "{}")
    expect(refused.output.hasPrefix("secure_field:"), "leer: seguro rechazado")
    expect(!refused.output.contains("pw"), "leer: sin el valor")
}

@MainActor func testNoFocusedFieldIsSaidPlainly() async {
    let hands = FakeHands()
    let typed = await handsRunner(hands).execute(name: "type_text", argumentsJSON: #"{"text":"a"}"#)
    expect(typed.output.hasPrefix("no_focused_field:"), "sin campo: lo dice")
    // D1 (brief manos-escribir-en-notas): with sight the error names the way
    // out; without it, menu is not offered, so naming it would mislead.
    expect(!typed.output.contains("menu"), "sin vista: no nombra una tool que no tiene")
    let sighted = ParentToolRunner(
        workspace: FakeWorkspaceOpener(),
        hands: ScreenHands(
            injector: hands, reader: hands, keys: hands, windows: hands,
            trusted: { true }, target: { 7 }, bundleID: { _ in "com.apple.Notes" }, screen: FakeScreen([])))
    let routed = await sighted.execute(name: "type_text", argumentsJSON: #"{"text":"a"}"#)
    expect(routed.output.hasPrefix("no_focused_field:"), "con vista: el mismo código")
    expect(routed.output.contains("menu") && routed.output.contains("File > New Note")
           && routed.output.contains("Archivo > Nueva nota"), "con vista: apunta a menu, en y es")
    let readSighted = await sighted.execute(name: "read_focused", argumentsJSON: "{}")
    expect(!readSighted.output.contains("menu"), "leer: no hay nada que crear")
    let read = await handsRunner(hands).execute(name: "read_focused", argumentsJSON: "{}")
    expect(read.output.hasPrefix("no_focused_field:"), "sin campo: al leer también")
    for id in ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
               "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "io.alacritty", "org.alacritty",
               "com.todesktop.230313mzl4w4u92", "com.microsoft.VSCode",
               "com.microsoft.VSCodeInsiders", "com.github.wez.wezterm", "co.zeit.hyper",
               "org.tabby", "dev.zed.Zed", "dev.warp.Warp-Preview",
               "com.anthropic.claudefordesktop", "com.openai.codex", "com.openai.chat"] {
        expect(CommandApps.isCommandApp(bundleID: id), "command app: \(id)")
    }
    expect(!CommandApps.isCommandApp(bundleID: "com.apple.Notes"), "command app: Notas no")
    expect(!CommandApps.isCommandApp(bundleID: nil), "command app: sin bundle no")
    // Review 2026-09-25 M1: the hands only ask about text nobody said, so
    // the sheet shows all of it, uncut.
    let long = String(repeating: "a", count: 300)
    expectEq(ChatCopy.approvalDetail(tool: "type_text", inputJSON: #"{"text":"\#(long)"}"#),
             long, "hoja: el texto entero, sin corte")
}

/// 5/6 por el chat escrito: la misma hoja; sí escribe, no nada.
@MainActor func testTheTypedChatAsksBeforeReturnInATerminal() async {
    let enter = ToolCallRef(id: "c1", name: "press_key", arguments: #"{"key":"return"}"#)
    for (approvals, label) in [(ApprovingApprovals() as any ApprovalsProvider, "sí"),
                               (DenyingApprovals(), "no")] {
        let hands = FakeHands(field: FocusedField(app: "Terminal", pid: 7))
        let chat = FakeChatProvider(replies: [
            .success([.toolCalls([enter])]), .success([.text("Listo.")]),
        ])
        let vm = primed(chat: chat, parentTools: handsRunner(hands, bundle: "com.apple.Terminal"),
                        approvals: approvals)
        vm.draft = "dale enter"
        vm.send()
        await pumpUntil("chat \(label): idle") { !vm.busy }
        expectEq(hands.pressed.count, label == "sí" ? 1 : 0, "chat \(label): Return tras la hoja")
    }
}
