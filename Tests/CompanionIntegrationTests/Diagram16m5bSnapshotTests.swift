import AppKit
import CompanionCore
@testable import CompanionServices
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing
import WebKit

// Wave 16m-5b: the REAL render (a WKWebView and 3.6 MB of Mermaid), so it
// runs only with COMPANION_SNAPSHOTS, like the other galleries. It writes a
// PNG per diagram and pins, against the real page, the two claims the unit
// tests can only pin as data: nothing leaves the page, and bad text fails
// with a reason instead of hanging.

private let samples: [(String, String)] = [
    ("flowchart", "flowchart LR\n  A[Idea] --> B{Vale la pena?}\n  B -->|si| C[Hacerlo]\n  B -->|no| D[Archivar]\n  C --> E[Medir]"),
    ("sequence", "sequenceDiagram\n  participant U as Karen\n  participant C as Companion\n  U->>C: Pregunta\n  C-->>U: Respuesta con diagrama\n  Note over U,C: sin red"),
    ("state", "stateDiagram-v2\n  [*] --> Escuchando\n  Escuchando --> Pensando: hold suelto\n  Pensando --> Hablando\n  Hablando --> [*]"),
    ("class", "classDiagram\n  class Sesion {\n    +proyeccion\n    +enviar()\n  }\n  Sesion <|-- SesionDeVoz"),
    ("er", "erDiagram\n  USUARIA ||--o{ MENSAJE : escribe\n  MENSAJE ||--o| TARJETA : lleva"),
    ("pie", "pie title Canal de origen\n  \"Web\" : 42\n  \"Referidos\" : 27\n  \"Eventos\" : 18"),
    ("gantt", "gantt\n  title Plan\n  dateFormat YYYY-MM-DD\n  section Isla\n  Mermaid :a1, 2026-09-29, 3d\n  Revision :after a1, 2d"),
    ("mindmap", "mindmap\n  root((Companion))\n    Voz\n    Isla\n      Popup\n      Diagramas"),
    ("timeline", "timeline\n  title Olas\n  16m-5a : Graficas\n  16m-5b : Diagramas"),
    ("unicode", "flowchart TD\n  A[猫 🐈 Gato] --> B[¿Café? ñ ü]"),
]

@MainActor private func snapshot(_ view: some View, to url: URL, width: CGFloat = 548) throws -> Bool {
    let saver: IslandFileSaver = { _, _ in .saved }
    let renderer = ImageRenderer(content: view.environment(\.fileSaver, saver)
        .frame(width: width).padding(20).background(AnswerInk.surface))
    renderer.scale = 2
    guard let tiff = renderer.nsImage?.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return false }
    try png.write(to: url)
    return true
}

let galleryEnabled = ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] != nil

