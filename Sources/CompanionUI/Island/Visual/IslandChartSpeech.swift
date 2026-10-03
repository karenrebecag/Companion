import CompanionCore
import Foundation

/// The chart said in words, for VoiceOver: kind, title, how many points and
/// where the extremes sit. The numbers come from Core's ChartSummary.
enum IslandChartSpeech {
    static func kindName(_ kind: ChartBlock.Kind) -> String {
        Localized.string("island.chart.kind.\(kind.rawValue)")
    }

    static func summary(_ block: ChartBlock) -> String {
        let facts = ChartSummary(block)
        var parts: [String] = []
        if let title = block.title, !title.isEmpty {
            parts.append("\(kindName(block.kind)), \(title)")
        } else {
            parts.append(kindName(block.kind))
        }
        parts.append(facts.pointCount == 1
            ? Localized.string("island.chart.points.one")
            : String(format: Localized.string("island.chart.points.other"), facts.pointCount))
        if let high = facts.maximum {
            parts.append(String(format: Localized.string("island.chart.high"),
                                place(high, of: facts, unit: block.unit), high.valueText + unitSuffix(block.unit)))
        }
        if let low = facts.minimum {
            parts.append(String(format: Localized.string("island.chart.low"),
                                place(low, of: facts, unit: block.unit), low.valueText + unitSuffix(block.unit)))
        }
        if block.kind == .donut { parts += donutParts(block) }
        return parts.joined(separator: ". ") + "."
    }

    /// The ring is hidden from VoiceOver, so the words carry every segment
    /// it draws, its share, and who "Other" stands for.
    static func donutParts(_ block: ChartBlock) -> [String] {
        let slices = DonutLayout.slices(block)
        let total = slices.reduce(0) { $0 + $1.value }
        guard total > 0 else { return [] }
        let suffix = unitSuffix(block.unit)
        let whole = Localized.string("island.chart.total") + " " + ChartBlock.text(total) + suffix
        return [whole] + slices.map { slice in
            let part = String(format: Localized.string("island.chart.part"), slice.label,
                              ChartBlock.text(slice.value) + suffix, DonutLayout.shareText(slice.value / total))
            guard !slice.members.isEmpty else { return part }
            let names = series(slice.members.map(\.label))
            return part + ", " + String(format: Localized.string("island.chart.includes"), names)
        }
    }

    /// "a, b and c": the members of "Other" read as one list.
    private static func series(_ names: [String]) -> String {
        guard names.count > 1, let last = names.last else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " " + Localized.string("island.chart.and") + " " + last
    }

    /// The label, and which series when there is more than one to tell apart.
    private static func place(_ point: ChartSummary.Extreme, of facts: ChartSummary,
                              unit: String?) -> String {
        guard facts.seriesCount > 1, let name = point.series, !name.isEmpty else { return point.label }
        return "\(point.label) (\(name))"
    }

    private static func unitSuffix(_ unit: String?) -> String {
        guard let unit, !unit.isEmpty else { return "" }
        return " " + unit
    }
}
