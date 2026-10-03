import Charts
import CompanionCore
import SwiftUI

/// The drawing itself. Bar, line, area, scatter and pie ride Swift Charts
/// (system framework, no dependency); polar and radar are Paths, because
/// Swift Charts has no mark for them. The donut is Arc's ring, which morphs
/// per key between datasets where a SectorMark would only cross-fade; it is
/// the one kind that moves, and it jumps under Reduce Motion.
struct IslandChartCanvas: View {
    let block: ChartBlock
    /// The donut's key-to-colour memory, shared with the legend.
    var palette: [String: Int] = [:]

    var body: some View {
        switch block.kind {
        case .polar, .radar, .donut:
            IslandRadialChart(block: block, palette: palette)
        case .pie:
            sectors
        case .bar, .line, .area, .scatter:
            cartesian
        }
    }

    private var names: [String] { IslandChartData.seriesNames(block) }

    private var sectors: some View {
        Chart(Array(IslandChartData.points(block).enumerated()), id: \.offset) { index, point in
            SectorMark(angle: .value("value", point.value),
                       angularInset: IslandVisualMetrics.sectorGap)
                .foregroundStyle(IslandChartInk.color(at: index))
        }
        .chartLegend(.hidden)
    }

    private var cartesian: some View {
        Chart {
            ForEach(Array(block.series.indices), id: \.self) { s in
                ForEach(IslandChartData.points(block, series: s), id: \.key) { point in
                    mark(x: point.key, y: point.value, series: names[s], color: IslandChartInk.color(at: s))
                }
            }
        }
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: IslandChartData.axisKeys(count: block.labels.count)) { value in
                AxisValueLabel {
                    Text(IslandChartData.axisText(block.labels, key: value.as(String.self) ?? ""))
                }
                .font(Fonts.geist(IslandVisualMetrics.axisSize))
                .foregroundStyle(IslandChartInk.axis)
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(IslandChartInk.grid)
                AxisValueLabel().font(Fonts.geist(IslandVisualMetrics.axisSize))
                    .foregroundStyle(IslandChartInk.axis)
            }
        }
    }

    @ChartContentBuilder
    private func mark(x: String, y: Double, series: String, color: Color) -> some ChartContent {
        // The key is the point's index: labels may repeat or be empty.
        let xv = PlottableValue.value("point", x)
        let yv = PlottableValue.value("value", y)
        switch block.kind {
        case .line:
            LineMark(x: xv, y: yv, series: .value("series", series))
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: IslandVisualMetrics.lineWidth))
                .foregroundStyle(color)
        case .area:
            AreaMark(x: xv, y: yv, series: .value("series", series), stacking: .unstacked)
                .foregroundStyle(color.opacity(IslandVisualMetrics.areaAlpha))
            LineMark(x: xv, y: yv, series: .value("series", series))
                .lineStyle(StrokeStyle(lineWidth: IslandVisualMetrics.lineWidth))
                .foregroundStyle(color)
        case .scatter:
            PointMark(x: xv, y: yv).foregroundStyle(color)
        default:
            BarMark(x: xv, y: yv).position(by: .value("series", series)).foregroundStyle(color)
        }
    }
}
