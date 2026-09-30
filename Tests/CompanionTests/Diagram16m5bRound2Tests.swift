import AppKit
import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import Foundation
import Testing
import WebKit

// Wave 16m-5b, review round: cancellation, dedupe and serialization of the
// renderer's queue; the wiring of the real page's isolation; the sanitizer's
// corners; and the fallbacks. Each test names the mutation it exists to kill.

private let flow = "flowchart LR\n  A[Idea] --> B{Vale la pena?}"
private let pic = DiagramImage(data: Data([1]), width: 504, height: 40)

@MainActor
private final class DrawProbe {
    var draws: [String] = []
    var live = 0
    var maxLive = 0
    var cancelledSeen = 0
    var delay: Duration = .milliseconds(60)
    var outcome: DiagramOutcome = .image(pic)

    var draw: DiagramScheduler.Draw {
        { [self] block, _ in
            draws.append(block.source)
            live += 1
            maxLive = max(maxLive, live)
            defer { live -= 1 }
            do { try await Task.sleep(for: delay) } catch {
                cancelledSeen += 1
                return .failed(.unavailable)
            }
            return outcome
        }
    }
}

private func block(_ text: String) -> DiagramBlock { DiagramBlock(source: "flowchart LR\n  \(text)") }
private func isImage(_ outcome: DiagramOutcome) -> Bool { if case .image = outcome { true } else { false } }

// MARK: - Scheduler

@MainActor
@Test func diagramSchedulerTests() async {
    await watched(60, "diagramSchedulerTests") {
        // Kills: no dedupe of identical in-flight requests.
        let probe = DrawProbe()
        let scheduler = DiagramScheduler(draw: probe.draw)
        async let a = scheduler.render(block("A --> B"), width: 504)
        async let b = scheduler.render(block("A --> B"), width: 504)
        let both = await [a, b]
        expect(both.allSatisfy(isImage), "16m-5b r2: los dos esperan la misma imagen")
        expectEq(probe.draws.count, 1, "16m-5b r2: dos peticiones idénticas en vuelo dibujan una vez")

        // Kills: removing the serial queue (two pages alive at once).
        let serial = DrawProbe()
        let queue = DiagramScheduler(draw: serial.draw)
        async let c = queue.render(block("A --> B"), width: 504)
        async let d = queue.render(block("C --> D"), width: 504)
        let two = await [c, d]
        expect(two.allSatisfy(isImage), "16m-5b r2: ambos dan imagen")
        expectEq(serial.draws.count, 2, "16m-5b r2: fuentes distintas dibujan cada una")
        expectEq(serial.maxLive, 1, "16m-5b r2: nunca más de una página viva a la vez")

        // Same text at another width is another picture.
        let widths = DrawProbe()
        let wide = DiagramScheduler(draw: widths.draw)
        _ = await wide.render(block("A --> B"), width: 504)
        _ = await wide.render(block("A --> B"), width: 300)
        expectEq(widths.draws.count, 2, "16m-5b r2: otro ancho, otro dibujo")
    }
}

@MainActor
@Test func diagramSchedulerCacheTests() async {
    await watched(60, "diagramSchedulerCacheTests") {
        let probe = DrawProbe()
        let scheduler = DiagramScheduler(draw: probe.draw)
        _ = await scheduler.render(block("A --> B"), width: 504)
        _ = await scheduler.render(block("A --> B"), width: 504)
        expectEq(probe.draws.count, 1, "16m-5b r2: una imagen se cachea")

        // Invalid is deterministic: asking again would only redraw the same refusal.
        let bad = DrawProbe()
        bad.outcome = .failed(.invalid)
        let refusing = DiagramScheduler(draw: bad.draw)
        _ = await refusing.render(block("X"), width: 504)
        _ = await refusing.render(block("X"), width: 504)
        expectEq(bad.draws.count, 1, "16m-5b r2: .invalid se cachea, es determinista")

        // A timeout or an unavailable page may recover: never cached.
        for failure in [DiagramFailure.unavailable] {
            let flaky = DrawProbe()
            flaky.outcome = .failed(failure)
            let s = DiagramScheduler(draw: flaky.draw)
            _ = await s.render(block("X"), width: 504)
            _ = await s.render(block("X"), width: 504)
            expectEq(flaky.draws.count, 2, "16m-5b r2: \(failure) no se cachea")
        }

        // The cache is bounded.
        let many = DrawProbe()
        many.delay = .milliseconds(1)
        let bounded = DiagramScheduler(draw: many.draw)
        for index in 0 ... DiagramScheduler.cacheLimit + 1 { _ = await bounded.render(block("N\(index) --> M"), width: 504) }
        _ = await bounded.render(block("N0 --> M"), width: 504)
        expectEq(many.draws.count, DiagramScheduler.cacheLimit + 3, "16m-5b r2: el más viejo salió de la caché")
    }
}

