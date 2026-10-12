import CompanionCore
import CompanionUIPro
import Foundation

/// What the island's result card is made of, decided apart from the view so
/// the mapping from a receipt, the touched apps and a reply's sources is
/// checked without drawing anything.
enum IslandResultCardModel {
    /// The card's chips and, for the ones that can be opened, where they go.
    struct Links: Equatable {
        var chips: [AIResultLink]
        /// Chip id -> address. Empty means the chips are plain labels.
        var urls: [String: URL]

        static let none = Links(chips: [], urls: [:])
    }

    static let titleMax = 60

    /// Sources are the only chips that can open: Companion has no road to
    /// launch an app from the island (the UI never activates apps), so app
    /// names are labels and appear only when there is nothing to open. Mixing
    /// them would make a chip that looks like a button and does nothing.
    static func links(apps: [String], sources: [MarkdownSplitter.SourceLink]) -> Links {
        var seen = Set<URL>()
        var chips: [AIResultLink] = []
        var urls: [String: URL] = [:]
        for source in sources {
            guard let url = webURL(source.url), seen.insert(url).inserted else { continue }
            let id = "source.\(chips.count)"
            let label = source.title.isEmpty ? (url.host ?? source.url) : source.title
            chips.append(AIResultLink(id: id, label: label, kind: .source))
            urls[id] = url
        }
        if !chips.isEmpty { return Links(chips: chips, urls: urls) }
        var named = Set<String>()
        let labels = apps.map(IslandReel.shown).filter { !$0.isEmpty && named.insert($0).inserted }
        return Links(
            chips: labels.enumerated().map { AIResultLink(id: "app.\($0.offset)", label: $0.element, kind: .app) },
            urls: [:])
    }

    /// Model-chosen addresses: only http(s) leaves the island.
    static func webURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host != nil
        else { return nil }
        return url
    }

    /// The header names what was asked, on one line; with no question the
    /// fallback stands in.
    static func title(question: String?, fallback: String) -> String {
        let flat = (question ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !flat.isEmpty else { return fallback }
        guard flat.count > titleMax else { return flat }
        return flat.prefix(titleMax - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Prose without its "Sources" list: the chips carry them, and the same
    /// links as bare text above would say them twice.
    static func proseAndSources(of reply: String) -> (prose: String, sources: [MarkdownSplitter.SourceLink]) {
        let window = String(reply.prefix(MarkdownSplitter.islandWindow))
        let split = MarkdownSplitter.extractSources(MarkdownSplitter.split(window))
        guard !split.web.isEmpty else { return (reply, []) }
        return (MarkdownSplitter.plainText(split.rest), split.web)
    }
}