@Test(.enabled(if: galleryEnabled)) @MainActor func diagramSnapshots() async throws {
    guard let dir = ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] else { return }
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let renderer = WebKitDiagramRenderer()
    // The gallery shares the machine with every other web view test; the
    // 10 s deadline is pinned by the timeout tests, not by this one.
    renderer.timeout = .seconds(60)
    let width = Double(IslandVisualMetrics.diagramWidth)

    for (name, text) in samples {
        let started = ContinuousClock.now
        let outcome = await renderer.render(DiagramBlock(source: text), width: width)
        let elapsed = ContinuousClock.now - started
        guard case .image(let image) = outcome else {
            expect(false, "16m-5b snapshot: \(name) no rindió: \(outcome)")
            continue
        }
        expect(elapsed < DiagramPage.renderTimeout * 4, "16m-5b snapshot: \(name) tardó \(elapsed) (el tope es del renderer; esto solo vigila que no cuelgue)")
        expectEq(image.width, width, "16m-5b snapshot: \(name) al ancho pedido")
        expect(image.height > 20 && image.height < 4000, "16m-5b snapshot: \(name) alto razonable: \(image.height)")
        expect(image.data.starts(with: Array("%PDF".utf8)), "16m-5b snapshot: \(name) es un PDF")
        expect(NSImage(data: image.data) != nil, "16m-5b snapshot: \(name) se decodifica")
        let model = IslandDiagramModel()
        await model.load(DiagramBlock(source: text), renderer: renderer, width: width)
        for scheme in [ColorScheme.dark, .light] {
            let tag = scheme == .dark ? "dark" : "light"
            let ok = try snapshot(IslandDiagramVisual(block: DiagramBlock(source: text), model: model)
                .environment(\.colorScheme, scheme), to: out.appendingPathComponent("diagram-\(name)-\(tag).png"))
            expect(ok, "16m-5b snapshot: \(name)-\(tag) no rindió")
        }
    }

    // Narrower than the popup's 580: the container scrolls, the picture stays whole.
    let narrow = IslandDiagramModel()
    await narrow.load(DiagramBlock(source: samples[0].1), renderer: renderer, width: width)
    _ = try snapshot(IslandDiagramVisual(block: DiagramBlock(source: samples[0].1), model: narrow),
                     to: out.appendingPathComponent("diagram-narrow.png"), width: 380)
    narrow.toggleBackground()
    _ = try snapshot(IslandDiagramVisual(block: DiagramBlock(source: samples[0].1), model: narrow),
                     to: out.appendingPathComponent("diagram-transparent-toggle.png"))

    // A second ask for the same text is the cache, not a second page.
    _ = await renderer.render(DiagramBlock(source: samples[0].1), width: width)
    let again = ContinuousClock.now
    _ = await renderer.render(DiagramBlock(source: samples[0].1), width: width)
    expect(ContinuousClock.now - again < .milliseconds(50), "16m-5b snapshot: el repetido sale de la caché")

    // Fallback: bad text is a reason, then the same text as code.
    let broken = DiagramBlock(source: "flowchart LR\n  A --> \n  ((((")
    expectEq(await renderer.render(broken, width: width), .failed(.invalid), "16m-5b snapshot: sintaxis rota es invalid")
    let notMermaid = DiagramBlock(source: "esto no es un diagrama")
    expectEq(await renderer.render(notMermaid, width: width), .failed(.invalid), "16m-5b snapshot: texto libre es invalid")
    let failed = IslandDiagramModel()
    await failed.load(broken, renderer: renderer, width: width)
    expectEq(failed.state, .failed(.invalid), "16m-5b snapshot: el modelo cae a código")
    _ = try snapshot(IslandDiagramVisual(block: broken, model: failed), to: out.appendingPathComponent("diagram-fallback-invalid.png"))
    let timedOut = IslandDiagramModel()
    await timedOut.load(broken, renderer: FakeDiagramRenderer(.failed(.timeout)), width: width)
    _ = try snapshot(IslandDiagramVisual(block: broken, model: timedOut), to: out.appendingPathComponent("diagram-fallback-timeout.png"))
    _ = try snapshot(IslandDiagramVisual(block: broken, model: IslandDiagramModel()), to: out.appendingPathComponent("diagram-loading.png"))

    // Hostile text straight to the page (past the Core sanitizer): it must
    // come back as a picture or a refusal, never hang, never open anything.
    let hostile = [
        "flowchart TD\n  A[\"<img src=x onerror=alert(1)>\"] --> B[\"<script>alert(1)</script>\"]",
        "flowchart TD\n  A --> B\n  click A href \"https://evil.example\" _blank",
        "%%{init: {\"securityLevel\":\"loose\"}}%%\nflowchart TD\n  A[\"<a href='javascript:alert(1)'>x</a>\"] --> B",
    ]
    for text in hostile {
        let outcome = await renderer.render(DiagramBlock(source: text), width: width)
        switch outcome {
        case .image, .failed(.invalid): break
        default: expect(false, "16m-5b snapshot: el texto hostil dio \(outcome)")
        }
    }

    // The popup as a reply produces it.
    let md = "# Flujo\n```companion:diagram\n\(samples[0].1)\n```\n\nY la secuencia:\n```companion:diagram\n\(samples[1].1)\n```"
    let popupModelReady = await preload(AnswerBlocks.blocks(from: md), renderer: renderer)
    expect(popupModelReady == 2, "16m-5b snapshot: dos diagramas en el popup")
}