@MainActor
@Test func diagramSchedulerCancellationTests() async {
    await watched(60, "diagramSchedulerCancellationTests") {
        // Kills: a cancelled caller that still holds the queue for the whole draw.
        let probe = DrawProbe()
        probe.delay = .seconds(20)
        let scheduler = DiagramScheduler(draw: probe.draw)
        let running = Task { await scheduler.render(block("A --> B"), width: 504) }
        try? await Task.sleep(for: .milliseconds(150))
        running.cancel()
        let started = ContinuousClock.now
        _ = await running.value
        expect(ContinuousClock.now - started < .seconds(2), "16m-5b r2: cancelar suelta al que espera enseguida")
        expectEq(probe.cancelledSeen, 1, "16m-5b r2: la cancelación llega al dibujo en curso")
        probe.delay = .milliseconds(20)
        let next = await scheduler.render(block("C --> D"), width: 504)
        expect(isImage(next), "16m-5b r2: la cola no se quedó ocupada 20 s")
        expect(ContinuousClock.now - started < .seconds(4), "16m-5b r2: el siguiente empieza ya")

        // Kills: a queued job that draws after its caller left.
        let busy = DrawProbe()
        busy.delay = .milliseconds(400)
        let q = DiagramScheduler(draw: busy.draw)
        let first = Task { await q.render(block("A --> B"), width: 504) }
        try? await Task.sleep(for: .milliseconds(50))
        let queued = Task { await q.render(block("Q --> R"), width: 504) }
        try? await Task.sleep(for: .milliseconds(50))
        queued.cancel()
        _ = await queued.value
        _ = await first.value
        try? await Task.sleep(for: .milliseconds(600))
        expectEq(busy.draws.count, 1, "16m-5b r2: lo encolado y cancelado nunca dibuja")

        // Kills: cancelling the shared draw when only ONE of two waiters leaves.
        let shared = DrawProbe()
        shared.delay = .milliseconds(500)
        let s = DiagramScheduler(draw: shared.draw)
        let stays = Task { await s.render(block("A --> B"), width: 504) }
        let leaves = Task { await s.render(block("A --> B"), width: 504) }
        try? await Task.sleep(for: .milliseconds(100))
        leaves.cancel()
        _ = await leaves.value
        expect(isImage(await stays.value), "16m-5b r2: quien sigue esperando recibe su imagen")
        expectEq(shared.cancelledSeen, 0, "16m-5b r2: el dibujo compartido no se cancela mientras alguien lo espera")
        expectEq(shared.draws.count, 1, "16m-5b r2: y sigue siendo un solo dibujo")
    }
}

@MainActor
@Test func diagramSchedulerTimeoutTests() async {
    await watched(60, "diagramSchedulerTimeoutTests") {
        // A draw that never answers and ignores cancellation (a continuation
        // nobody resumes): the scheduler stops waiting, and the queue moves on.
        // Kills: waiting for the work (`race.work?.value`) after the deadline.
        var hung = 0
        let scheduler = DiagramScheduler(timeout: .milliseconds(80)) { block, _ in
            if block.source.contains("hang") {
                hung += 1
                await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
            }
            return .image(pic)
        }
        let started = ContinuousClock.now
        let outcome = await scheduler.render(block("hang1"), width: 504)
        expectEq(outcome, .failed(.timeout), "16m-5b r2: lo que no contesta es .timeout")
        expect(ContinuousClock.now - started < .seconds(8), "16m-5b r2: sin esperar al trabajo colgado")
        expect(isImage(await scheduler.render(block("ok"), width: 504)), "16m-5b r2: el siguiente de la cola termina")

        // Shutdown after N consecutive timeouts; a success resets the count.
        for index in 2 ..< DiagramScheduler.timeoutsBeforeShutdown {
            expectEq(await scheduler.render(block("hang\(index)"), width: 504), .failed(.timeout), "16m-5b r2: timeout \(index)")
        }
        expect(isImage(await scheduler.render(block("fine"), width: 504)), "16m-5b r2: un éxito reinicia la cuenta")
        for index in 10 ..< 10 + DiagramScheduler.timeoutsBeforeShutdown {
            expectEq(await scheduler.render(block("hang\(index)"), width: 504), .failed(.timeout), "16m-5b r2: seguidos \(index)")
        }
        let before = hung
        expectEq(await scheduler.render(block("hang99"), width: 504), .failed(.unavailable),
                 "16m-5b r2: tras N timeouts seguidos el renderer se apaga")
        expectEq(hung, before, "16m-5b r2: apagado, ni intenta dibujar")
    }
}

