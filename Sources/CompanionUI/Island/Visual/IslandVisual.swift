import CompanionCore
import SwiftUI

// Wave 16m-5a: the `visual` container Incredible wraps every chart in: a
// header with the title and the tools, the canvas under it, on the popup's
// own quiet fill. The measures live in IslandVisualMetrics.

struct IslandChartVisual: View {
    let block: ChartBlock
    /// The donut's colours by key, kept across datasets so a segment the
    /// ring morphs into its new size keeps the colour the legend shows.
    @State private var seen: [String: Int] = [:]

    private var palette: [String: Int] {
        DonutLayout.palette(seen, keys: DonutLayout.slices(block).map(\.key))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            header
            IslandChartCanvas(block: block, palette: palette)
                .frame(height: IslandVisualMetrics.canvasHeight(for: block.kind))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(IslandChartSpeech.summary(block))
                .accessibilityChartDescriptor(IslandChartDescriptor(block: block))
            IslandChartLegend(entries: IslandChartData.legend(block, palette: palette))
        }
        .islandVisualSurface()
        .onChange(of: block, initial: true) { seen = palette }
    }

    private var header: some View {
        HStack(spacing: Space.x2) {
            if let title = block.title, !title.isEmpty {
                Text(title)
                    .font(Fonts.geist(AnswerBlockMetrics.tableSize).weight(.semibold))
                    .foregroundStyle(AnswerInk.white(AnswerInk.text))
                    .lineLimit(1)
            }
            if let unit = block.unit, !unit.isEmpty {
                Text(unit)
                    .font(Fonts.geist(AnswerBlockMetrics.tableSize))
                    .foregroundStyle(AnswerInk.white(AnswerInk.muted))
                    .lineLimit(1)
            }
            Spacer(minLength: Space.none)
            IslandVisualCopyButton(copyLabel: "island.chart.copy", copiedLabel: "island.chart.copied") {
                IslandVisualTools.copy(block)
            }
        }
    }
}

/// The `visual` container of Incredible (padding 14/16/12, 5 % fill, 7 %
/// border, radius 12), shared by charts and diagrams.
struct IslandVisualSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.top, IslandVisualMetrics.paddingTop)
            .padding(.horizontal, IslandVisualMetrics.paddingX)
            .padding(.bottom, IslandVisualMetrics.paddingBottom)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: IslandVisualMetrics.radius)
                .fill(AnswerInk.white(IslandVisualMetrics.fill)))
            .overlay(RoundedRectangle(cornerRadius: IslandVisualMetrics.radius)
                .strokeBorder(AnswerInk.white(IslandVisualMetrics.border), lineWidth: Stroke.hairline))
            // The island's surface is dark in both appearances; axis and legend
            // text read the environment, so pin it or light mode paints black
            // labels on it.
            .environment(\.colorScheme, .dark)
    }
}

extension View {
    func islandVisualSurface() -> some View { modifier(IslandVisualSurface()) }
}

/// The copy tool: the icon flips to a check for a beat.
struct IslandVisualCopyButton: View {
    let copyLabel: String
    let copiedLabel: String
    let action: () -> Void
    @State private var copied = false

    var body: some View {
        IconButton(copied ? "checkmark" : "doc.on.doc",
                   label: Localized.string(copied ? copiedLabel : copyLabel),
                   size: .islandClose, tone: .island, pressable: true) {
            action()
            copied = true
        }
        // Tied to the view: it is cancelled when the visual goes away, so a
        // closed popup never writes state back.
        .task(id: copied) {
            guard copied else { return }
            do { try await Task.sleep(for: .seconds(IslandVisualMetrics.copiedFor)) } catch { return }
            copied = false
        }
    }
}

/// Colour dots and names under the canvas, wrapping when they run long.
struct IslandChartLegend: View {
    let entries: [IslandChartData.LegendEntry]

    var body: some View {
        if !entries.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: IslandVisualMetrics.legendColumn),
                                         alignment: .leading)],
                      alignment: .leading, spacing: Space.x1_5) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: Space.x1_5) {
                        Circle()
                            .fill(IslandChartInk.color(at: entry.colorIndex))
                            .frame(width: IslandVisualMetrics.legendDot, height: IslandVisualMetrics.legendDot)
                        Text(entry.name)
                            .font(Fonts.geist(IslandVisualMetrics.axisSize))
                            .foregroundStyle(IslandChartInk.label)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}
