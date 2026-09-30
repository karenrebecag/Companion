import Foundation

/// The search at the top of Settings (Wave 16g). Matches what the user reads,
/// already localized, so the same query works in whichever language is on.
package enum SettingsSearch {
    package struct Entry: Sendable, Equatable {
        package let id: String
        package let page: String
        package let title: String
        package let subtitle: String

        package init(id: String, page: String, title: String, subtitle: String) {
            self.id = id
            self.page = page
            self.title = title
            self.subtitle = subtitle
        }
    }

    /// Every word of the query has to appear; typing "tamano" without the
    /// tilde is the common case, not the edge case.
    package static func match(_ query: String, in entries: [Entry]) -> [Entry] {
        let words = normalize(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        let found = entries.compactMap { entry -> (Entry, Bool)? in
            let title = normalize(entry.title)
            let all = title + " " + normalize(entry.subtitle)
            guard words.allSatisfy(all.contains) else { return nil }
            return (entry, words.allSatisfy(title.contains))
        }
        return found.filter(\.1).map(\.0) + found.filter { !$0.1 }.map(\.0)
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
