import AppKit
import CompanionCore
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

// Wave 16m §3: the popup and the work states compare against Incredible by
// snapshot. Same harness rule as uiSnapshots: only with COMPANION_SNAPSHOTS.

@Test @MainActor func answerPopupSnapshots() async throws {
    guard let dir = ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] else { return }
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let markdown = """
    # Comparativa Swift vs TypeScript
    ### CONTEXTO
    Dos lenguajes con tipado fuerte, dos mundos de despliegue distintos.

    | Aspecto | Swift | TypeScript |
    |---|---|---|
    | Plataforma | Apple nativo | Web y Node |
    | Tipado | Estricto del compilador | Gradual, se borra |
    | Concurrencia | actors, async/await | event loop |

    > **Ojo:** el runtime decide más que la sintaxis.

    - [x] revisar el pipeline de CI
    - [ ] medir el arranque en frío

    `Sources/CompanionCore/AnswerBlocks.swift`

    ```swift
    let blocks = AnswerBlocks.blocks(from: reply)
    ```
    """
    let blocks = AnswerBlocks.blocks(from: markdown)
    let popup = AnswerPopupView(
        blocks: blocks, screenWidth: 1800, maxHeight: 520, onClose: {})
        .environment(\.colorScheme, .dark)
        .padding(20)
        .background(Color(white: 0.35))
    let renderer = ImageRenderer(content: popup)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?
              .representation(using: .png, properties: [:])
    else {
        expect(false, "16m-1 snapshot: el popup no rindió imagen")
        return
    }
    try png.write(to: out.appendingPathComponent("answer-popup-dark.png"))

    // A short answer proves the hug: the popup must not reach the cap.
    let short = AnswerBlocks.blocks(from: "## Listo\nEl invite salió a las 10:40.")
    let shortRep = try piece(AnswerPopupView(
        blocks: short, screenWidth: 1800, maxHeight: 520, onClose: {}),
        to: out, "answer-popup-short")
    // Two lines of answer measure nowhere near 520; a cap-tall render means
    // the greedy ScrollView is back (review 16m: the gallery is also proof).
    if let shortRep {
        expect(shortRep.pixelsHigh < Int(520 * 2),
               "16m-1: el popup corto no abraza — mide \(shortRep.pixelsHigh)px")
    }

    // Data fences render as the same cards the window shows.
    let dataMarkdown = """
    # Ventas del trimestre
    ```companion:stats
    {"items":[{"label":"Total","value":"128"},{"label":"Nuevos","value":"41"},{"label":"MRR","value":"$12.4k"}]}
    ```
    ```companion:chart
    {"kind":"bar","labels":["Jul","Ago","Sep"],"series":[{"name":"QMs","values":[38,44,46]}]}
    ```
    """
    try piece(AnswerPopupView(
        blocks: AnswerBlocks.blocks(from: dataMarkdown), screenWidth: 1800,
        maxHeight: 520, onClose: {}), to: out, "answer-popup-datacards")

    var job = JobTimeline(goal: "Ordenar las capturas del escritorio")
    job.steps = [
        JobStepInfo(tool: "Bash", label: "Bash: ls ~/Desktop", done: true),
        JobStepInfo(tool: "Read", label: "Read: inventario.md", done: true, failed: true),
        JobStepInfo(tool: "Write", label: "Write: plan.md"),
    ]
    try piece(IslandRunCard(job: job), to: out, "island-runcard")

    var long = JobTimeline(goal: "Migrar el blog completo")
    long.steps = (1 ... 8).map { n in
        JobStepInfo(tool: n % 2 == 0 ? "Write" : "WebFetch",
                    label: "Paso \(n): entrada \(n) del blog", done: n < 7)
    }
    try piece(IslandChecklist(job: long, onDismiss: {}), to: out, "island-checklist")

    try piece(IslandAgentBars(agents: [
        JobStepInfo(tool: "Task", label: "Task: revisar seguridad"),
        JobStepInfo(tool: "Task", label: "Task: escribir tests"),
    ]), to: out, "island-agentbars")

    try piece(IslandReel(touched: ["Slack", "Safari", "Notas", "Mail"])
        .frame(width: 420), to: out, "island-reel")

    try piece(VStack(alignment: .leading, spacing: 12) {
        IslandTranscript(text: "abre el correo de ana y dime qué", fixed: false)
        IslandTranscript(text: "Abre el correo de Ana y dime qué pide.", fixed: true)
    }.frame(width: 420), to: out, "island-transcript")
}

/// One widget on the island's own dark, at 2x, named for the gallery.
/// Returns the bitmap so a caller can assert on the rendered measures.
@discardableResult
@MainActor private func piece(
    _ view: some View, to dir: URL, _ name: String
) throws -> NSBitmapImageRep? {
    let framed = view
        .environment(\.colorScheme, .dark)
        .padding(20)
        .background(Color(white: 0.35))
    let renderer = ImageRenderer(content: framed)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else {
        expect(false, "16m snapshot: \(name) no rindió imagen")
        return nil
    }
    try png.write(to: dir.appendingPathComponent(name + ".png"))
    return rep
}
