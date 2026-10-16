import CompanionCore
import CompanionCoreTestSupport
import CompanionServices
import CompanionServicesTestSupport
import CompanionTestKit
import Foundation
import Testing

// Wave 10b. El runner del padre: sin aprobación, sin Process; todo por el
// puerto `WorkspaceOpening`, que aquí no abre nada.
@Test @MainActor func parentToolRunnerTests() async throws {
    await testOpenAppOpensKnownApp()
    await testOpenAppUnknownListsCandidates()
    await testOpenURLDeniesFileScheme()
    await testOpenFileDeniesHidden()
    try await testOpenFileOpensFileURL()
    try await testOpenFileRefusesLaunchers()
    await testListAppsCapsAt100()
    await testUnknownToolAndBadJSON()
    testSpecsFollowBacking()
    await testRealOpenerFindsSafari()
    await testReadSkillByNameOnly()
    await testShowCardPutsTheChartOnTheChannel()
}

@MainActor func testOpenAppOpensKnownApp() async {
    let opener = FakeWorkspaceOpener(installed: ["Safari", "Notes"], running: ["Finder"])
    let runner = ParentToolRunner(workspace: opener)
    let out = await runner.execute(name: "open_app", argumentsJSON: #"{"name":"safari"}"#)
    expect(out.ok, "open_app: ok")
    expectEq(opener.openedApps, ["Safari"], "open_app: abre la instalada con su nombre exacto")
    expect(out.output.contains("opened Safari"), "open_app: el modelo lee qué se abrió")
    expectEq(out.target, "Safari", "open_app: la línea de estado nombra la app")
    let running = await runner.execute(name: "open_app", argumentsJSON: #"{"name":"Finder"}"#)
    expect(running.ok, "open_app: una app corriendo también cuenta")
}

@MainActor func testOpenAppUnknownListsCandidates() async {
    let opener = FakeWorkspaceOpener(
        installed: ["Safari", "Safari Technology Preview", "Slack", "Notes"], running: [])
    let runner = ParentToolRunner(workspace: opener)
    let out = await runner.execute(name: "open_app", argumentsJSON: #"{"name":"Safar"}"#)
    expect(!out.ok, "open_app: desconocida falla")
    expect(out.output.hasPrefix("not_found:"), "open_app: código estable primero")
    expect(out.output.contains("Safari"), "open_app: lista candidatos")
    expect(!out.output.contains("Notes"), "open_app: no lista lo que no se parece")
    expect(opener.openedApps.isEmpty, "open_app: no abrió nada")
}

@MainActor func testOpenURLDeniesFileScheme() async {
    let opener = FakeWorkspaceOpener()
    let runner = ParentToolRunner(workspace: opener)
    let out = await runner.execute(
        name: "open_url", argumentsJSON: #"{"url":"file:///etc/passwd"}"#)
    expect(!out.ok, "open_url: file:// falla")
    expect(out.output.hasPrefix("denied_url:"), "open_url: código denied_url")
    expect(opener.openedURLs.isEmpty, "open_url: el opener NO fue llamado")
    let ok = await runner.execute(
        name: "open_url", argumentsJSON: #"{"url":"http://192.168.1.1"}"#)
    expect(ok.ok, "open_url: http a un host cualquiera es legítimo (no es EndpointPolicy)")
    expectEq(opener.openedURLs.map(\.absoluteString), ["http://192.168.1.1"],
             "open_url: abre la URL normalizada")
}

@MainActor func testOpenFileDeniesHidden() async {
    let opener = FakeWorkspaceOpener()
    let fx = try? HomeFixture()
    let runner = ParentToolRunner(
        workspace: opener, home: fx?.home ?? URL(fileURLWithPath: "/nonexistent"))
    let out = await runner.execute(name: "open_file", argumentsJSON: #"{"path":"~/.zshrc"}"#)
    expect(!out.ok, "open_file: oculto falla")
    expect(out.output.hasPrefix("denied_path:"), "open_file: código denied_path")
    expect(opener.openedURLs.isEmpty, "open_file: el opener NO fue llamado")
}

@MainActor func testOpenFileOpensFileURL() async throws {
    let opener = FakeWorkspaceOpener()
    let fx = try HomeFixture()
    try fx.touch("notes.md")
    let runner = ParentToolRunner(workspace: opener, home: fx.home)
    let out = await runner.execute(name: "open_file", argumentsJSON: #"{"path":"~/notes.md"}"#)
    expect(out.ok, "open_file: ok")
    expectEq(opener.openedURLs.map(\.path),
             [fx.canonical.appendingPathComponent("notes.md").path],
             "open_file: abre la ruta canónica como file URL")
    expect(opener.openedURLs.first?.isFileURL == true, "open_file: es file://")
}

@MainActor func testOpenFileRefusesLaunchers() async throws {
    let opener = FakeWorkspaceOpener()
    let fx = try HomeFixture()
    try fx.mkdir("Downloads")
    try fx.touch("Downloads/update.command")
    try fx.touch("Downloads/site.webloc")
    let runner = ParentToolRunner(workspace: opener, home: fx.home)
    for path in ["~/Downloads/update.command", "~/Downloads/site.webloc"] {
        let out = await runner.execute(name: "open_file", argumentsJSON: "{\"path\":\"\(path)\"}")
        expect(!out.ok && out.output.hasPrefix("denied_path:"), "open_file: \(path) se niega")
    }
    expect(opener.openedURLs.isEmpty, "open_file: el opener NO fue llamado con un lanzador")
}

@MainActor func testListAppsCapsAt100() async {
    let installed = (1 ... 250).map { "App \($0)" }
    let opener = FakeWorkspaceOpener(installed: installed, running: ["App 3"])
    let runner = ParentToolRunner(workspace: opener)
    let out = await runner.execute(name: "list_apps", argumentsJSON: "{}")
    expect(out.ok, "list_apps: ok")
    let lines = out.output.split(separator: "\n").filter { $0.hasPrefix("- ") }
    expectEq(lines.count, 100, "list_apps: tope 100 entradas")
    expect(out.output.contains("150"), "list_apps: dice cuántas quedaron fuera")
    expect(out.output.contains("App 3") && out.output.contains("running"),
           "list_apps: las que corren van marcadas")
}

@MainActor func testUnknownToolAndBadJSON() async {
    let runner = ParentToolRunner(workspace: FakeWorkspaceOpener())
    expect(!runner.handles("run_shell"), "handles: run_shell nunca es del padre")
    expect(runner.handles("open_app"), "handles: open_app sí")
    let bad = await runner.execute(name: "open_app", argumentsJSON: "{not json")
    expect(!bad.ok && bad.output.hasPrefix("invalid_args:"),
           "execute: JSON roto es invalid_args, no [:] silencioso")
    // Review 2026-09-25 L2: the raw arguments can carry text for another
    // app; the model gets the size and what to send instead.
    expect(!bad.output.contains("{not json") && bad.output.contains("9 chars"),
           "execute: el tamaño, nunca el crudo")
    let missing = await runner.execute(name: "open_app", argumentsJSON: "{}")
    expect(!missing.ok && missing.output.hasPrefix("invalid_args:"),
           "execute: falta el argumento → invalid_args")
}

/// Una tool sin respaldo no se anuncia (misma regla que NativeToolRunner).
@MainActor func testSpecsFollowBacking() {
    let bare = ParentToolRunner(workspace: FakeWorkspaceOpener())
    expectEq(bare.specs(.en).map(\.name), ["open_app", "open_url", "open_file", "list_apps", "show_card"],
             "specs: sin PlacesSearching no hay find_places")
    let withPlaces = ParentToolRunner(
        workspace: FakeWorkspaceOpener(), places: FakePlaces(found: []))
    expect(withPlaces.specs(.es).map(\.name).contains("find_places"),
           "specs: con PlacesSearching se ofrece find_places al padre")
    expect(withPlaces.handles("find_places"), "handles: find_places con respaldo")
    expect(!bare.handles("find_places"), "handles: find_places sin respaldo no")
    expect(bare.specs(.es).allSatisfy { !$0.description.isEmpty },
           "specs: descripciones en español")
}

/// Visto en uso real (2026-09-05): "abre Safari" → `not_found`. En macOS 26
/// `/Applications/Safari.app` es un symlink a un cryptex y la enumeración del
/// directorio no lo devuelve; `stat` sí. Depende de la máquina a propósito:
/// es la pregunta "¿ve el adapter lo que el Finder ve?".
@MainActor func testRealOpenerFindsSafari() async {
    guard FileManager.default.fileExists(atPath: "/Applications/Safari.app") else { return }
    let opener = NSWorkspaceOpener()
    expect(opener.installedApplications().contains("Safari"),
           "opener real: Safari aparece entre las instaladas")
    let runner = ParentToolRunner(workspace: ProbeOnlyOpener(real: opener))
    let out = await runner.execute(name: "open_app", argumentsJSON: #"{"name":"safari"}"#)
    expect(out.ok, "opener real: open_app resuelve Safari sin abrirlo (\(out.output))")
}

/// Lista con el adapter real, abre con el fake: el test no lanza Safari.
private struct ProbeOnlyOpener: WorkspaceOpening {
    let real: NSWorkspaceOpener
    func openApplication(named name: String) async throws(ContractError) {}
    func open(_ url: URL) async throws(ContractError) {}
    func runningApplications() -> [String] { real.runningApplications() }
    func installedApplications() -> [String] { real.installedApplications() }
}

// MARK: - Wave 11a: el padre lee una skill por nombre

@MainActor func testReadSkillByNameOnly() async {
    let opener = FakeWorkspaceOpener()
    let card = SkillCard(name: "writing-content", description: "Writes. Use when writing.",
                         path: "/x/writing-content/SKILL.md", kind: .skill, origin: .system)
    let reader = FakeSkillReader(cards: [card], bodies: ["writing-content": "# Write well\nShort."])
    let bare = ParentToolRunner(workspace: opener)
    expect(!bare.handles("read_skill") && !bare.specs(.en).map(\.name).contains("read_skill"),
           "read_skill: sin catálogo no se anuncia — una tool sin respaldo captura la intención y muere")
    let runner = ParentToolRunner(workspace: opener, skills: reader)
    expect(runner.handles("read_skill") && runner.specs(.es).map(\.name).contains("read_skill"),
           "read_skill: con catálogo se anuncia")
    let out = await runner.execute(name: "read_skill", argumentsJSON: #"{"name":"writing-content"}"#)
    expect(out.ok, "read_skill: ok")
    expect(out.output.contains("# Write well"), "read_skill: devuelve el cuerpo")
    expectEq(out.target, "writing-content", "read_skill: la línea de estado nombra la skill")
    expectEq(ParentToolCopy.status("read_skill", out, .en), "Read the writing-content skill.", "read_skill: estado en")
    expectEq(ParentToolCopy.status("read_skill", out, .es), "Leí la skill writing-content.", "read_skill: estado es")
    let unknown = await runner.execute(name: "read_skill", argumentsJSON: #"{"name":"nope"}"#)
    expect(!unknown.ok && unknown.output.hasPrefix("not_found:"), "read_skill: desconocida → not_found")
    // Code review 2026-09-06: el fallo genérico decía "Could not open" para una lectura.
    expect(ParentToolCopy.status("read_skill", unknown, .en).hasPrefix("Could not read the nope skill:"),
           "read_skill: el fallo habla de leer, no de abrir — got: \(ParentToolCopy.status("read_skill", unknown, .en))")
    expect(ParentToolCopy.status("read_skill", unknown, .es).hasPrefix("No pude leer la skill nope:"),
           "read_skill: fallo es")
    let path = await runner.execute(name: "read_skill", argumentsJSON: #"{"name":"../../etc/passwd"}"#)
    expect(!path.ok && path.output.hasPrefix("not_found:"), "read_skill: una ruta no es un nombre")
    expect(reader.bodies["../../etc/passwd"] == nil, "read_skill: ni se consulta")
    let missing = await runner.execute(name: "read_skill", argumentsJSON: #"{}"#)
    expect(missing.output.hasPrefix("invalid_args:"), "read_skill: sin name → invalid_args")
    reader.bodies["writing-content"] = String(repeating: "x", count: 60_000)
    let big = await runner.execute(name: "read_skill", argumentsJSON: #"{"name":"writing-content"}"#)
    expect(big.output.unicodeScalars.count < 41_000 && big.output.hasSuffix("…"),
           "read_skill: un cuerpo enorme se corta visible")
}

/// Karen 2026-10-06: the fast brain left chart fences unclosed and the card
/// never painted. The tool call lands the chart on the card channel whole.
@MainActor func testShowCardPutsTheChartOnTheChannel() async {
    let runner = ParentToolRunner(workspace: FakeWorkspaceOpener())
    let out = await runner.execute(name: "show_card", argumentsJSON: #"""
        {"card":"chart","title":"Ventas","kind":"bar","labels":["Ene","Feb"],
         "series":[{"name":"MXN","values":[120,150]}]}
        """#)
    expect(out.ok, "show_card: ok")
    guard case .chart(let chart)? = out.card?.payload else {
        expect(false, "show_card: la gráfica viaja en card, no en el texto")
        return
    }
    expectEq(chart.labels, ["Ene", "Feb"], "show_card: etiquetas intactas")
    expect(!out.output.contains("150"), "show_card: el modelo no recibe los números para leerlos")
    let bad = await runner.execute(name: "show_card", argumentsJSON: #"{"card":"chart","labels":["a"]}"#)
    expect(!bad.ok && bad.card == nil, "show_card: datos rotos fallan sin pintar nada")
    expect(bad.output.hasPrefix("invalid_args:"), "show_card: código estable para reintentar")
}
