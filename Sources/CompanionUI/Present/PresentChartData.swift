import CompanionCore
import CompanionUIPro
import Foundation

/// The step from Core's plain values to the shapes the charts take. Pure, so
/// the island and the chat feed the same numbers to the same components.
enum PresentChartData {
    static func slope(_ slope: PresentSlope) -> [SlopeItem] {
        slope.points.enumerated().map { index, point in
            SlopeItem(key: "\(index)", label: point.label, start: point.before, end: point.after)
        }
    }

    static func donut(_ parts: PresentParts) -> [DonutChartDatum] {
        parts.parts.enumerated().map { index, part in
            DonutChartDatum(key: "\(index)", label: part.label, value: part.value)
        }
    }

    static func segments(_ parts: PresentParts) -> [SplitSegment] {
        parts.parts.enumerated().map { index, part in
            SplitSegment(id: "\(index)", label: part.label, value: part.value)
        }
    }

    static func treemap(_ parts: PresentParts) -> TreemapNode {
        TreemapNode(
            id: "root", label: parts.title ?? "",
            children: parts.parts.enumerated().map { index, part in
                TreemapNode(id: "\(index)", label: part.label, value: part.value)
            })
    }

    static func bars(_ ranking: PresentRanking) -> [BarChartDatum] {
        ranking.items.enumerated().map { index, item in
            BarChartDatum(id: "\(index)", label: item.label, axisLabel: item.label, value: item.value)
        }
    }

    static func lineSeries(_ series: PresentSeries) -> [LineChartSeries] {
        series.series.indices.map { index in
            LineChartSeries(id: "s\(index)", label: series.series[index].name)
        }
    }

    /// Every label is a category the model named, so the axis shows a share
    /// of them (`stride`) and the rest are reachable by hovering the point.
    static func points(_ series: PresentSeries, stride: Int) -> [LineChartPoint] {
        series.labels.indices.map { index in
            var values: [String: Double] = [:]
            for (line, item) in series.series.enumerated() where item.values.indices.contains(index) {
                values["s\(line)"] = item.values[index]
            }
            return LineChartPoint(
                id: "\(index)", label: series.labels[index],
                axisLabel: index % stride == 0 ? series.labels[index] : nil, values: values)
        }
    }

    /// The brush scrolls a real time axis. Labels that are not all dates, or
    /// more than one line, cannot be placed on it without inventing a scale,
    /// so those draw as a line chart instead.
    static func brush(_ series: PresentSeries) -> [BrushDatum]? {
        guard series.series.count == 1, let line = series.series.first,
              line.values.count == series.labels.count
        else { return nil }
        var data: [BrushDatum] = []
        for (label, value) in zip(series.labels, line.values) {
            guard let date = date(label) else { return nil }
            data.append(BrushDatum(date: date, value: value))
        }
        return data
    }

    private static func date(_ label: String) -> Date? {
        let full = ISO8601DateFormatter()
        if let date = full.date(from: label) { return date }
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        return day.date(from: label)
    }

    /// A delta's written sign picks the tone; no sign stays on the accent.
    static func tone(delta: String?) -> ChartTone {
        switch DataCardInk.tone(delta ?? "") {
        case .up: .success
        case .down: .danger
        case .flat: .accent
        }
    }
}
