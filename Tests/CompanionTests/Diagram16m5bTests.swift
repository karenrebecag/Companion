import AppKit
import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing
import WebKit

// Wave 16m-5b: Mermaid diagrams in the island. What the model may put in
// the fence, what the isolated page may do, and what the popup shows when the
// render fails are decided in pure code and pinned here. The real render is
// in Diagram16m5bSnapshotTests, behind COMPANION_SNAPSHOTS.

private func fence(_ body: String) -> String { "```companion:diagram\n\(body)\n```" }
private let flow = "flowchart LR\n  A[Idea] --> B{Vale la pena?}\n  B -->|si| C[Hacerlo]\n  B -->|no| D[Archivar]"

private let sourcesRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources")
private let repoRoot = sourcesRoot.deletingLastPathComponent()

// MARK: - Core: the fence

@Test func diagramFenceTests() {
    testAValidFenceBecomesADiagram()
    testDiagramRidesTheAnswerBlocks()
    testBrokenDiagramFencesStayVisibleAsCode()
    testTheDiagramByteCapIsExact()
    testHostileTextIsStrippedNotExecuted()
    testDiagramUnicodeSurvives()
    testTheVoiceKnowsADiagramIsACard()
    testTheModelIsToldWhenToDrawADiagram()
}

func testAValidFenceBecomesADiagram() {
    expectEq(CompanionBlocks.diagramLanguage, "companion:diagram", "16m-5b: la fence sigue la convención companion:*")
    expectEq(CompanionBlocks.diagram(flow)?.source, flow, "16m-5b: el cuerpo es el texto de Mermaid, sin JSON")
    expectEq(CompanionBlocks.diagram("\n\n  \(flow)\n\n")?.source, flow, "16m-5b: los blancos de los bordes no cuentan")
}

func testDiagramRidesTheAnswerBlocks() {
    let blocks = AnswerBlocks.blocks(from: "Así se ve.\n\n" + fence(flow))
    expectEq(blocks.count, 2, "16m-5b: prosa y diagrama")
    if blocks.count == 2 {
        expectEq(blocks[1], .diagram(DiagramBlock(source: flow)), "16m-5b: el bloque llega tipado")
    }
    expect(AnswerBlocks.isRich(blocks), "16m-5b: un diagrama abre el popup, no cabe en la tarjeta")
}

func testBrokenDiagramFencesStayVisibleAsCode() {
    let bad: [(String, String)] = [
        ("vacía", ""),
        ("solo blancos", "  \n\t\n "),
        ("solo una directiva", "%%{init: {\"theme\":\"dark\"}}%%"),
        ("solo frontmatter", "---\ntitle: x\n---"),
        ("solo invisibles", "\u{200B}\u{202E}"),
    ]
    for (name, body) in bad {
        expect(CompanionBlocks.diagram(body) == nil, "16m-5b: \(name) no es diagrama")
        let blocks = AnswerBlocks.blocks(from: fence(body))
        expect(!blocks.contains { if case .diagram = $0 { true } else { false } }, "16m-5b: \(name) no pinta diagrama")
        // The splitter drops a fence with nothing in it (as for every fence);
        // one with something in it must stay visible.
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
        expect(blocks.count == 1, "16m-5b: \(name) es un solo bloque")
        if case .code(let language, _)? = blocks.first {
            expectEq(language, "companion:diagram", "16m-5b: \(name) queda como código visible")
        } else { expect(false, "16m-5b: \(name) debía quedar como código") }
    }
}

