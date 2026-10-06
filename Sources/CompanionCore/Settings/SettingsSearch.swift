import Foundation

/// The search at the top of Settings (Wave 16g). Matches what the user reads,
/// already localized, so the same query works in whichever language is on.
package enum SettingsSearch {
    package struct Entry: Sendable, Equatable {
        package let id: String
        package let page: String
        package let title: String
        package let subtitle: String
        /// Synonyms and the other language. The label still outranks them.
        package let keywords: [String]
        /// The page this row sits on. Weakest match, so a row wins on its own name.
        package let pageTitle: String

        package init(
            id: String, page: String, title: String, subtitle: String,
            keywords: [String] = [], pageTitle: String = ""
        ) {
            self.id = id
            self.page = page
            self.title = title
            self.subtitle = subtitle
            self.keywords = keywords
            self.pageTitle = pageTitle
        }

        /// A page entry opens the page and does not scroll to a row.
        var isPage: Bool { id.hasPrefix("settings.tab.") }
    }

    /// Longest query read; a pasted page of text costs the same as a short one.
    static let maxQueryCharacters = 64
    static let maxQueryWords = 8

    /// Each word has to lead a word: the label, else a keyword, else the page
    /// name. A page's label sits just under a row's, so the page is found and
    /// the row still wins when the word is the row's own name. The list is not
    /// cut here; the rail shows its own top.
    /// Rows order by their weakest word first, then the next weakest: a sum would
    /// let a title plus a page hit beat two keyword hits. Ties keep input order,
    /// because `sorted` is not documented as stable.
    /// Typing "tamano" without the tilde is the common case, not the edge case.
    /// local reference; brief ajustes-hoja-incredible S2
    package static func match(_ query: String, in entries: [Entry]) -> [Entry] {
        let words = Array(tokens(String(query.prefix(maxQueryCharacters))).prefix(maxQueryWords))
        guard !words.isEmpty else { return [] }
        let found = entries.enumerated().compactMap { index, entry -> (index: Int, ranks: [Int], entry: Entry)? in
            let fields = Fields(entry)
            var ranks: [Int] = []
            for word in words {
                guard let rank = fields.rank(of: word) else { return nil }
                ranks.append(rank)
            }
            return (index, ranks.sorted(), entry)
        }
        return found.sorted {
            $0.ranks == $1.ranks ? $0.index < $1.index : $0.ranks.lexicographicallyPrecedes($1.ranks, by: >)
        }.map(\.entry)
    }

    /// An entry's words, split once per call and not once per query word.
    private struct Fields {
        let isPage: Bool
        let title: [String]
        let secondary: [String]
        let page: [String]

        init(_ entry: Entry) {
            isPage = entry.isPage
            title = SettingsSearch.tokens(entry.title)
            secondary = SettingsSearch.tokens(([entry.subtitle] + entry.keywords).joined(separator: " "))
            page = SettingsSearch.tokens(entry.pageTitle)
        }

        /// A row's label, then a page's label, then a keyword, then the page name.
        func rank(of word: String) -> Int? {
            if title.contains(where: { $0.hasPrefix(word) }) { return isPage ? 3 : 4 }
            if secondary.contains(where: { $0.hasPrefix(word) }) { return 2 }
            if page.contains(where: { $0.hasPrefix(word) }) { return 1 }
            return nil
        }
    }

    static func tokens(_ text: String) -> [String] {
        normalize(text).split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