@MainActor
@Test func diagramTimeoutUncancellableTests() async {
    await watched(60, "diagramTimeoutUncancellableTests") {
        // Kills: a race that awaits its work after the timer fires.
        let started = ContinuousClock.now
        let result: Int? = await DiagramTimeout.run(after: .milliseconds(80)) {
            await withCheckedContinuation { (_: CheckedContinuation<Int, Never>) in }
        }
        expectEq(result, nil, "16m-5b r2: una operación que ignora la cancelación devuelve nil")
        expect(ContinuousClock.now - started < .seconds(8), "16m-5b r2: sin esperar al trabajo (nunca, no solo rápido)")
        // The caller's own cancellation ends the wait too.
        let waiting = Task { @MainActor in
            await DiagramTimeout.run(after: .seconds(30)) {
                await withCheckedContinuation { (_: CheckedContinuation<Int, Never>) in }
            }
        }
        try? await Task.sleep(for: .milliseconds(100))
        waiting.cancel()
        let cancelStart = ContinuousClock.now
        let cancelled = await waiting.value
        expectEq(cancelled, nil, "16m-5b r2: cancelar al que espera devuelve nil")
        expect(ContinuousClock.now - cancelStart < .seconds(8), "16m-5b r2: sin esperar al plazo")
    }
}

// MARK: - Model: cancel before the answer

@MainActor
@Test func diagramModelCancellationTests() async {
    await watched(60, "diagramModelCancellationTests") {
        // Kills: removing the `!Task.isCancelled` guard, or marking `drawn` early.
        let gate = GatedRenderer(.image(pic))
        let model = IslandDiagramModel()
        let target = DiagramBlock(source: flow)
        let task = Task { await model.load(target, renderer: gate, width: 504) }
        try? await Task.sleep(for: .milliseconds(80))
        task.cancel()
        gate.release()
        await task.value
        expectEq(model.state, .loading, "16m-5b r2: cancelar antes de la respuesta deja .loading")
        let again = GatedRenderer(.image(pic))
        again.release()
        await model.load(target, renderer: again, width: 504)
        expectEq(again.calls, 1, "16m-5b r2: lo cancelado no quedó marcado como dibujado")
        expectEq(model.state, .image(pic), "16m-5b r2: y al volver sí se dibuja")
    }
}