func testTheDiagramByteCapIsExact() {
    let head = "flowchart LR\n"
    func body(bytes: Int) -> String { head + String(repeating: "a", count: bytes - head.utf8.count) }
    expect(CompanionBlocks.diagram(body(bytes: DiagramBlock.maxSourceBytes)) != nil, "16m-5b: justo el tope entra")
    expect(CompanionBlocks.diagram(body(bytes: DiagramBlock.maxSourceBytes + 1)) == nil, "16m-5b: un byte más, no")
    expect(CompanionBlocks.diagram(head + String(repeating: "x", count: 1 << 20)) == nil, "16m-5b: 1 MiB es nil, no se recorta")
    // Bytes, not characters: 4-byte emoji fill the cap four times faster.
    let emoji = head + String(repeating: "😀", count: DiagramBlock.maxSourceBytes / 4)
    expect(CompanionBlocks.diagram(emoji) == nil, "16m-5b: el tope cuenta bytes, no caracteres")
}

func testHostileTextIsStrippedNotExecuted() {
    // Bidi override and zero-width space: same sanitizer as every card.
    expectEq(CompanionBlocks.diagram("graph TD\n  A[\u{202E}hola\u{200B}] --> B")?.source, "graph TD\n  A[hola] --> B",
             "16m-5b: sin controles bidi ni invisibles")
    // A directive could restyle the diagram or touch the config; the page fixes both.
    let directive = "%%{init: {\"securityLevel\":\"loose\",\"theme\":\"default\"}}%%\ngraph TD\n  A --> B"
    expectEq(CompanionBlocks.diagram(directive)?.source, "graph TD\n  A --> B", "16m-5b: las directivas init se quitan")
    let multiline = "%%{\n init: {\n \"securityLevel\": \"loose\" }\n}%%\ngraph TD\n  A --> B"
    expectEq(CompanionBlocks.diagram(multiline)?.source, "graph TD\n  A --> B", "16m-5b: también la directiva de varias líneas")
    let front = "---\nconfig:\n  theme: forest\n---\ngraph TD\n  A --> B"
    expectEq(CompanionBlocks.diagram(front)?.source, "graph TD\n  A --> B", "16m-5b: el frontmatter se quita")
    // Callbacks and links from the model are behavior, not drawing.
    let click = "graph TD\n  A --> B\n  click A callback \"tip\"\n  CLICK B href \"https://evil.example\"\n  C --> D"
    expectEq(CompanionBlocks.diagram(click)?.source, "graph TD\n  A --> B\n  C --> D", "16m-5b: las líneas click se quitan")
    // HTML is data: it stays in the text (the page never parses it as markup).
    let html = "graph TD\n  A[\"<img src=x onerror=alert(1)>\"] --> B"
    expectEq(CompanionBlocks.diagram(html)?.source, html, "16m-5b: el HTML viaja como texto; la CSP y strict lo neutralizan")
    // Not every mention of the word click is an interaction.
    let word = "graph TD\n  A[click here] --> B"
    expectEq(CompanionBlocks.diagram(word)?.source, word, "16m-5b: un nodo que dice click no es una interacción")
}

func testDiagramUnicodeSurvives() {
    let text = "sequenceDiagram\n  participant 猫 as 🐈 Gato\n  猫->>Ana: ¿Café? ñ ü"
    expectEq(CompanionBlocks.diagram(text)?.source, text, "16m-5b: CJK, emoji y acentos pasan")
    let sql = "graph TD\n  A[\"'; DROP TABLE x;--\"] --> B"
    expectEq(CompanionBlocks.diagram(sql)?.source, sql, "16m-5b: metacaracteres de SQL son texto")
}

func testTheVoiceKnowsADiagramIsACard() {
    expect(SpeechBudget.hasCard(in: "Mira.\n" + fence(flow)), "16m-5b: la voz no lee un diagrama en voz alta")
    expect(!SpeechBudget.hasCard(in: "Mira.\n" + fence("")), "16m-5b: una fence rota es código, la voz no acorta por ella")
}

func testTheModelIsToldWhenToDrawADiagram() {
    for (language, words) in [(AppLanguage.en, ["Mermaid", "flowchart"]), (.es, ["Mermaid", "flowchart"])] {
        let text = CardVocabulary.text(language)
        expect(text.contains(CompanionBlocks.diagramLanguage), "16m-5b: \(language) enseña la fence")
        for word in words { expect(text.contains(word), "16m-5b: \(language) menciona \(word)") }
        expect(text.contains("\(DiagramBlock.maxSourceBytes / 1024) KiB"), "16m-5b: \(language) dice el tope")
        expect(text.contains("%%{"), "16m-5b: \(language) prohíbe las directivas")
    }
}

