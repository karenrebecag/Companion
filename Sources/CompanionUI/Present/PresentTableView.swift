import CompanionCore
import CompanionUIPro
import SwiftUI

/// A table that sorts by column. Past the filter threshold it also gets a
/// toolbar for the columns that hold a few repeated words, since those are
/// the ones a filter answers.
struct PresentTableView: View {
    let table: PresentTable
    let measures: PresentMeasures
    let filterable: Bool

    @State private var filters: [FilterChip] = []

    private struct Row: Identifiable {
        let id: String
        let cells: [PresentCell]
    }

    private var rows: [Row] {
        table.rows.enumerated().map { Row(id: "\($0.offset)", cells: $0.element) }
    }

    /// Columns with two to eight distinct words: a filter on a column where
    /// every row differs is a search box with extra steps.
    private var fields: [FilterField] {
        guard filterable else { return [] }
        return table.columns.indices.compactMap { column in
            let words = table.rows.compactMap { row -> String? in
                if case .text(let text) = row[column], !text.isEmpty { return text }
                return nil
            }
            let distinct = Array(Set(words)).sorted()
            guard words.count == table.rows.count, (2...8).contains(distinct.count) else { return nil }
            return FilterField(id: "\(column)", label: table.columns[column], options: distinct)
        }
    }

    private var shown: [Row] {
        rows.filter { row in
            filters.allSatisfy { chip in
                guard let column = Int(chip.id), row.cells.indices.contains(column) else { return true }
                return row.cells[column].display == chip.value
            }
        }
    }

    private var columns: [DataColumn<Row>] {
        table.columns.indices.map { column in
            DataColumn<Row>(
                id: "\(column)", title: table.columns[column],
                value: { row in
                    switch row.cells[column] {
                    case .number(let value): .number(value)
                    case .text(let text): text.isEmpty ? .missing : .text(text)
                    }
                },
                cell: { row in
                    AnyView(
                        Text(row.cells[column].display)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity, alignment: .leading))
                })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            if !fields.isEmpty {
                FilterToolbar(
                    filters: filters, fields: fields, label: Localized.string("present.filter.active"),
                    onAdd: { chip in
                        filters = filters.filter { $0.id != chip.id } + [chip]
                    },
                    onRemove: { id in filters = filters.filter { $0.id != id } },
                    onClearAll: { filters = [] })
            }
            SortableDataTable(
                rows: shown, columns: columns, rowID: { $0.id },
                caption: PresentStrings.label(table.title, fallback: "present.table"),
                emptyMessage: Localized.string("present.table.empty"),
                itemName: (Localized.string("present.rows.one"), Localized.string("present.rows.other")))
        }
    }
}