@MainActor
private final class GatedRenderer: DiagramRendering {
    let outcome: DiagramOutcome
    var calls = 0
    private var open = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    init(_ outcome: DiagramOutcome) { self.outcome = outcome }
    func release() {
        open = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
    func render(_ block: DiagramBlock, width: Double) async -> DiagramOutcome {
        calls += 1
        if !open { await withCheckedContinuation { waiting.append($0) } }
        return outcome
    }
}

// MARK: - Streaming and unclosed fences

@Test func diagramUnclosedFenceTests() {
    // A cut inside the fence is text to the end, never a diagram to draw.
    let cut = AnswerBlocks.blocks(from: "Mira.\n```companion:diagram\nflowchart LR\n  A --> ")
    if case .code(let language, _)? = cut.last { expectEq(language, "companion:diagram", "16m-5b r2: sin cerrar es código") }
    else { expect(false, "16m-5b r2: la fence sin cerrar debía quedar como código, no diagrama") }
    let closed = AnswerBlocks.blocks(from: "Mira.\n```companion:diagram\nflowchart LR\n  A --> B\n```\nFin.")
    expect(closed.contains { if case .diagram = $0 { true } else { false } }, "16m-5b r2: cerrada sí es diagrama")
    // An unclosed fence after a closed one does not take the closed one down.
    let mixed = AnswerBlocks.blocks(from: "```companion:diagram\nflowchart LR\n  A --> B\n```\n```companion:diagram\nflowchart LR\n  C -->")
    expectEq(mixed.filter { if case .diagram = $0 { true } else { false } }.count, 1, "16m-5b r2: solo la cerrada")
    // Over the byte cap, visible as code.
    let over = "flowchart LR\n" + String(repeating: "a", count: DiagramBlock.maxSourceBytes)
    let huge = AnswerBlocks.blocks(from: "```companion:diagram\n\(over)\n```")
    if case .code(let language, _)? = huge.first { expectEq(language, "companion:diagram", "16m-5b r2: sobre el tope queda como código") }
    else { expect(false, "16m-5b r2: sobre el tope debía ser código") }
}

// MARK: - Sanitizer corners

@Test func diagramSanitizerRound2Tests() {
    let lines = "graph TD\n  A --> B"
    expectEq(CompanionBlocks.diagram("---\r\nconfig:\r\n  theme: forest\r\n---\r\n\(lines)")?.source, lines,
             "16m-5b r2: frontmatter con CRLF se quita")
    expectEq(CompanionBlocks.diagram("---\rconfig:\r  theme: forest\r---\rgraph TD\r  A --> B")?.source, lines,
             "16m-5b r2: frontmatter con CR solo se quita")
    expectEq(CompanionBlocks.diagram("graph TD\r\n  A --> B")?.source, lines, "16m-5b r2: CRLF normaliza a salto")

    // `click` after `;` on the same line is still a click.
    expect(CompanionBlocks.diagram("graph TD\n  A --> B; click A href \"https://evil.example\"") == nil,
           "16m-5b r2: click tras ; no pasa (queda como código, visible)")
    expect(CompanionBlocks.diagram("graph TD\n  A --> B;click A callback") == nil, "16m-5b r2: ni sin espacio tras ;")
    expectEq(CompanionBlocks.diagram("graph TD\n  A[\"uno; dos\"] --> B")?.source, "graph TD\n  A[\"uno; dos\"] --> B",
             "16m-5b r2: un ; en una etiqueta no toca nada")
    // link/links/callback of sequence and class diagrams.
    let sequence = "sequenceDiagram\n  A->>B: hola\n  link A: Dashboard @ https://evil.example\n  links A: {\"x\": \"https://evil.example\"}"
    expectEq(CompanionBlocks.diagram(sequence)?.source, "sequenceDiagram\n  A->>B: hola", "16m-5b r2: link/links de secuencia se quitan")
    let klass = "classDiagram\n  class Foo\n  link Foo \"https://evil.example\" \"tip\"\n  callback Foo \"fn\" \"tip\""
    expectEq(CompanionBlocks.diagram(klass)?.source, "classDiagram\n  class Foo", "16m-5b r2: link/callback de clases se quitan")
    // A node that happens to be called link is a node.
    let node = "graph TD\n  link --> B\n  link -- \"texto\" --> C\n  link[Etiqueta] --> D"
    expectEq(CompanionBlocks.diagram(node)?.source, node, "16m-5b r2: un nodo llamado link no se toca")

    // `%%{` inside a label must not silently eat the rest.
    expect(CompanionBlocks.diagram("graph TD\n  A[\"%%{ oops\"] --> B\n  B --> C") == nil,
           "16m-5b r2: una %%{ sin cerrar no borra el resto en silencio: queda como código")
    let shown = AnswerBlocks.blocks(from: "```companion:diagram\ngraph TD\n  A[\"%%{ oops\"] --> B\n  B --> C\n```")
    if case .code(_, let body)? = shown.first { expect(body.contains("B --> C"), "16m-5b r2: y el código lo muestra completo") }
    else { expect(false, "16m-5b r2: debía verse como código") }
    expectEq(CompanionBlocks.diagram("graph TD\n  A[\"%%{init: {}}%% x\"] --> B")?.source, "graph TD\n  A[\" x\"] --> B",
             "16m-5b r2: una directiva cerrada en línea se quita, lo demás queda")
}

@Test func diagramRTLTests() {
    let rtl = "flowchart LR\n  A[שלום] --> B[مرحبا]"
    expectEq(CompanionBlocks.diagram(rtl)?.source, rtl, "16m-5b r2: el hebreo y el árabe pasan intactos")
    // Copying the text is the code fallback's own button (AnswerCodeBlock);
    // what it copies is the block's body, which keeps the letters intact.
    let cut = AnswerBlocks.blocks(from: "```companion:diagram\n\(rtl)")
    if case .code(_, let body)? = cut.first { expectEq(body, rtl, "16m-5b r2: el fallback a código lleva el RTL intacto") }
    else { expect(false, "16m-5b r2: sin cerrar debía quedar como código") }
    // The controls that reorder text are still gone.
    expectEq(CompanionBlocks.diagram("flowchart LR\n  A[\u{202E}שלום\u{202C}] --> B")?.source, "flowchart LR\n  A[שלום] --> B",
             "16m-5b r2: los controles bidi salen, las letras no")
}

@Test func diagramHeightCapTests() {
    expect(DiagramPage.acceptsHeight(40), "16m-5b r2: un alto normal pasa")
    expect(DiagramPage.acceptsHeight(DiagramPage.maxImageHeight), "16m-5b r2: justo el tope pasa")
    for bad in [0, -1, DiagramPage.maxImageHeight + 1, .infinity, .nan, 1e9] as [Double] {
        expect(!DiagramPage.acceptsHeight(bad), "16m-5b r2: \(bad) no pasa")
    }
}

// MARK: - The real page's isolation, wired

@MainActor
@Test func diagramRendererIsolationWiringTests() async {
    await watchedWeb(60, "diagramRendererIsolationWiringTests") {
        do {
            // The control gets its own port: an open page keeps retrying, so on a slow
            // machine its late hits must never be counted against the real render.
            let controlBeacon = try Beacon()
            guard let controlPort = await controlBeacon.start() else { return expect(false, "16m-5b r2: no abrió el puerto de control") }
            defer { controlBeacon.stop() }
            let beacon = try Beacon()
            guard let port = await beacon.start() else { return expect(false, "16m-5b r2: no abrió el puerto de prueba") }
            defer { beacon.stop() }
            let width = Double(IslandVisualMetrics.diagramWidth)

            // Control: a permissive page reaches its port, so zeros below mean the layers held.
            let open = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
            open.loadHTMLString(pageWithoutCSP(leakScript(port: controlPort)), baseURL: nil)
            guard let took = await controlBeacon.firstHit(within: 20) else {
                return expect(false, "16m-5b r2: el control no llegó a su puerto en 20 s")
            }

            // The real wiring: page, CSP, rules, configuration.
            let renderer = testRenderer(script: fakeMermaid(leaking: port))
            var view: WKWebView?
            renderer.pageObserver = { view = $0 }
            let full = await renderer.render(DiagramBlock(source: flow), width: width)
            expect(isImage(full), "16m-5b r2: la página real dibuja con el script de prueba: \(full)")
            do { try await Task.sleep(for: silenceWindow(controlTook: took)) } catch {}
            expectEq(beacon.hits, 0, "16m-5b r2: el render real no abrió ni una conexión")

            // Kills: `WKWebViewConfiguration()` instead of `makeConfiguration()`.
            guard let view else { return expect(false, "16m-5b r2: el observador no vio la página") }
            let config = view.configuration
            expect(!config.websiteDataStore.isPersistent, "16m-5b r2: la página real no usa almacén persistente")
            expect(!config.preferences.javaScriptCanOpenWindowsAutomatically, "16m-5b r2: ni abre ventanas")
            expect(config.mediaTypesRequiringUserActionForPlayback == .all, "16m-5b r2: ni reproduce medios")
        } catch {
            expect(false, "\(error)")
        }
    }
}

@MainActor
@Test func diagramRulesAloneHoldTests() async {
    await watchedWeb(60, "diagramRulesAloneHoldTests") {
        do {
            // Kills: removing `userContentController.add(rules)` from the draw. The
            // page has no CSP, so only the content rules stand between it and the port.
            // A control on its own port proves hits are observable on this machine and sets
            // the silence window, so a slow runner cannot turn "not yet" into a pass.
            let controlBeacon = try Beacon()
            guard let controlPort = await controlBeacon.start() else { return expect(false, "16m-5b r2: no abrió el puerto de control") }
            defer { controlBeacon.stop() }
            let open = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
            open.loadHTMLString(pageWithoutCSP(leakScript(port: controlPort)), baseURL: nil)
            guard let took = await controlBeacon.firstHit(within: 20) else {
                return expect(false, "16m-5b r2: el control no llegó a su puerto en 20 s")
            }
            let beacon = try Beacon()
            guard let port = await beacon.start() else { return expect(false, "16m-5b r2: no abrió el puerto de prueba") }
            defer { beacon.stop() }
            let renderer = testRenderer(script: fakeMermaid(leaking: port), pageHTML: pageWithoutCSP)
            let outcome = await renderer.render(DiagramBlock(source: flow), width: 504)
            expect(isImage(outcome), "16m-5b r2: dibuja sin CSP: \(outcome)")
            do { try await Task.sleep(for: silenceWindow(controlTook: took)) } catch {}
            expectEq(beacon.hits, 0, "16m-5b r2: las reglas solas, en el render real, cierran la red")
        } catch {
            expect(false, "\(error)")
        }
    }
}

@MainActor
@Test func diagramNavigationDelegateTests() async {
    await watchedWeb(60, "diagramNavigationDelegateTests") {
        // Kills: `decisionHandler(.allow)` in the delegate.
        let renderer = testRenderer(script: fakeMermaid())
        var view: WKWebView?
        var delegate: DiagramWebPage?
        // Taken while the page is alive: the delegate is weak and the page is
        // torn down when the draw ends.
        renderer.pageObserver = { view = $0; delegate = $0.navigationDelegate as? DiagramWebPage }
        _ = await renderer.render(DiagramBlock(source: flow), width: 504)
        guard let delegate, let view else {
            return expect(false, "16m-5b r2: el delegado de la página real es un DiagramWebPage")
        }
        for raw in ["https://evil.example/x", "http://127.0.0.1:1/", "file:///etc/passwd", "javascript:alert(1)", "data:text/html,x"] {
            var decided: WKNavigationActionPolicy?
            delegate.webView(view, decidePolicyFor: FakeNavigationAction(URL(string: raw)!)) { decided = $0 }
            expectEq(decided, .cancel, "16m-5b r2: \(raw) se cancela")
        }
        var initial: WKNavigationActionPolicy?
        delegate.webView(view, decidePolicyFor: FakeNavigationAction(URL(string: "about:blank")!)) { initial = $0 }
        expectEq(initial, .allow, "16m-5b r2: about:blank es la carga inicial")
        expect(delegate.webView(view, createWebViewWith: WKWebViewConfiguration(), for: FakeNavigationAction(URL(string: "about:blank")!),
                                windowFeatures: WKWindowFeatures()) == nil, "16m-5b r2: ninguna ventana nueva")
    }
}

@MainActor
@Test func diagramPageFailureTests() async {
    await watchedWeb(60, "diagramPageFailureTests") {
        do {
            let width = 504.0
            // Height cap before pdf(): a page that reports a huge SVG is refused.
            let tall = testRenderer(script: fakeMermaid(height: DiagramPage.maxImageHeight + 1))
            expectEq(await tall.render(DiagramBlock(source: flow), width: width), .failed(.invalid), "16m-5b r2: SVG demasiado alto es .invalid")
            let ok = testRenderer(script: fakeMermaid(height: DiagramPage.maxImageHeight))
            expect(isImage(await ok.render(DiagramBlock(source: flow), width: width)), "16m-5b r2: en el tope sí se dibuja")

            // A hung page: .timeout, then the queue moves on, and the page is released.
            let renderer = testRenderer(script: fakeMermaid())
            renderer.timeout = .milliseconds(400)
            weak var weakView: WKWebView?
            renderer.pageObserver = { weakView = $0 }
            let hung = await renderer.render(DiagramBlock(source: "flowchart LR\n  hang --> B"), width: width)
            expectEq(hung, .failed(.timeout), "16m-5b r2: JS colgado es .timeout")
            renderer.timeout = .seconds(30)
            let next = await renderer.render(DiagramBlock(source: flow), width: width)
            expect(isImage(next), "16m-5b r2: el siguiente de la cola termina: \(next)")
            do { try await Task.sleep(for: .seconds(1)) } catch {}
            expect(weakView == nil, "16m-5b r2: el web view colgado se soltó tras el timeout")

            // A cancelled caller frees a hung page too.
            let long = testRenderer(script: fakeMermaid())
            let task = Task { await long.render(DiagramBlock(source: "flowchart LR\n  hang2 --> B"), width: width) }
            do { try await Task.sleep(for: .milliseconds(600)) } catch {}
            task.cancel()
            let started = ContinuousClock.now
            _ = await task.value
            expect(ContinuousClock.now - started < .seconds(3), "16m-5b r2: cancelar suelta una página colgada")
        } catch {
            expect(false, "\(error)")
        }
    }
}

@MainActor
@Test func diagramProcessTerminationTests() async {
    await watchedWeb(60, "diagramProcessTerminationTests") {
        do {
            // A page whose web content process dies is a platform failure, not a
            // refusal of the model's text. Kills: mapping it to .invalid.
            let renderer = testRenderer(script: fakeMermaid())
            renderer.timeout = .seconds(60)
            var view: WKWebView?
            renderer.pageObserver = { view = $0 }
            let drawing = Task { await renderer.render(DiagramBlock(source: "flowchart LR\n  hang --> B"), width: 504) }
            // Until the page has loaded and is stuck in its script: a fixed wait is a
            // flake when the machine is busy with other web views.
            for _ in 0 ..< 200 where view == nil || view?.isLoading != false || view?.url == nil {
                do { try await Task.sleep(for: .milliseconds(50)) } catch {}
            }
            do { try await Task.sleep(for: .milliseconds(300)) } catch {}
            guard let page = view?.navigationDelegate as? DiagramWebPage, let view else {
                drawing.cancel()
                return expect(false, "16m-5b r2: la página real conserva su delegado durante el render")
            }
            page.webViewWebContentProcessDidTerminate(view)
            expect(page.terminated, "16m-5b r2: la terminación queda anotada")
            let outcome = await drawing.value
            expectEq(outcome, .failed(.unavailable), "16m-5b r2: el proceso caído es .unavailable")
        } catch {
            expect(false, "\(error)")
        }
    }
}

@MainActor
@Test func diagramPageLayersTests() async {
    await watchedWeb(60, "diagramPageLayersTests") {
        do {
            // Each layer alone, on a raw web view: the CSP of the real page, and the
            // content rules of the real rule list.
            // One port per page, so the control's late retries never land on a layer's count.
            let controlBeacon = try Beacon()
            guard let controlPort = await controlBeacon.start() else { return expect(false, "16m-5b r2: no abrió el puerto de control") }
            defer { controlBeacon.stop() }
            let open = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
            open.loadHTMLString(pageWithoutCSP(leakScript(port: controlPort)), baseURL: nil)
            guard let took = await controlBeacon.firstHit(within: 20) else {
                return expect(false, "16m-5b r2: el control no llegó a su puerto en 20 s")
            }

            let cspBeacon = try Beacon()
            guard let cspPort = await cspBeacon.start() else { return expect(false, "16m-5b r2: no abrió el puerto de la CSP") }
            defer { cspBeacon.stop() }
            let cspOnly = WKWebView(frame: .zero, configuration: WebKitDiagramRenderer.makeConfiguration())
            cspOnly.loadHTMLString(DiagramPage.html(vendorScript: leakScript(port: cspPort)), baseURL: nil)
            do { try await Task.sleep(for: silenceWindow(controlTook: took)) } catch {}
            expect(await leakScriptRan(in: cspOnly), "16m-5b r2: el script corrió bajo la CSP, así que el cero no es vacío")
            expectEq(cspBeacon.hits, 0, "16m-5b r2: la CSP sola cierra la red")

            do {
                let rulesBeacon = try Beacon()
                guard let rulesPort = await rulesBeacon.start() else { return expect(false, "16m-5b r2: no abrió el puerto de las reglas") }
                defer { rulesBeacon.stop() }
                let rules = try await WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: "companion.diagram.test", encodedContentRuleList: DiagramPage.blockNetworkRules)
                let config = WebKitDiagramRenderer.makeConfiguration()
                if let rules { config.userContentController.add(rules) }
                let rulesOnly = WKWebView(frame: .zero, configuration: config)
                rulesOnly.loadHTMLString(pageWithoutCSP(leakScript(port: rulesPort)), baseURL: nil)
                do { try await Task.sleep(for: silenceWindow(controlTook: took)) } catch {}
                expect(await leakScriptRan(in: rulesOnly), "16m-5b r2: el script corrió bajo las reglas, así que el cero no es vacío")
                expectEq(rulesBeacon.hits, 0, "16m-5b r2: las reglas solas cierran la red")
            }
        } catch {
            expect(false, "\(error)")
        }
    }
}