// MARK: - Core: the isolated page

@Test func diagramPageTests() {
    testTheCSPAllowsOnlyTheLocalScripts()
    testThePageEmbedsNoDiagramText()
    testMermaidRunsStrictWithIncrediblesTheme()
    testOnlyTheInitialBlankNavigationIsAllowed()
    testTheNetworkRulesBlockEveryRemoteScheme()
    testTheDataEntersAsAnArgumentNeverAsCode()
}

private func hashes(of vendor: String) -> [String] {
    [DiagramPage.cspHash(vendor), DiagramPage.cspHash(DiagramPage.bootstrapScript)]
}

func testTheCSPAllowsOnlyTheLocalScripts() {
    let csp = DiagramPage.contentSecurityPolicy(scriptHashes: ["sha256-AAA", "sha256-BBB"])
    let directives = Dictionary(uniqueKeysWithValues: csp.split(separator: ";").map { part -> (String, String) in
        let pieces = part.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1).map(String.init)
        return (pieces[0], pieces.count > 1 ? pieces[1] : "")
    })
    expectEq(directives["default-src"], "'none'", "16m-5b: todo cerrado por defecto")
    expectEq(directives["script-src"], "'sha256-AAA' 'sha256-BBB'", "16m-5b: solo los scripts locales por hash")
    for name in ["connect-src", "img-src", "font-src", "media-src", "object-src", "frame-src", "worker-src", "form-action", "base-uri"] {
        expectEq(directives[name], "'none'", "16m-5b: \(name) cerrado")
    }
    expectEq(directives["style-src"], "'unsafe-inline'", "16m-5b: estilos en línea (Mermaid los pone en el SVG), nada más")
    expect(!csp.contains("unsafe-eval"), "16m-5b: sin eval")
    expect(!csp.contains("http") && !csp.contains("*") && !csp.contains("data:"), "16m-5b: ningún origen abierto")
    expect(!(directives["script-src"] ?? "").contains("unsafe-inline"), "16m-5b: un onerror del modelo no corre")
}

func testThePageEmbedsNoDiagramText() {
    let page = DiagramPage.html(vendorScript: "/*vendor*/")
    expect(page.contains("<meta http-equiv=\"Content-Security-Policy\""), "16m-5b: la CSP va en la página")
    expect(page.contains(DiagramPage.contentSecurityPolicy(scriptHashes: hashes(of: "/*vendor*/"))),
           "16m-5b: la CSP lleva exactamente los hashes de lo que la página incrusta")
    expect(page.contains("/*vendor*/") && page.contains(DiagramPage.bootstrapScript), "16m-5b: incrusta el vendor y el arranque")
    expect(!page.contains("src=") && !page.contains("href="), "16m-5b: la página no carga nada por URL")
    expect(page.contains("id=\"out\""), "16m-5b: hay dónde pintar")
    expect(DiagramPage.html(vendorScript: "a") != DiagramPage.html(vendorScript: "b"), "16m-5b: el vendor cambia la página")
}

