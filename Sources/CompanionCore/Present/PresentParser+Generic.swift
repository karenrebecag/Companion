import Foundation

/// The fallback for a table or comparison that does not validate. The rows
/// are drawn as they came, so the model's numbers stay visible in a table even
/// when the family's own rules refused them.
extension PresentParser {
    static func genericTable(_ family: PresentFamily, _ dict: [String: Any]) -> PresentBlock? {
        guard family == .table || family == .comparison else { return nil }
        let header = headers(dict, "columns") ?? []
        let rows: [[PresentCell]] = bounded(array(dict, "rows") ?? [], max: Limits.maxRows).compactMap { row in
            guard let cells = rowCells(row) else { return nil }
            return cells.map { cell($0) ?? .text("") }
        }
        let width = min(max(header.count, rows.map(\.count).max() ?? 0), Limits.maxColumns)
        guard !rows.isEmpty, width > 0 else { return nil }
        let columns = (0..<width).map { $0 < header.count ? header[$0] : "" }
        let padded = rows.map { row in (0..<width).map { $0 < row.count ? row[$0] : .text("") } }
        return .table(PresentTable(title: optionalText(dict, "title"), columns: columns, rows: padded))
    }
}
