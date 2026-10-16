import CompanionCore
import SwiftUI

/// Rows under a header, and every column sorts on a tap. A figure column sorts
/// by value and sits on the right, so the digits line up. The table takes the
/// card's full width; a table wider than that scrolls sideways.
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
        VStack(alignment: .leading, spacing: Space.x3) {
            DataCardTitle(title: block.title)
            // The grid is only wrapped in a scroll view when it does not fit:
            // a scroll view stretches to its maximum and left a band of empty
            // space under short tables.
            ViewThatFits(in: .horizontal) {
                grid
                ScrollView(.horizontal, showsIndicators: false) { grid }
            }
            if Self.isCut(block) {
                Text(String(format: Localized.string("card.table.truncated"), TableBlock.maxRows))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    /// Sorts what is on the card: the rows past the cap are not on it.
    private var grid: some View {
        let shown = Self.visibleRows(block)
        let numeric = block.columns.indices.map { TableSort.isNumeric(column: $0, rows: shown) }
        let rows = order.map { TableSort.sorted(shown, by: $0) } ?? shown
        return Grid(alignment: .leading, horizontalSpacing: Space.x4, verticalSpacing: Space.x2) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func text(_ row: [String], _ index: Int) -> String {
        row.indices.contains(index) ? row[index] : ""
    }

    /// Every header shows the sort control, so the table reads as sortable
    /// before the first tap; the active column's chevron shows its direction.
    private func header(_ column: String, index: Int, numeric: Bool) -> some View {
        let sorted = order?.column == index ? order : nil
        return Button {
            order = TableSort.tapped(order, column: index)
        } label: {
            HStack(spacing: Space.x1) {
                Text(column)
                Image(systemName: chevron(sorted?.direction))
                    .font(.uiCaption)
                    .foregroundStyle(sorted == nil ? Semantic.mutedForeground : Semantic.foreground)
                    .accessibilityHidden(true)
            }
            .font(.uiCaption.weight(.semibold))
            .foregroundStyle(sorted == nil ? Semantic.mutedForeground : Semantic.foreground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .gridColumnAlignment(numeric ? .trailing : .leading)
        .accessibilityLabel(column)
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

    private func chevron(_ direction: TableSort.Direction?) -> String {
        switch direction {
        case .ascending: "chevron.up"
        case .descending: "chevron.down"
        case nil: "chevron.up.chevron.down"
        }
    }

    private func sortedWord(_ direction: TableSort.Direction?) -> String {
        switch direction {
        case .ascending: Localized.string("card.sort.ascending")
        case .descending: Localized.string("card.sort.descending")
        case nil: ""
        }
    }
}