func testMermaidRunsStrictWithIncrediblesTheme() {
    guard let data = DiagramPage.configJSON.data(using: .utf8),
          let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let vars = config["themeVariables"] as? [String: Any]
    else { return expect(false, "16m-5b: la configuración debe ser JSON") }
    expectEq(config["securityLevel"] as? String, "strict", "16m-5b: securityLevel strict (Incredible: strict)")
    expectEq(config["startOnLoad"] as? Bool, false, "16m-5b: nada se pinta solo")
    expectEq(config["theme"] as? String, "base", "16m-5b: tema base como Incredible")
    expectEq(vars["darkMode"] as? Bool, true, "16m-5b: la isla es oscura")
    expectEq(vars["background"] as? String, "transparent", "16m-5b: fondo transparente sobre el contenedor visual")
    expectEq(vars["fontSize"] as? String, "13px", "16m-5b: 13 px como Incredible")
    expectEq(vars["primaryColor"] as? String, "#1e1e26", "16m-5b: nodo, valor de Incredible")
    expectEq(vars["lineColor"] as? String, "rgba(255, 255, 255, 0.32)", "16m-5b: línea, valor de Incredible")
    expectEq(vars["primaryTextColor"] as? String, "rgba(255, 255, 255, 0.94)", "16m-5b: texto, valor de Incredible")
    expectEq((config["flowchart"] as? [String: Any])?["curve"] as? String, "basis", "16m-5b: curvas basis")
    expectEq((config["flowchart"] as? [String: Any])?["padding"] as? Int, 14, "16m-5b: padding 14")
    expectEq((config["sequence"] as? [String: Any])?["mirrorActors"] as? Bool, false, "16m-5b: sin actores espejo")
    expect(DiagramPage.bootstrapScript.contains(DiagramPage.configJSON), "16m-5b: el arranque usa esa configuración")
}

func testOnlyTheInitialBlankNavigationIsAllowed() {
    expect(DiagramPage.allowsNavigation(to: URL(string: "about:blank")), "16m-5b: la carga inicial pasa")
    for raw in ["https://evil.example/x", "http://a.b", "file:///etc/passwd", "javascript:alert(1)",
                "data:text/html,<script>1</script>", "ftp://a.b/c", "about:srcdoc", "custom-scheme://x", "mailto:a@b.c"] {
        expect(!DiagramPage.allowsNavigation(to: URL(string: raw)), "16m-5b: \(raw) no navega")
    }
    expect(!DiagramPage.allowsNavigation(to: nil), "16m-5b: sin URL no navega")
}

func testTheNetworkRulesBlockEveryRemoteScheme() {
    guard let data = DiagramPage.blockNetworkRules.data(using: .utf8),
          let rules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    else { return expect(false, "16m-5b: las reglas deben ser JSON de reglas de contenido") }
    expectEq(rules.count, 1, "16m-5b: una regla")
    let trigger = rules.first?["trigger"] as? [String: Any]
    let filter = trigger?["url-filter"] as? String ?? ""
    for url in ["http://a.b/x.js", "https://a.b/x.png", "ws://a.b", "wss://a.b", "ftp://a.b", "file:///etc/hosts"] {
        expect(url.range(of: filter, options: .regularExpression) != nil, "16m-5b: la regla alcanza \(url)")
    }
    expect("about:blank".range(of: filter, options: .regularExpression) == nil, "16m-5b: la página propia no se bloquea")
    expectEq((rules.first?["action"] as? [String: Any])?["type"] as? String, "block", "16m-5b: bloquea")
}

func testTheDataEntersAsAnArgumentNeverAsCode() {
    expect(DiagramPage.renderCall.contains("renderDiagram(source)"), "16m-5b: el texto entra como el argumento `source`")
    expect(!DiagramPage.renderCall.contains("\\("), "16m-5b: ninguna interpolación")
    let boot = DiagramPage.bootstrapScript
    expect(boot.contains("window.renderDiagram"), "16m-5b: el arranque expone la única entrada")
    expect(boot.contains("mermaid.parse"), "16m-5b: se valida antes de pintar")
    expect(!boot.contains("eval(") && !boot.contains("new Function"), "16m-5b: el arranque no evalúa texto")
}

// MARK: - Core: the timeout

