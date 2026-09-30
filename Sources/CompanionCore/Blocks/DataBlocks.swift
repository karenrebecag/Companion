import Foundation

// Wave 20-0 (spec 20 §5): figures, tables and charts on the card channel,
// Incredible's `stat`/`table`/`chart` blocks. Bounded so a runaway fence
// cannot freeze the thread; a table that was cut says so.

public struct StatsBlock: Sendable, Equatable {
    public struct Item: Sendable, Equatable {
        public var label: String
        public var value: String
        /// "+8 %", "−3": shown as written, never computed.
        public var delta: String?

        public init(label: String, value: String, delta: String? = nil) {
            self.label = label
            self.value = value
            self.delta = delta
        }
    }

    /// More than a row of tiles is a table.
    public static let maxItems = 12
    public var title: String?
    public var items: [Item]

    public init(title: String? = nil, items: [Item]) {
        self.title = title
        self.items = items
    }
}

public struct TableBlock: Sendable, Equatable {
    public static let maxRows = 200
    public static let maxColumns = 12
    public var title: String?
    public var columns: [String]
    /// Every row has exactly `columns.count` cells.
    public var rows: [[String]]
    public var truncated: Bool

    public init(title: String? = nil, columns: [String], rows: [[String]], truncated: Bool = false) {
        self.title = title
        self.columns = columns
        self.rows = rows
        self.truncated = truncated
    }
}

public struct ChartBlock: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable, CaseIterable {
        case bar, line, area, pie, donut, scatter, polar, radar

        /// Parts of a whole and radial charts have no meaning below zero.
        var needsNonNegative: Bool { [.pie, .donut, .polar, .radar].contains(self) }
        /// One value per label and nothing else to compare it against.
        var singleSeries: Bool { [.pie, .donut, .polar].contains(self) }
        /// Only the island paints these; the window card and the PDF show the
        /// same numbers as a table rather than bars under another name.
        public var isIslandOnly: Bool { self == .polar || self == .radar }
        /// Most labels this kind stays legible with; nil is no cap of its own.
        var legibleLabels: Int? {
            switch self {
            case .radar: ChartBlock.maxRadarAxes
            case .pie, .donut, .polar: ChartBlock.maxSlices
            default: nil
            }
        }
        /// Fewer than three axes is a line, not a radar.
        var minLabels: Int { self == .radar ? ChartBlock.minRadarAxes : 1 }
    }

    public struct Series: Sendable, Equatable {
        public var name: String?
        public var values: [Double]

        public init(name: String? = nil, values: [Double]) {
            self.name = name
            self.values = values
        }
    }

    public static let maxSeries = 8
    public static let maxPoints = 500
    public static let minRadarAxes = 3
    /// Legibility caps for the round kinds: past them the labels collide at
    /// the island's canvas and the same numbers read better as a table.
    // HACK: set from the 16m-5a snapshots (24 axes overlapped the pole labels,
    // 20 clears them); never checked against real answers. Revisit when a
    // real chart lands on the cap.
    public static let maxRadarAxes = 20
    public static let maxSlices = 12
    /// Bar, line, area and scatter cost a mark per point per series, and
    /// past a thousand the chart is slower than it is useful.
    // HACK: a round number, not benchmarked. Measure Swift Charts on real
    // answers and move it when a chart of this size feels slow.
    public static let maxCartesianPoints = 1000
    /// Past this a value is a broken number, not a large one: the sums the
    /// painters take would overflow long before the cap on points does.
    // HACK: a flat ceiling far above any real figure; lower it per unit if
    // a chart ever needs to refuse sooner.
    public static let maxMagnitude = 1e12
    public var title: String?
    public var kind: Kind
    public var unit: String?
    public var labels: [String]
    public var series: [Series]

    public init(title: String? = nil, kind: Kind, unit: String? = nil, labels: [String], series: [Series]) {
        self.title = title
        self.kind = kind
        self.unit = unit
        self.labels = labels
        self.series = series
    }

    /// The same numbers as rows, for a kind the painter does not know and
    /// for documents that want the figures beside the drawing.
    public var asTable: TableBlock {
        let columns = [""] + series.enumerated().map { index, serie in serie.name ?? "\(index + 1)" }
        let rows = labels.enumerated().map { index, label in
            [label] + series.map { $0.values.indices.contains(index) ? DataCells.number($0.values[index]) : "" }
        }
        return TableBlock(title: title, columns: columns, rows: rows)
    }
}

enum DataCells {
    /// A cell or a value as the user would write it: 12, 12.5, never 12.0.
    static func text(_ raw: Any?) -> String? {
        guard let raw else { return nil }
        if let text = raw as? String { return text }
        if let value = CompanionBlocks.jsonDouble(raw) { return number(value) }
        return nil
    }

