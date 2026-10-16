import CompanionCore
import CompanionUIPro
import SwiftUI

/// The charts: one component per family, chosen by Core. Each takes the
/// model's title as its VoiceOver name; the visible title is drawn once above.
struct PresentChart: View {
    let render: PresentRender
    let measures: PresentMeasures

    var body: some View {
        switch render {
        case .slope(let slope):
            PresentTitled(title: slope.title) {
                SlopeChart(
                    data: PresentChartData.slope(slope),
                    label: PresentStrings.label(slope.title, fallback: "present.chart"),
                    startLabel: Localized.string("present.slope.before"),
                    endLabel: Localized.string("present.slope.after"),
                    emptyLabel: Localized.string("present.empty"),
                    height: measures.slopeHeight)
            }
        case .donut(let parts):
            PresentTitled(title: parts.title) {
                DonutChart(
                    data: PresentChartData.donut(parts),
                    label: PresentStrings.label(parts.title, fallback: "present.chart"),
                    totalLabel: Localized.string("present.total"), size: measures.donutSize,
                    otherLabel: Localized.string("present.other"),
                    emptyLabel: Localized.string("present.empty"))
            }
        case .splitBar(let parts):
            PresentTitled(title: parts.title) {
                SplitBar(
                    segments: PresentChartData.segments(parts),
                    totalLabel: Localized.string("present.total"))
            }
        case .treemap(let parts):
            // The treemap draws its own label and total as a header.
            PresentTitled(title: nil) {
                Treemap(
                    data: PresentChartData.treemap(parts),
                    label: PresentStrings.label(parts.title, fallback: "present.chart"),
                    height: measures.treemapHeight, emptyLabel: Localized.string("present.empty"))
            }
        case .bar(let ranking):
            PresentTitled(title: ranking.title) {
                BarChart(
                    data: PresentChartData.bars(ranking),
                    label: PresentStrings.label(ranking.title, fallback: "present.chart"),
                    period: String(format: Localized.string("present.bar.period"), ranking.items.count),
                    unit: ranking.unit ?? "",
                    averageLabel: Localized.string("present.bar.average"),
                    valueLabel: Localized.string("present.total"),
                    showAverage: false, height: measures.barHeight)
                    // Half a bar hangs past the last tick; this keeps it inside the frame.
                    .padding(.trailing, Space.x2)
            }
        case .line(let series):
            PresentTitled(title: series.title) { PresentSeriesChart(series: series, measures: measures) }
        case .brush(let series):
            // The brush draws its own label; the line fallback does not.
            if let data = PresentChartData.brush(series) {
                BrushChart(
                    data: data, label: PresentStrings.label(series.title, fallback: "present.chart"),
                    unit: series.unit ?? "", height: measures.brushHeight,
                    overviewHeight: measures.brushOverview)
            } else {
                PresentTitled(title: series.title) { PresentSeriesChart(series: series, measures: measures) }
            }
        case .streamgraph(let series):
            PresentTitled(title: series.title) {
                Streamgraph(
                    data: PresentChartData.points(series, stride: measures.axisStride(count: series.labels.count)),
                    series: PresentChartData.lineSeries(series),
                    label: PresentStrings.label(series.title, fallback: "present.chart"),
                    unit: series.unit ?? "", height: measures.streamHeight,
                    emptyLabel: Localized.string("present.empty"))
            }
        default:
            EmptyView()
        }
    }
}

/// A plain line chart, also the fallback of a brush that has no date axis.
struct PresentSeriesChart: View {
    let series: PresentSeries
    let measures: PresentMeasures

    var body: some View {
        LineChart(
            points: PresentChartData.points(series, stride: measures.axisStride(count: series.labels.count)),
            series: PresentChartData.lineSeries(series),
            label: PresentStrings.label(series.title, fallback: "present.chart"),
            unit: series.unit ?? "", height: measures.lineHeight)
    }
}
