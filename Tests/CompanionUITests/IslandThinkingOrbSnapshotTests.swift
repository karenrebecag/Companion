import AppKit
import CompanionCore
@testable import CompanionUI
import Foundation
import SwiftUI
import Testing

// Visual review of the island's lead orb and status words: each orb state in
// the 32 pt slot and enlarged, the morph as a frame sequence and the shimmer
// at three points of its pass. Runs only with COMPANION_SNAPSHOTS=<dir>; it
// also writes a rough frame-cost note next to the images.

@Test(.enabled(if: ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"] != nil,
               "only with COMPANION_SNAPSHOTS=<dir>, like the other galleries"))
@MainActor func islandThinkingOrbGallery() throws {
    let dir = try #require(ProcessInfo.processInfo.environment["COMPANION_SNAPSHOTS"], "gallery: directory")
    let out = URL(fileURLWithPath: dir, isDirectory: true)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

    let marks: [(String, IslandLeadMark, String)] = [
        ("enviando", .thinking(.ring), "Enviando…"),
        ("pensando", .thinking(.rubik), "Pensando…"),
        ("actuando", .thinking(.globe), "Pensando…"),
        ("trabajo", .thinking(.braid), "Ordenar descargas · 2 pasos"),
    ]
    for (name, mark, words) in marks {
        // A job's goal does not shimmer: only the waiting words do.
        let settle: Double = name == "trabajo" ? 1 : 0
        try write(row(mark, words: words, shimmer: (0.45, settle)), to: out, "isla-orbe-\(name)")
        try write(ThinkingOrbFrameOnly(mark: mark, side: 120), to: out, "isla-orbe-\(name)-grande")
    }

    // Every Space UI mode in the 32 pt slot, at three instants: what reads at notch size.
    let modes = VStack(alignment: .leading, spacing: 8) {
        ForEach(ThinkingOrbMode.allCases, id: \.self) { mode in
            HStack(spacing: 12) {
                Text(mode.caption).font(.caption).foregroundStyle(.gray).frame(width: 80, alignment: .leading)
                ForEach([0.0, 0.7, 1.9], id: \.self) { t in
                    ThinkingOrb(mode: mode, surface: .ink, scale: IslandLeadOrbMetrics.fill,
                                size: IslandChrome.meterSide, frozenAt: t)
                }
            }
        }
    }
    try write(modes, to: out, "isla-orbe-modos-32pt")

    let morphs: [(String, String, String)] = [("enviando-pensando", "Enviando…", "Pensando…"),
                                              ("pensando-listo", "Pensando…", "Listo")]
    for (name, from, to) in morphs {
        let frames = [0, 0.04, 0.08, 0.12, 0.16, 0.22, 0.3, 0.45, 0.8]
        let strip = VStack(alignment: .leading, spacing: 6) {
            ForEach(frames, id: \.self) { t in
                HStack(spacing: 12) {
                    Text(String(format: "%.2f s", t)).font(.caption.monospacedDigit()).foregroundStyle(.gray)
                        .frame(width: 48, alignment: .trailing)
                    IslandTextMorph(text: to, frozen: (from, t))
                }
            }
        }
        try write(strip, to: out, "isla-morph-\(name)")
    }

    let sweeps = VStack(alignment: .leading, spacing: 6) {
        ForEach([0.0, 0.3, 0.5, 0.7, 1.0], id: \.self) { t in
            IslandTextMorph(text: "Pensando…", frozen: ("Pensando…", .infinity))
                .modifier(IslandTextShimmer(active: true, frozen: (t, 0)))
        }
        IslandTextMorph(text: "Listo", frozen: ("Listo", .infinity))
            .modifier(IslandTextShimmer(active: false, frozen: (0.5, 0.5)))
    }
    try write(sweeps, to: out, "isla-shimmer-pasada")
    try frameCost().write(to: out.appendingPathComponent("isla-orbe-costo.txt"), atomically: true, encoding: .utf8)
}

@MainActor private func row(_ mark: IslandLeadMark, words: String, shimmer: (Double, Double)) -> some View {
    HStack(spacing: 10) {
        IslandLeadOrb(mark: mark, levels: VoiceLevels(mic: 0, agent: 0), side: IslandChrome.meterSide, paused: true)
        IslandTextMorph(text: words, frozen: (words, .infinity))
            .modifier(IslandTextShimmer(active: true, frozen: shimmer))
    }
}

private struct ThinkingOrbFrameOnly: View {
    let mark: IslandLeadMark
    let side: CGFloat

    var body: some View {
        IslandLeadOrb(mark: mark, levels: VoiceLevels(mic: 0, agent: 0), side: side, paused: true)
    }
}

@MainActor private func write(_ view: some View, to dir: URL, _ name: String) throws {
    let framed = view.padding(16).background(Color.black).environment(\.colorScheme, .dark)
    let renderer = ImageRenderer(content: framed)
    renderer.scale = 2
    let tiff = try #require(renderer.nsImage?.tiffRepresentation, "render: \(name)")
    let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
    try png.write(to: dir.appendingPathComponent("\(name).png"))
}

/// Scene math alone and a full offscreen draw, per mode at the island's size.
/// Offscreen rendering includes ImageRenderer's own setup, so it is an upper bound.
@MainActor private func frameCost() -> String {
    let side = Double(IslandChrome.meterSide) * IslandLeadOrbMetrics.fill
    var lines = ["side \(side) pt, \(ThinkingOrb.frameInterval) s budget per frame"]
    for mode in [ThinkingOrbMode.ring, .rubik, .globe, .braid] {
        let preset = ThinkingOrbPreset.make(mode, pixelSize: side)
        let runs = 500
        let start = Date()
        var dots = 0
        for i in 0..<runs {
            dots = ThinkingOrbScene.render(mode, size: side, time: Double(i) * 0.02, options: preset.options).dots.count
        }
        let scene = Date().timeIntervalSince(start) / Double(runs)
        let drawStart = Date()
        for _ in 0..<50 {
            let renderer = ImageRenderer(content: ThinkingOrb(mode: mode, surface: .ink, scale: IslandLeadOrbMetrics.fill,
                                                              size: IslandChrome.meterSide, paused: true))
            renderer.scale = 2
            _ = renderer.cgImage
        }
        let draw = Date().timeIntervalSince(drawStart) / 50
        lines.append("\(mode): \(dots) dots, scene \(String(format: "%.3f", scene * 1000)) ms, "
            + "offscreen draw \(String(format: "%.3f", draw * 1000)) ms")
    }
    return lines.joined(separator: "\n") + "\n"
}
