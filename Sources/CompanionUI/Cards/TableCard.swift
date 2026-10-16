import CompanionCore
import SwiftUI

/// Rows under a header that stays, and every column sorts on a tap. A figure
/// column sorts by value and sits on the right, so the digits line up.
struct TableCard: View {
    let block: TableBlock

    @State private var order: TableSort.Order?

    /// A table born from a chart can carry 500 rows, which the grid would
    /// lay out whole; the card shows the same first rows a fence table does.
    static func visibleRows(_ block: TableBlock) -> [[String]] {
        Array(block.rows.prefix(TableBlock.maxRows))
    }

    static func isCut(_ block: TableBlock) -> Bool {
        block.truncated || block.rows.count > TableBlock.maxRows
    }

    var body: some View {
        let shown = Self.visibleRows(block)
        let numeric = block.columns.indices.map { TableSort.isNumeric(column: $0, rows: shown) }
        // Sorts what is on the card: the rows past the cap are not on it.
        let rows = order.map { TableSort.sorted(shown, by: $0) } ?? shown
        VStack(alignment: .leading, spacing: Space.x3) {
            DataCardTitle(title: block.title)
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: Space.x4, verticalSpacing: Space.x2) {
                    GridRow {
                        ForEach(Array(block.columns.enumerated()), id: \.offset) { index, column in
                            header(column, index: index, numeric: numeric[index])
                        }
                    }
                    Divider()
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(block.columns.indices), id: \.self) { index in
                                cell(Self.text(row, index), numeric: numeric[index])
                            }
                        }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
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

    private static func text(_ row: [String], _ index: Int) -> String {
        row.indices.contains(index) ? row[index] : ""
    }

    private func header(_ column: String, index: Int, numeric: Bool) -> some View {
        let sorted = order?.column == index ? order : nil
        return Button {
            order = TableSort.tapped(order, column: index)
        } label: {
            HStack(spacing: Space.x1) {
                Text(column)
                if let sorted {
                    Image(systemName: sorted.direction == .ascending ? "arrow.up" : "arrow.down")
                        .font(.uiCaption)
                }
            }
            .font(.uiCaption.weight(.semibold))
            .foregroundStyle(Semantic.mutedForeground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .gridColumnAlignment(numeric ? .trailing : .leading)
        .accessibilityValue(sortedWord(sorted?.direction))
    }

    private func cell(_ text: String, numeric: Bool) -> some View {
        Text(text)
            .font(.uiBody)
            .monospacedDigit()
            .foregroundStyle(Semantic.foreground)
            .textSelection(.enabled)
            .gridColumnAlignment(numeric ? .trailing : .leading)
    }

    private func sortedWord(_ direction: TableSort.Direction?) -> String {
        switch direction {
        case .ascending: Localized.string("card.sort.ascending")
        case .descending: Localized.string("card.sort.descending")
        case nil: ""
        }
    }
}
