import CompanionCore
import Foundation

/// What the painters read out of a ChartBlock, decided apart from any view.
enum IslandChartData {
    /// Own value: past this many entries a legend stops being a legend.
    static let maxLegend = 12
    /// Own value: an axis with more labels than this is unreadable; the
    /// painter shows an even sample and keeps every point in the drawing.
    static let maxAxisLabels = 8

    struct LegendEntry: Equatable {
        let name: String
        let colorIndex: Int
    }

    /// One plotted value. The key is its position, never its label: a label
    /// can repeat or be empty, and two points on one key paint as one.
    struct Point: Equatable {
        let key: String
        let value: Double
    }

    static func xKeys(count: Int) -> [String] {
        (0 ..< max(count, 0)).map(String.init)
    }

    /// The points one series has; a series longer than the labels (only a
    /// hand-built block) is cut to the labels rather than trapped on.
    static func points(_ block: ChartBlock, series index: Int = 0) -> [Point] {
        guard block.series.indices.contains(index) else { return [] }
        let values = block.series[index].values.prefix(block.labels.count)
        return values.enumerated().map { Point(key: String($0.offset), value: $0.element) }
    }

    /// The keys whose labels the axis prints: an even sample, first included.
    static func axisKeys(count: Int) -> [String] {
        let keys = xKeys(count: count)
        guard keys.count > maxAxisLabels else { return keys }
        let step = Int((Double(keys.count) / Double(maxAxisLabels)).rounded(.up))
        return keys.enumerated().filter { $0.offset % step == 0 }.map(\.element)
    }

    /// The label at a key, blank when there is none.
    static func axisText(_ labels: [String], key: String) -> String {
        guard let index = Int(key), labels.indices.contains(index) else { return "" }
        return labels[index]
    }

    /// Labels VoiceOver can tell apart: empty is its number, a repeat gets
    /// its position.
    static func uniqueLabels(_ labels: [String]) -> [String] {
        var seen = Set<String>()
        return labels.enumerated().map { index, label in
            let base = label.isEmpty ? "\(index + 1)" : label
            let unique = seen.contains(base) ? "\(base) (\(index + 1))" : base
            seen.insert(unique)
            return unique
        }
    }

    /// Series names Swift Charts can tell apart: an unnamed series is its
    /// number, and a repeated name gets its position.
    static func seriesNames(_ block: ChartBlock) -> [String] {
        var seen = Set<String>()
        return block.series.enumerated().map { index, serie in
            let base = serie.name?.isEmpty == false ? serie.name! : "\(index + 1)"
            let name = seen.contains(base) ? "\(base) (\(index + 1))" : base
            seen.insert(name)
            return name
        }
    }

    /// `palette` is the donut's key-to-colour memory; without one each
    /// segment takes its colour in data order.
    static func legend(_ block: ChartBlock, palette: [String: Int] = [:]) -> [LegendEntry] {
        switch block.kind {
        case .donut:
            // The ring groups small parts, so the legend names its segments, not the raw labels.
            let slices = DonutLayout.slices(block)
            let colors = DonutLayout.palette(palette, keys: slices.map(\.key))
            return slices.map { LegendEntry(name: $0.label, colorIndex: DonutLayout.colorIndex($0.key, palette: colors)) }
        case .pie:
            return uniqueLabels(block.labels).prefix(maxLegend).enumerated().map { LegendEntry(name: $1, colorIndex: $0) }
        case .polar:
            return []
        case .bar, .line, .area, .scatter, .radar:
            guard block.series.count > 1 else { return [] }
            return seriesNames(block).enumerated().map { LegendEntry(name: $1, colorIndex: $0) }
        }
    }

    /// The largest value any series reaches, never below zero.
    static func maximum(_ block: ChartBlock) -> Double {
        max(block.series.flatMap(\.values).max() ?? 0, 0)
    }
}
