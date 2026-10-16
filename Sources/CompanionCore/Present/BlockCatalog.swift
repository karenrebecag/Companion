import Foundation

/// A visual block outside the present families, found through `find_block`.
/// Static on purpose: a lookup costs no I/O and no model round trip, and the
/// catalog is small enough to match by keyword.
package struct CatalogEntry: Sendable, Equatable {
    package var id: String
    package var whenToUse: String
    /// The data the block takes, as the model must write it.
    package var shape: String
    package var keywords: [String]

    package init(id: String, whenToUse: String, shape: String, keywords: [String]) {
        self.id = id
        self.whenToUse = whenToUse
        self.shape = shape
        self.keywords = keywords
    }
}

package enum BlockCatalog {
    package static let entries: [CatalogEntry] = [
        CatalogEntry(
            id: "json-viewer",
            whenToUse: "a JSON document or API response the reader browses by key",
            shape: "value: any JSON value, nested objects and arrays allowed",
            keywords: ["json", "api", "response", "payload", "object", "raw", "schema", "tree", "document"]),
        CatalogEntry(
            id: "countdown",
            whenToUse: "one deadline or start time to count down to",
            shape: "title, startsAt (ISO 8601)",
            keywords: ["countdown", "deadline", "timer", "remaining", "due", "until", "starts", "launch"]),
        CatalogEntry(
            id: "market-terminal",
            whenToUse: "live market quotes with price, change and volume",
            shape: "symbol, price, change, volume",
            keywords: ["market", "stock", "stocks", "price", "quote", "quotes", "ticker", "trading", "terminal", "crypto", "forex"]),
        CatalogEntry(
            id: "activity-heatmap",
            whenToUse: "daily activity over weeks, one cell per day",
            shape: "days[{date (YYYY-MM-DD), value}]",
            keywords: ["heatmap", "activity", "calendar", "contributions", "daily", "streak", "commits"]),
        CatalogEntry(
            id: "ridgeline",
            whenToUse: "the spread of one quantity across several groups over time",
            shape: "series[{name, values[number]}]",
            keywords: ["ridgeline", "distribution", "distributions", "density", "spread", "histogram"]),
        CatalogEntry(
            id: "slope-chart",
            whenToUse: "one item measured before and after a change, shown as a slope",
            shape: "items[{label, before, after}]",
            keywords: ["slope", "before", "after", "change", "delta", "rank", "shift"]),
        CatalogEntry(
            id: "waffle-chart",
            whenToUse: "a share shown as a grid of squares, where each square is a unit",
            shape: "categories[{label, value}]",
            keywords: ["waffle", "percentage", "share", "grid", "squares", "proportion"]),
        CatalogEntry(
            id: "presence-stack",
            whenToUse: "who is online or present right now",
            shape: "people[{name, status}]",
            keywords: ["presence", "online", "team", "avatars", "available", "here"]),
    ]

    /// Entries whose keywords or use name the query's words, best match first.
    /// Ties keep catalog order, so the same query always returns the same list.
    package static func find(_ query: String, limit: Int = 3) -> [CatalogEntry] {
        let words = Set(tokens(query))
        // Keywords only: the prose of whenToUse is full of words ("a", "the")
        // that would match every entry.
        guard !words.isEmpty, limit > 0 else { return [] }
        let scored: [(entry: CatalogEntry, score: Int)] = entries.map { entry in
            return (entry, words.intersection(entry.keywords).count)
        }
        return scored
            .filter { $0.score > 0 }
            .enumerated()
            .sorted { lhs, rhs in
                lhs.element.score != rhs.element.score
                    ? lhs.element.score > rhs.element.score
                    : lhs.offset < rhs.offset
            }
            .prefix(limit)
            .map(\.element.entry)
    }

    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }
}
