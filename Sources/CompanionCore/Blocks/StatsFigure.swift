import Foundation

// A figure the model wrote as text ("1,234.5 %", "$12") counted up on the card.
// Only the number moves; the prefix, the suffix and the decimals are kept as
// written, so the count ends on exactly the figure the model gave.

package struct StatsFigure: Sendable, Equatable {
    package var prefix: String
    package var number: Double
    package var decimals: Int
    package var suffix: String

    package init?(_ text: String) {
        guard let match = text.trimmingCharacters(in: .whitespaces)
            .wholeMatch(of: /(\D*?)([+\-\u{2212}]?\d[\d,]*(?:\.\d+)?)(.*)/),
            let number = TableSort.number(String(match.2))
        else { return nil }
        self.prefix = String(match.1)
        self.number = number
        self.decimals = match.2.split(separator: ".", omittingEmptySubsequences: false).dropFirst().first?.count ?? 0
        self.suffix = String(match.3)
    }

    /// The figure at a point of the count, with the same decimals and frame.
    package func text(at value: Double) -> String {
        let digits = value.formatted(.number.precision(.fractionLength(decimals)))
        return prefix + digits + suffix
    }
}
