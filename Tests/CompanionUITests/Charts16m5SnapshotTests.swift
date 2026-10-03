import AppKit
import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Foundation
import SwiftUI
import Testing

// Wave 16m-5a: one snapshot per chart kind, in both appearances, on the
// popup's own surface. Same harness rule as the other galleries: only with
// COMPANION_SNAPSHOTS.

private let months = ["Ene", "Feb", "Mar", "Abr", "May", "Jun"]

@MainActor private func samples() -> [(String, ChartBlock)] {
    let one = [ChartBlock.Series(name: "QMs", values: [38, 44, 46, 41, 52, 58])]
    let two = one + [.init(name: "Demos", values: [22, 30, 28, 35, 33, 40])]
    let share = [ChartBlock.Series(values: [42, 27, 18, 13])]
    let axes = ["Voz", "Latencia", "Precisión", "Costo", "Contexto"]
    return [
        ("bar", ChartBlock(title: "Reuniones por mes", kind: .bar, labels: months, series: two)),
        ("line", ChartBlock(title: "Reuniones por mes", kind: .line, unit: "QMs", labels: months, series: two)),
        ("area", ChartBlock(title: "Reuniones por mes", kind: .area, labels: months, series: one)),
        ("scatter", ChartBlock(title: "Dispersión", kind: .scatter, labels: months, series: one)),
        ("pie", ChartBlock(title: "Canal de origen", kind: .pie, labels: ["Web", "Referidos", "Eventos", "Otros"], series: share)),
        ("donut", ChartBlock(title: "Canal de origen", kind: .donut, labels: ["Web", "Referidos", "Eventos", "Otros"], series: share)),
        ("polar", ChartBlock(title: "Carga por área", kind: .polar, labels: axes, series: [.init(values: [8, 5, 9, 3, 6])])),
        ("radar", ChartBlock(title: "Modelos", kind: .radar, labels: axes,
                             series: [.init(name: "Local", values: [7, 9, 5, 9, 4]), .init(name: "Nube", values: [9, 5, 9, 4, 8])])),
        ("radar-20", ChartBlock(title: "20 ejes (el tope)", kind: .radar, labels: (1 ... 20).map { "Eje largo \($0)" },
                                series: [.init(name: "A", values: (1 ... 20).map { Double(($0 * 7) % 10 + 1) })])),
        ("pie-12", ChartBlock(title: "12 rebanadas (el tope)", kind: .pie, labels: (1 ... 12).map { "Canal \($0)" },
                              series: [.init(values: (1 ... 12).map { Double(13 - $0) })])),
        ("polar-12", ChartBlock(title: "12 cuñas (el tope)", kind: .polar, labels: (1 ... 12).map { "Área \($0)" },
                                series: [.init(values: (1 ... 12).map { Double(($0 * 5) % 9 + 1) })])),
        ("dup-labels", ChartBlock(title: "Etiquetas repetidas y vacía", kind: .bar, labels: ["Lun", "Lun", "", "Mar"],
                                  series: [.init(values: [3, 5, 2, 6])])),
    ]
}

@Test @MainActor func chartSnapshots() throws {
    guard let dir = ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] else { return }
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    for (name, block) in samples() {
        for scheme in [ColorScheme.dark, .light] {
            let tag = scheme == .dark ? "dark" : "light"
            let view = IslandChartVisual(block: block)
                .frame(width: 548)
                .padding(20)
                .background(AnswerInk.surface)
                .environment(\.colorScheme, scheme)
                .environment(\.islandChartSweeps, false)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
            else { expect(false, "16m-5a snapshot: \(name)-\(tag) no rindió"); continue }
            try png.write(to: out.appendingPathComponent("chart-\(name)-\(tag).png"))
        }
    }
    // The whole popup, as a reply produces it.
    let md = "# Resumen\n```companion:chart\n{\"title\":\"Reuniones\",\"kind\":\"radar\",\"labels\":[\"a\",\"b\",\"c\"],\"series\":[{\"name\":\"x\",\"values\":[3,5,4]}]}\n```"
    let popup = AnswerPopupView(blocks: AnswerBlocks.blocks(from: md), screenWidth: 1800, maxHeight: 700, onClose: {})
        .padding(20).background(Color(white: 0.35))
    let renderer = ImageRenderer(content: popup)
    renderer.scale = 2
    if let tiff = renderer.nsImage?.tiffRepresentation,
       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
        try png.write(to: out.appendingPathComponent("chart-popup.png"))
    } else { expect(false, "16m-5a snapshot: el popup no rindió") }
}
