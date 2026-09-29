import Accessibility
import CompanionCore
import SwiftUI

/// The chart for VoiceOver's audio graph: the same points the drawing plots,
/// so a person who cannot see it can still hear its shape. Round kinds ride
/// it too: their values are still one number per label.
struct IslandChartDescriptor: AXChartDescriptorRepresentable {
    let block: ChartBlock

    func makeChartDescriptor() -> AXChartDescriptor {
        let values = block.series.flatMap(\.values)
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let categories = IslandChartData.uniqueLabels(block.labels)
        let axisTitle = block.title.flatMap { $0.isEmpty ? nil : $0 } ?? Localized.string("island.chart.categories")
        let x = AXCategoricalDataAxisDescriptor(title: axisTitle, categoryOrder: categories)
        let y = AXNumericDataAxisDescriptor(
            title: block.unit ?? "", range: low ... max(high, low), gridlinePositions: [],
            valueDescriptionProvider: { ChartBlock.text($0) })
        let continuous = block.kind == .line || block.kind == .area
        let series = zip(IslandChartData.seriesNames(block), block.series).map { name, serie in
            AXDataSeriesDescriptor(
                name: name, isContinuous: continuous,
                dataPoints: zip(categories, serie.values).map { AXDataPoint(x: $0, y: $1) })
        }
        return AXChartDescriptor(title: block.title ?? IslandChartSpeech.kindName(block.kind),
                                 summary: IslandChartSpeech.summary(block),
                                 xAxis: x, yAxis: y, additionalAxes: [], series: series)
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {}
}
