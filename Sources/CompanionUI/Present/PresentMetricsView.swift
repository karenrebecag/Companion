import CompanionCore
import CompanionUIPro
import SwiftUI

/// A grid of figures. Each tile draws the visual Core picked from what the
/// model gave it: a history is a sparkline, a goal is a gauge, a bare number
/// is a counter. Label, value, unit and delta are shown as written.
struct PresentMetricsView: View {
    let tiles: [PresentTile]
    let measures: PresentMeasures

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: measures.tileMinWidth), alignment: .topLeading)],
            alignment: .leading, spacing: Space.x4
        ) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                PresentTileView(tile: tile, measures: measures)
            }
        }
    }
}

struct PresentTileView: View {
    let tile: PresentTile
    let measures: PresentMeasures

    private var metric: PresentMetric { tile.metric }

    private var valueText: String {
        let number = metric.value.formatted(.number.precision(.fractionLength(0...2)))
        guard let unit = metric.unit, !unit.isEmpty else { return number }
        return number + " " + unit
    }

    /// The value against its goal, both as written.
    private var gaugeDetail: String {
        guard let target = metric.target else { return valueText }
        return valueText + " / " + target.formatted(.number.precision(.fractionLength(0...2)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1_5) {
            Text(metric.label)
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
                .lineLimit(2)
            visual
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var visual: some View {
        switch tile.visual {
        case .sparkline:
            Sparkline(
                data: metric.trend ?? [metric.value], label: metric.label, value: valueText,
                change: metric.delta, tone: PresentChartData.tone(delta: metric.delta),
                width: measures.sparklineWidth)
        case .gauge:
            VStack(alignment: .leading, spacing: Space.x1) {
                GaugeChart(
                    value: metric.value, max: metric.target ?? metric.value, label: metric.label,
                    detail: gaugeDetail, size: measures.gaugeSize)
                delta
            }
        case .counter:
            VStack(alignment: .leading, spacing: Space.x1) {
                AnimatedCounter(
                    value: metric.value, suffix: metric.unit.map { " " + $0 } ?? "",
                    decimals: Self.decimals(metric.value))
                delta
            }
        }
    }

    @ViewBuilder
    private var delta: some View {
        if let delta = metric.delta, !delta.isEmpty {
            Text(delta)
                .font(.uiCaption)
                .foregroundStyle(DataCardInk.delta(delta))
        }
    }

    private static func decimals(_ value: Double) -> Int {
        value == value.rounded() ? 0 : 2
    }
}
