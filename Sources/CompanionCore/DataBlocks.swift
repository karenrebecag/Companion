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
        case bar, line, area, pie, donut, scatter
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
            [label] + series.map { DataCells.number($0.values[index]) }
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
        jsonObject(body).flatMap(stats(from:))
    }

    static func stats(from dict: [String: Any]) -> StatsBlock? {
        guard let list = dict["items"] as? [Any] else { return nil }
        var items: [StatsBlock.Item] = []
        for raw in list.prefix(StatsBlock.maxItems) {
            guard let item = raw as? [String: Any],
                  let label = item["label"] as? String,
                  let value = DataCells.text(item["value"]) else { return nil }
            items.append(StatsBlock.Item(label: label, value: value, delta: DataCells.text(item["delta"])))
        }
        return items.isEmpty ? nil : StatsBlock(title: dict["title"] as? String, items: items)
    }

    public static func table(_ body: String) -> TableBlock? {
        guard let dict = jsonObject(body) else { return nil }
        return table(from: dict)
    }

    static func table(from dict: [String: Any]) -> TableBlock? {
        guard let rawColumns = dict["columns"] as? [Any], let rawRows = dict["rows"] as? [Any] else { return nil }
        let columns = rawColumns.prefix(TableBlock.maxColumns).map { DataCells.text($0) ?? "" }
        guard !columns.isEmpty else { return nil }
        var rows: [[String]] = []
        for raw in rawRows.prefix(TableBlock.maxRows) {
            guard let cells = raw as? [Any] else { return nil }
            let text = cells.prefix(columns.count).map { DataCells.text($0) ?? "" }
            rows.append(text + Array(repeating: "", count: columns.count - text.count))
        }
        return TableBlock(title: dict["title"] as? String, columns: columns, rows: rows,
                          truncated: rawRows.count > TableBlock.maxRows)
    }

    /// A chart, or the same data as a table when the kind is unknown: the
    /// numbers the model looked up are never thrown away over a word.
    public static func chart(_ body: String) -> CardPayload? {
        guard let dict = jsonObject(body) else { return nil }
        return chart(from: dict)
    }

    static func chart(from dict: [String: Any]) -> CardPayload? {
        guard let rawLabels = dict["labels"] as? [Any], let rawSeries = dict["series"] as? [Any] else { return nil }
        let labels = rawLabels.prefix(ChartBlock.maxPoints).map { DataCells.text($0) ?? "" }
        guard !labels.isEmpty else { return nil }
        var series: [ChartBlock.Series] = []
        for raw in rawSeries.prefix(ChartBlock.maxSeries) {
            guard let item = raw as? [String: Any], let values = item["values"] as? [Any],
                  values.count >= labels.count else { return nil }
            var numbers: [Double] = []
            for value in values.prefix(labels.count) {
                guard let number = jsonDouble(value), number.isFinite else { return nil }
                numbers.append(number)
            }
            series.append(ChartBlock.Series(name: item["name"] as? String, values: numbers))
        }
        guard !series.isEmpty else { return nil }
        let rawKind = (dict["kind"] as? String)?.lowercased() ?? ""
        let block = ChartBlock(title: dict["title"] as? String, kind: ChartBlock.Kind(rawValue: rawKind) ?? .bar,
                               unit: dict["unit"] as? String, labels: labels, series: series)
        return ChartBlock.Kind(rawValue: rawKind) == nil ? .table(block.asTable) : .chart(block)
    }
}