    static func number(_ value: Double) -> String {
        value.rounded() == value && abs(value) < 1e15 ? String(Int64(value)) : String(value)
    }
}

extension CompanionBlocks {
    public static let statsLanguage = "companion:stats"
    public static let tableLanguage = "companion:table"
    public static let chartLanguage = "companion:chart"

    public static func stats(_ body: String) -> StatsBlock? {
        fenceObject(body).flatMap(stats(from:))
    }

    static func stats(from dict: [String: Any]) -> StatsBlock? {
        guard let list = dict["items"] as? [Any] else { return nil }
        var items: [StatsBlock.Item] = []
        for raw in list.prefix(StatsBlock.maxItems) {
            guard let item = raw as? [String: Any],
                  let label = item["label"] as? String,
                  let value = DataCells.text(item["value"]) else { return nil }
            items.append(StatsBlock.Item(label: clean(label), value: clean(value),
                                         delta: DataCells.text(item["delta"]).map(clean)))
        }
        return items.isEmpty ? nil : StatsBlock(title: (dict["title"] as? String).map(clean), items: items)
    }

    public static func table(_ body: String) -> TableBlock? {
        guard let dict = fenceObject(body) else { return nil }
        return table(from: dict)
    }

    static func table(from dict: [String: Any]) -> TableBlock? {
        guard let rawColumns = dict["columns"] as? [Any], let rawRows = dict["rows"] as? [Any] else { return nil }
        let columns = rawColumns.prefix(TableBlock.maxColumns).map { clean(DataCells.text($0) ?? "") }
        guard !columns.isEmpty else { return nil }
        var rows: [[String]] = []
        for raw in rawRows.prefix(TableBlock.maxRows) {
            guard let cells = raw as? [Any] else { return nil }
            let text = cells.prefix(columns.count).map { TextSanitizer.display(DataCells.text($0) ?? "", maxLength: TextSanitizer.maxCell) }
            rows.append(text + Array(repeating: "", count: columns.count - text.count))
        }
        return TableBlock(title: (dict["title"] as? String).map(clean), columns: columns, rows: rows,
                          truncated: rawRows.count > TableBlock.maxRows)
    }

    /// A chart, or the same data as a table when the kind is unknown: the
    /// numbers the model looked up are never thrown away over a word.
    public static func chart(_ body: String) -> CardPayload? {
        guard let dict = fenceObject(body) else { return nil }
        return chart(from: dict)
    }

    static func chart(from dict: [String: Any]) -> CardPayload? {
        guard let rawLabels = dict["labels"] as? [Any], let rawSeries = dict["series"] as? [Any],
              !rawLabels.isEmpty, rawLabels.count <= ChartBlock.maxPoints,
              !rawSeries.isEmpty, rawSeries.count <= ChartBlock.maxSeries else { return nil }
        let labels = rawLabels.map { clean(DataCells.text($0) ?? "") }
        var series: [ChartBlock.Series] = []
        for raw in rawSeries {
            guard let item = raw as? [String: Any], let values = item["values"] as? [Any],
                  values.count == labels.count else { return nil }
            var numbers: [Double] = []
            for value in values {
                guard let number = jsonDouble(value), number.isFinite else { return nil }
                numbers.append(number)
            }
            series.append(ChartBlock.Series(name: (item["name"] as? String).map(clean), values: numbers))
        }
        let rawKind = (dict["kind"] as? String)?.lowercased() ?? ""
        let kind = ChartBlock.Kind(rawValue: rawKind)
        let block = ChartBlock(title: (dict["title"] as? String).map(clean), kind: kind ?? .bar,
                               unit: (dict["unit"] as? String).map(clean), labels: labels, series: series)
        // Whole data that cannot be drawn honestly keeps its numbers as a
        // table; only structurally broken data returns nil (wave 20 rule).
        guard kind != nil, block.drawable else { return .table(block.asTable) }
        return .chart(block)
    }

    static func clean(_ text: String) -> String {
        TextSanitizer.display(text, maxLength: TextSanitizer.maxLabel)
    }
}

extension ChartBlock {
    /// Whether the kind can honestly and legibly draw these numbers. A chart
    /// that would drop a series, a slice or a point, or that is too big to
    /// read or too heavy to paint, is not drawn; the caller keeps the same
    /// numbers as a table (16m-5a).
    var drawable: Bool {
        let values = series.flatMap(\.values)
        guard values.allSatisfy({ abs($0) <= Self.maxMagnitude }) else { return false }
        if kind.legibleLabels == nil, labels.count * series.count > Self.maxCartesianPoints { return false }
        guard labels.count >= kind.minLabels else { return false }
        if let cap = kind.legibleLabels, labels.count > cap { return false }
        if kind.singleSeries, series.count != 1 { return false }
        if kind.needsNonNegative {
            return values.allSatisfy { $0 >= 0 } && values.contains { $0 > 0 }
        }
        return true
    }
}
