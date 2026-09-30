import Charts
import CompanionCore
import SwiftUI

// Wave 20-1 (spec 20 §5): Incredible's stat, table and chart blocks as
// native cards. Swift Charts ships with the system: no dependency (D2).

/// A row of figures: the value large, the label under it, the change beside.
struct StatsCard: View {
    let block: StatsBlock

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            DataCardTitle(title: block.title)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: CardMetrics.statMin), alignment: .leading)],
                      alignment: .leading, spacing: Space.x3) {
                ForEach(Array(block.items.enumerated()), id: \.offset) { _, item in
                    tile(item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func tile(_ item: StatsBlock.Item) -> some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
                Text(item.value)
                    .font(.uiTitle)
                    .foregroundStyle(Semantic.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let delta = item.delta, !delta.isEmpty {
                    Text(delta)
                        .font(.uiCaption)
                        .foregroundStyle(DataCardInk.delta(delta))
                }
            }
            Text(item.label)
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Rows with a header that stays; wide tables scroll sideways.
struct TableCard: View {
    let block: TableBlock

    /// A table born from a chart can carry 500 rows, which the grid would
    /// lay out whole; the card shows the same first rows a fence table does.
    static func visibleRows(_ block: TableBlock) -> [[String]] {
        Array(block.rows.prefix(TableBlock.maxRows))
    }

    static func isCut(_ block: TableBlock) -> Bool {
        block.truncated || block.rows.count > TableBlock.maxRows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            DataCardTitle(title: block.title)
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: Space.x4, verticalSpacing: Space.x2) {
                    GridRow {
                        ForEach(Array(block.columns.enumerated()), id: \.offset) { _, column in
                            Text(column)
                                .font(.uiCaption.weight(.semibold))
                                .foregroundStyle(Semantic.mutedForeground)
                        }
                    }
                    Divider()
                    ForEach(Array(Self.visibleRows(block).enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                Text(cell)
                                    .font(.uiBody)
                                    .foregroundStyle(Semantic.foreground)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: CardMetrics.tableMax)
            if Self.isCut(block) {
                Text(String(format: Localized.string("card.table.truncated"), TableBlock.maxRows))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}

/// One chart per block; the kind picks the mark, the series pick the colour.
struct ChartCard: View {
    let block: ChartBlock

    @ViewBuilder
    var body: some View {
        // Polar and radar are painted by the island only; here the same
        // numbers read as a table, not as bars under another name.
        if block.kind.isIslandOnly {
            TableCard(block: block.asTable)
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            DataCardTitle(title: block.title, unit: block.unit)
            chart
                .frame(height: CardMetrics.chart)
                .accessibilityLabel(block.title ?? Localized.string("card.chart"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var points: [ChartPoint] { ChartPoint.flatten(block) }
    private var many: Bool { block.series.count > 1 }

    @ViewBuilder
    private var chart: some View {
        switch block.kind {
        case .pie, .donut:
            Chart(points.filter { $0.series == 0 }) { point in
                SectorMark(angle: .value(point.label, point.value),
                           innerRadius: .ratio(block.kind == .donut ? 0.6 : 0))
                    .foregroundStyle(by: .value("label", point.label))
            }
        default:
            Chart(points) { point in
                mark(point)
                    .foregroundStyle(by: .value("series", point.seriesName))
            }
            .chartLegend(many ? .visible : .hidden)
        }
    }

    @ChartContentBuilder
    private func mark(_ point: ChartPoint) -> some ChartContent {
        let x = PlottableValue.value("label", point.label)
        let y = PlottableValue.value("value", point.value)
        switch block.kind {
        case .line: LineMark(x: x, y: y).interpolationMethod(.monotone)
        case .area: AreaMark(x: x, y: y, stacking: .unstacked)
        case .scatter: PointMark(x: x, y: y)
        default: BarMark(x: x, y: y).position(by: .value("series", point.seriesName))
        }
    }
}

/// One plotted value, flat: Swift Charts wants rows, the block keeps series.
struct ChartPoint: Identifiable, Equatable {
    let id: Int
    let series: Int
    let seriesName: String
    let label: String
    let value: Double

    static func flatten(_ block: ChartBlock) -> [ChartPoint] {
        var out: [ChartPoint] = []
        for (s, serie) in block.series.enumerated() {
            let name = serie.name ?? "\(s + 1)"
            for (i, label) in block.labels.enumerated() {
                out.append(ChartPoint(id: out.count, series: s, seriesName: name, label: label,
                                      value: serie.values[i]))
            }
        }
        return out
    }
}

private struct DataCardTitle: View {
    let title: String?
    var unit: String?

    var body: some View {
        if title?.isEmpty == false || unit?.isEmpty == false {
            HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
                if let title, !title.isEmpty {
                    Text(title).font(.uiSubtitle).foregroundStyle(Semantic.foreground)
                }
                if let unit, !unit.isEmpty {
                    Text(unit).font(.uiCaption).foregroundStyle(Semantic.mutedForeground)
                }
            }
        }
    }
}

/// Not a palette: a delta's sign picks a Semantic role (success, danger,
/// muted). The sign logic is what lives here, so a test can read it
/// without rendering.
enum DataCardInk {
    enum Tone: Equatable { case up, down, flat }

    /// Read from the sign the model wrote; no sign stays neutral.
    static func tone(_ text: String) -> Tone {
        let first = text.trimmingCharacters(in: .whitespaces).first
        if first == "+" { return .up }
        if first == "-" || first == "\u{2212}" { return .down }
        return .flat
    }

    static func delta(_ text: String) -> Color {
        switch tone(text) {
        case .up: Semantic.success
        case .down: Semantic.danger
        case .flat: Semantic.mutedForeground
        }
    }
}