@MainActor private func preload(_ blocks: [AnswerBlock], renderer: WebKitDiagramRenderer) async -> Int {
    var count = 0
    for case .diagram(let diagram) in blocks {
        let outcome = await renderer.render(diagram, width: Double(IslandVisualMetrics.diagramWidth))
        if case .image = outcome { count += 1 }
    }
    return count
}

// MARK: - Round 2: the real Mermaid, end to end

@Test(.enabled(if: galleryEnabled)) @MainActor func diagramRealRenderRound2() async throws {
    let renderer = WebKitDiagramRenderer()
    renderer.timeout = .seconds(60)
    let width = Double(IslandVisualMetrics.diagramWidth)

    // What the hostile text became is asserted on the SVG itself.
    var svgs: [String] = []
    renderer.svgObserver = { svgs.append($0) }
    let hostile = [
        "flowchart TD\n  A[\"<img src=x onerror=alert(1)>\"] --> B[\"<script>alert(1)</script>\"]",
        "flowchart TD\n  A[\"<a href='javascript:alert(1)'>x</a>\"] --> B",
    ]
    for text in hostile {
        let outcome = await renderer.render(DiagramBlock(source: text), width: width)
        expect({ if case .image = outcome { true } else { false } }(), "16m-5b r2: el hostil se dibuja: \(outcome)")
    }
    expectEq(svgs.count, hostile.count, "16m-5b r2: se inspeccionó cada SVG")
    for svg in svgs {
        expect(!svg.lowercased().contains("<script"), "16m-5b r2: el SVG no tiene <script")
        expect(!svg.lowercased().contains("href=\"javascript:"), "16m-5b r2: el SVG no tiene href javascript:")
        expect(!svg.lowercased().contains(" onerror"), "16m-5b r2: el SVG no tiene onerror")
    }
    renderer.svgObserver = nil

    // Right-to-left text, through Core and the page.
    let rtl = "flowchart LR\n  A[שלום] --> B[مرحبا]"
    expectEq(CompanionBlocks.diagram(rtl)?.source, rtl, "16m-5b r2: el RTL pasa Core intacto")
    let drawn = await renderer.render(DiagramBlock(source: rtl), width: width)
    expect({ if case .image = drawn { true } else { false } }(), "16m-5b r2: el RTL se dibuja: \(drawn)")

    // A valid diagram at the byte cap does not hang the queue.
    var big = "flowchart LR\n"
    var index = 0
    while big.utf8.count < DiagramBlock.maxSourceBytes - 80 {
        big += "  n\(index)[Etiqueta numero \(index) de relleno] --> n\(index + 1)\n"
        index += 1
    }
    expect(index < 500, "16m-5b r2: bajo el tope de aristas de Mermaid (\(index))")
    let started = ContinuousClock.now
    let bigOutcome = await renderer.render(DiagramBlock(source: big), width: width)
    switch bigOutcome {
    case .image, .failed(.timeout): break
    default: expect(false, "16m-5b r2: 16 KiB dio \(bigOutcome)")
    }
    expect(ContinuousClock.now - started < .seconds(70), "16m-5b r2: el de 16 KiB no cuelga")
    let after = await renderer.render(DiagramBlock(source: "flowchart LR\n  A --> B"), width: width)
    expect({ if case .image = after { true } else { false } }(), "16m-5b r2: la cola sigue viva tras el grande: \(after)")

    // A short timeout on the real page: a timeout, then the queue moves on.
    let quick = WebKitDiagramRenderer()
    quick.timeout = .milliseconds(30)
    expectEq(await quick.render(DiagramBlock(source: "flowchart LR\n  A --> B"), width: width), .failed(.timeout),
             "16m-5b r2: el timeout corto da .timeout con la página real")
    quick.timeout = .seconds(10)
    let next = await quick.render(DiagramBlock(source: "flowchart LR\n  C --> D"), width: width)
    expect({ if case .image = next { true } else { false } }(), "16m-5b r2: el render siguiente termina: \(next)")
}
