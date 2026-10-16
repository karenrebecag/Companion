import CompanionCore
import SwiftUI

/// The inks, type and rules a table is drawn with. The card, the notch and the
/// document each bring their own; the sorting never changes.
struct SortableTableStyle {
    var headerFont: Font
    var cellFont: Font
    var headerInk: Color
    var activeInk: Color
    var cellInk: Color
    /// Between body rows; nil draws none.
    var rowLine: Color?
    var lineExtra: CGFloat = 0
    var padX: CGFloat = Space.none
    var padY: CGFloat = Space.none
    /// Cells read inline markdown (bold, code) instead of showing it raw.
    var marked = false

    static let card = SortableTableStyle(
        headerFont: .uiCaption.weight(.semibold), cellFont: .uiBody,
        headerInk: Semantic.mutedForeground, activeInk: Semantic.foreground,
        cellInk: Semantic.foreground, rowLine: nil)
}

/// The grid every table shares: a tap on a header sorts by that column, the
/// active chevron shows the direction, and a figure column sorts by value and
/// sits on the right so the digits line up. Cells wrap in full; nothing is cut.
struct SortableTableGrid: View {
    let columns: [String]
    let rows: [[String]]
    /// The caller owns the sort: a table inside a layout switch (ViewThatFits)
    /// would otherwise lose it each time the layout changes.
    @Binding var order: TableSort.Order?
    var style = SortableTableStyle.card

    var body: some View {
        let numeric = columns.indices.map { TableSort.isNumeric(column: $0, rows: rows) }
        let shown = order.map { TableSort.sorted(rows, by: $0) } ?? rows
        Grid(alignment: .leading, horizontalSpacing: Space.x4, verticalSpacing: Space.x2) {
            GridRow {
                ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                    header(column, index: index, numeric: numeric[index])
                }
            }
            Divider()
            ForEach(Array(shown.enumerated()), id: \.offset) { index, row in
                GridRow {
                    ForEach(Array(columns.indices), id: \.self) { index in
                        cell(Self.text(row, index), numeric: numeric[index])
                    }
                }
                if let rowLine = style.rowLine, index < shown.count - 1 {
                    Divider().overlay(rowLine).gridCellUnsizedAxes(.vertical)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func text(_ row: [String], _ index: Int) -> String {
        row.indices.contains(index) ? row[index] : ""
    }

    /// Every header shows the sort control, so the table reads as sortable
    /// before the first tap.
    private func header(_ column: String, index: Int, numeric: Bool) -> some View {
        let sorted = order?.column == index ? order : nil
        return Button {
            order = TableSort.tapped(order, column: index)
        } label: {
            HStack(spacing: Space.x1) {
                label(column)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: chevron(sorted?.direction))
                    .font(.uiCaption)
                    .foregroundStyle(sorted == nil ? style.headerInk : style.activeInk)
                    .accessibilityHidden(true)
            }
            .font(style.headerFont)
            .foregroundStyle(sorted == nil ? style.headerInk : style.activeInk)
            .padding(.horizontal, style.padX)
            .padding(.vertical, style.padY)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .gridColumnAlignment(numeric ? .trailing : .leading)
        .accessibilityLabel(column)
        .accessibilityValue(sortedWord(sorted?.direction))
    }

    private func cell(_ value: String, numeric: Bool) -> some View {
        label(value)
            .font(style.cellFont)
            .foregroundStyle(style.cellInk)
            .lineSpacing(style.lineExtra)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, style.padX)
            .padding(.vertical, style.padY)
            .monospacedDigit()
            .textSelection(.enabled)
            .gridColumnAlignment(numeric ? .trailing : .leading)
    }

    @ViewBuilder
    private func label(_ value: String) -> some View {
        if style.marked {
            Text(AnswerInline.rich(value))
        } else {
            Text(value)
        }
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

/// A table with nothing else to hold its sort.
struct OwnedSortTable: View {
    let columns: [String]
    let rows: [[String]]
    var style = SortableTableStyle.card

    @State private var order: TableSort.Order?

    var body: some View {
        SortableTableGrid(columns: columns, rows: rows, order: $order, style: style)
    }
}
