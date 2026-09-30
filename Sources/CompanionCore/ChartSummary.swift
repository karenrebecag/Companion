import Foundation

/// What a chart says in words, for VoiceOver and for a copy: pure, so a test
/// pins the numbers before any view speaks them (16m-5a).
public struct ChartSummary: Sendable, Equatable {
    public struct Extreme: Sendable, Equatable {
        public var label: String
        public var series: String?
        public var value: Double

        /// 12, 12.5 — never 12.0.
        public var valueText: String { ChartBlock.text(value) }

        public init(label: String, series: String?, value: Double) {
            self.label = label
            self.series = series
            self.value = value
        }
    }

    public var kind: ChartBlock.Kind
    public var title: String?
    public var seriesCount: Int
    public var pointCount: Int
    public var maximum: Extreme?
    public var minimum: Extreme?

    public init(_ block: ChartBlock) {
        kind = block.kind
        title = block.title
        seriesCount = block.series.count
        pointCount = block.labels.count
        var high: Extreme?
        var low: Extreme?
        for serie in block.series {
            for (index, value) in serie.values.enumerated() {
                let label = block.labels.indices.contains(index) ? block.labels[index] : "\(index + 1)"
                let point = Extreme(label: label, series: serie.name, value: value)
                // Strict comparisons: the first of equal values names the spot.
                if high == nil || value > high!.value { high = point }
                if low == nil || value < low!.value { low = point }
            }
        }
        maximum = high
        minimum = low
    }
}

extension ChartBlock {
    /// A value as the user would write it: 12, 12.5, never 12.0.
    public static func text(_ value: Double) -> String { DataCells.number(value) }

    /// The data as CSV: it pastes into Numbers or Sheets as the table the
    /// drawing came from.
    public var csv: String {
        let table = asTable
        let header = table.columns.map(Self.csvText)
        let rows = table.rows.map { [Self.csvText($0[0])] + $0.dropFirst().map(Self.csvField) }
        return ([header] + rows).map { $0.joined(separator: ",") }.joined(separator: "\n")
    }

    /// Characters that make a spreadsheet read a cell as a formula or a
    /// command, checked on the first character and on the first non-blank
    /// one (a leading space or em space does not hide the trigger).
    private static let formulaTriggers: Set<Character> = ["=", "+", "-", "@", "\t", "\r", "\n", "\r\n", "|", "%"]

    /// A label the model wrote: defused with a leading quote when risky.
    private static func csvText(_ raw: String) -> String {
        // Invisible characters are dropped first, or a zero-width space in
        // front of "=" would hide the trigger from the check below.
        let text = TextSanitizer.display(raw, maxLength: max(raw.count, 1))
        let risky = text.first.map(formulaTriggers.contains) == true
            || text.first(where: { !$0.isWhitespace }).map(formulaTriggers.contains) == true
        return csvField(risky ? "'" + text : text)
    }

    private static func csvField(_ text: String) -> String {
        guard text.contains(where: { ",\"\n\r".contains($0) }) else { return text }
        return "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
