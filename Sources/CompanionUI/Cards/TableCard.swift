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

    /// The rows past the cap are not on the card.
    private var grid: some View {
        SortableTableGrid(columns: block.columns, rows: Self.visibleRows(block), order: $order)
    }
}
