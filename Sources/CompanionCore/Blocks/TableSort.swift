import Foundation

// A column sorts by value when every filled cell is a number. Text compares
// with the locale's collation: a lexical order would put "10" before "9" in a
// revenue column, which is the one mistake a sorted table must not make.

package enum TableSort {
    package enum Direction: Sendable, Equatable {
        case ascending, descending

        package var toggled: Direction { self == .ascending ? .descending : .ascending }
    }

    package struct Order: Sendable, Equatable {
        package var column: Int
        package var direction: Direction

        package init(column: Int, direction: Direction) {
            self.column = column
            self.direction = direction
        }
    }

    /// The header tap: a new column starts ascending, the same one flips.
    package static func tapped(_ current: Order?, column: Int) -> Order {
        guard let current, current.column == column else {
            return Order(column: column, direction: .ascending)
        }
        return Order(column: column, direction: current.direction.toggled)
    }

    /// Figures as the model copies them: "1,234.5", "12 %", "$3", "−4".
    /// Anything else, including "NaN" and "inf", is not a number.
    package static func number(_ cell: String) -> Double? {
        var text = cell.filter { !$0.isWhitespace && !"%$€£".contains($0) }
        text = text.replacingOccurrences(of: "\u{2212}", with: "-")
        if text.range(of: #"^[+-]?\d{1,3}(,\d{3})+(\.\d+)?$"#, options: .regularExpression) != nil {
            text = text.replacingOccurrences(of: ",", with: "")
        }
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }

    /// Numeric when every filled cell reads as a number; an empty column is text.
    package static func isNumeric(column: Int, rows: [[String]]) -> Bool {
        let filled = rows.compactMap { row -> String? in
            guard row.indices.contains(column), !row[column].isEmpty else { return nil }
            return row[column]
        }
        return !filled.isEmpty && filled.allSatisfy { number($0) != nil }
    }

    /// Empty cells sort last in both directions: they are missing, not small.
    package static func sorted(_ rows: [[String]], by order: Order) -> [[String]] {
        let numeric = isNumeric(column: order.column, rows: rows)
        let keyed = rows.enumerated().map { index, row in (index, row, cell(row, order.column)) }
        return keyed.sorted { lhs, rhs in
            let (left, right) = (lhs.2, rhs.2)
            if left.isEmpty != right.isEmpty { return right.isEmpty }
            if left.isEmpty { return lhs.0 < rhs.0 }
            let ascending = order.direction == .ascending
            let result: ComparisonResult
            if numeric, let a = number(left), let b = number(right) {
                result = a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
            } else {
                result = left.localizedStandardCompare(right)
            }
            if result == .orderedSame { return lhs.0 < rhs.0 }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
        .map(\.1)
    }

    private static func cell(_ row: [String], _ column: Int) -> String {
        row.indices.contains(column) ? row[column] : ""
    }
}