@MainActor
@Test func diagramTimeoutTests() async {
    let fast = await DiagramTimeout.run(after: .seconds(2)) { 42 }
    expectEq(fast, 42, "16m-5b: lo que termina a tiempo se entrega")
    let start = ContinuousClock.now
    let slow: Int? = await DiagramTimeout.run(after: .milliseconds(80)) {
        do { try await Task.sleep(for: .seconds(30)) } catch { return -1 }
        return 1
    }
    expectEq(slow, nil, "16m-5b: lo que no termina devuelve nil")
    expect(ContinuousClock.now - start < .seconds(3), "16m-5b: el timeout no espera al trabajo colgado")
    let late: Int? = await DiagramTimeout.run(after: .milliseconds(20)) {
        do { try await Task.sleep(for: .milliseconds(200)) } catch { return -1 }
        return 7
    }
    expectEq(late, nil, "16m-5b: la respuesta tardía se descarta, no se entrega dos veces")
}

// MARK: - The vendored script

@Test func diagramVendorTests() {
    let dir = sourcesRoot.appendingPathComponent("CompanionServices/Diagram")
    let script = try? Data(contentsOf: dir.appendingPathComponent("mermaid.min.js"))
    expect(script != nil, "16m-5b: mermaid.min.js vive en el repo")
    if let script {
        expectEq(DiagramPage.sha256Hex(script), DiagramPage.mermaidSHA256, "16m-5b: el archivo es el que fija el SHA-256")
        expect(script.count > 1_000_000, "16m-5b: es el bundle completo, no un stub")
    }
    let note = (try? String(contentsOf: dir.appendingPathComponent("VENDOR.md"), encoding: .utf8)) ?? ""
    expect(note.contains(DiagramPage.mermaidVersion), "16m-5b: VENDOR.md dice la versión")
    expect(note.contains(DiagramPage.mermaidSHA256), "16m-5b: VENDOR.md dice el SHA-256")
    expect(note.contains("npm pack mermaid@\(DiagramPage.mermaidVersion)"), "16m-5b: VENDOR.md dice cómo se obtuvo")
    let license = (try? String(contentsOf: dir.appendingPathComponent("LICENSE"), encoding: .utf8)) ?? ""
    expect(license.contains("MIT License") && license.contains("Knut Sveidqvist"), "16m-5b: la licencia MIT viaja con el archivo")
    let manifest = (try? String(contentsOf: repoRoot.appendingPathComponent("Package.swift"), encoding: .utf8)) ?? ""
    expect(manifest.contains(".copy(\"Diagram\")"), "16m-5b: Package.swift copia el recurso")
    expect(!manifest.contains(".package("), "16m-5b: ninguna dependencia de SwiftPM (mermaid es un archivo vendoreado)")
    expect(!FileManager.default.fileExists(atPath: repoRoot.appendingPathComponent("package.json").path),
           "16m-5b: sin package.json ni node_modules")
    expectEq(DiagramPage.sha256Hex(Data("abc".utf8)),
             "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "16m-5b: SHA-256 de referencia")
}

// MARK: - Services: the web view

@MainActor
@Test func diagramWebViewTests() {
    let config = WebKitDiagramRenderer.makeConfiguration()
    expect(!config.websiteDataStore.isPersistent, "16m-5b: sin disco, cookies ni caché")
    expect(!config.preferences.javaScriptCanOpenWindowsAutomatically, "16m-5b: no abre ventanas")
    expect(config.defaultWebpagePreferences.allowsContentJavaScript, "16m-5b: Mermaid necesita JS")
    expect(config.mediaTypesRequiringUserActionForPlayback == .all, "16m-5b: nada suena ni se reproduce")
    expect(!config.preferences.isElementFullscreenEnabled, "16m-5b: sin pantalla completa")
    expect(!config.preferences.isTextInteractionEnabled, "16m-5b: sin selección")
    expect(config.userContentController.userScripts.isEmpty, "16m-5b: nada inyectado fuera de la página")
    expect(WebKitDiagramRenderer.vendoredScript() != nil, "16m-5b: el script vendoreado se encuentra en el bundle y coincide con el SHA fijado")
    expect(WebKitDiagramRenderer.verified(Data("tampered".utf8)) == nil, "16m-5b: un script que no es el fijado no se carga")
}

// MARK: - UI: the load and the fallback

@MainActor
final class FakeDiagramRenderer: DiagramRendering {
    var outcome: DiagramOutcome
    private(set) var calls: [(DiagramBlock, Double)] = []
    init(_ outcome: DiagramOutcome) { self.outcome = outcome }
    func render(_ block: DiagramBlock, width: Double) async -> DiagramOutcome {
        calls.append((block, width))
        return outcome
    }
}

private let image = DiagramImage(data: Data([1, 2, 3]), width: 504, height: 120)

@MainActor
@Test func diagramModelTests() async {
    let block = DiagramBlock(source: flow)
    let model = IslandDiagramModel()
    expectEq(model.state, .loading, "16m-5b: nace cargando")
    let ok = FakeDiagramRenderer(.image(image))
    await model.load(block, renderer: ok, width: 504)
    expectEq(model.state, .image(image), "16m-5b: la imagen llega")
    expectEq(ok.calls.count, 1, "16m-5b: un render")
    expectEq(ok.calls.first?.0, block, "16m-5b: se renderiza el bloque, no otro texto")
    expectEq(ok.calls.first?.1, 504, "16m-5b: al ancho pedido")

    for failure in [DiagramFailure.invalid, .timeout, .unavailable] {
        let m = IslandDiagramModel()
        await m.load(block, renderer: FakeDiagramRenderer(.failed(failure)), width: 504)
        expectEq(m.state, .failed(failure), "16m-5b: \(failure) cae a código, no a error mudo")
    }
    let none = IslandDiagramModel()
    await none.load(block, renderer: nil, width: 504)
    expectEq(none.state, .failed(.unavailable), "16m-5b: sin renderer, el texto se muestra como código")
}

@MainActor
@Test func diagramModelIdempotenceTests() async {
    let block = DiagramBlock(source: flow)
    let renderer = FakeDiagramRenderer(.image(image))
    let model = IslandDiagramModel()
    await model.load(block, renderer: renderer, width: 504)
    await model.load(block, renderer: renderer, width: 504)
    expectEq(renderer.calls.count, 1, "16m-5b: SwiftUI puede repetir la tarea; el mismo diagrama se dibuja una vez")
    expectEq(model.state, .image(image), "16m-5b: y la imagen no se pierde en el repetido")
    await model.load(DiagramBlock(source: "graph TD\n  X --> Y"), renderer: renderer, width: 504)
    expectEq(renderer.calls.count, 2, "16m-5b: otro texto sí se dibuja")
    // A failure is worth asking again: the renderer may have recovered.
    let flaky = FakeDiagramRenderer(.failed(.timeout))
    let retry = IslandDiagramModel()
    await retry.load(block, renderer: flaky, width: 504)
    flaky.outcome = .image(image)
    await retry.load(block, renderer: flaky, width: 504)
    expectEq(retry.state, .image(image), "16m-5b: tras un fallo, volver a pedir reintenta")
}

@MainActor
@Test func diagramTextsAndMetricsTests() {
    for key in ["island.diagram.label", "island.diagram.failed", "island.diagram.timeout", "island.diagram.loading"] {
        for language in [AppLanguage.en, .es] {
            let text = Localized.string(key, language: language)
            expect(text != key && !text.isEmpty, "16m-5b: \(key) está en \(language)")
        }
    }
    // WebKit paints a PDF on white whatever the page says, so the page paints
    // the container's own fill: 5 % white over the popup's rgb(14,14,16).
    let blend = { (channel: Double) in Int((channel * 255 * (1 - IslandVisualMetrics.fill) + 255 * IslandVisualMetrics.fill).rounded()) }
    expectEq(DiagramPage.surface, "rgb(\(blend(14 / 255)), \(blend(14 / 255)), \(blend(16 / 255)))",
             "16m-5b: la página pinta el relleno del contenedor visual, para que la imagen no se note")
    expect(DiagramPage.html(vendorScript: "x").contains("background:\(DiagramPage.surface)"), "16m-5b: la página usa ese relleno")
}
