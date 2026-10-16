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
    @MainActor static func links(
        apps: [String], sources: [MarkdownSplitter.SourceLink],
        appName: (String) -> String = { localizedAppName($0, language: Localized.language()) }
    ) -> Links {
        var seen = Set<URL>()
        var chips: [AIResultLink] = []
        var urls: [String: URL] = [:]
        for source in sources {
            guard let url = webURL(source.url), seen.insert(url).inserted else { continue }
            let id = "source.\(chips.count)"
            let label = source.title.isEmpty ? readableHost(url) : source.title
            chips.append(AIResultLink(id: id, label: label, kind: .source))
            urls[id] = url
        }
        if !chips.isEmpty { return Links(chips: chips, urls: urls) }
        var named = Set<String>()
        // The touched list also carries the addresses a step opened: a chip
        // reads "google.com", not the whole query string.
        let labels = apps.map { webURL($0).map(readableHost) ?? appName($0) }
            .map(IslandReel.shown).filter { !$0.isEmpty && named.insert($0).inserted }
        return Links(
            chips: labels.enumerated().map { AIResultLink(id: "app.\($0.offset)", label: $0.element, kind: .app) },
            urls: [:])
    }

    /// "https://www.google.com/search?q=x" -> "google.com".
    static func readableHost(_ url: URL) -> String {
        let host = url.host ?? url.absoluteString
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The system's own name for an app the model called by its English name
    /// ("Notes" -> "Notas" on a Spanish Mac): what the Finder shows for the
    /// bundle. An app that is not found keeps the name it came with.
    nonisolated static func localizedAppName(_ name: String, language: AppLanguage) -> String {
        let bare = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !bare.isEmpty, !bare.contains("/") else { return name }
        let folders = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                       "/Applications/Utilities", NSHomeDirectory() + "/Applications"]
        for folder in folders {
            let path = "\(folder)/\(bare).app"
            if FileManager.default.fileExists(atPath: path) {
                // The app's own language first: displayName follows the
                // system's, which may not be the one Companion speaks.
                return loctableName(appPath: path, language: language)
                    ?? FileManager.default.displayName(atPath: path)
            }
        }
        return name
    }

    /// System apps keep their per-language names in one InfoPlist.loctable.
    nonisolated private static func loctableName(appPath: String, language: AppLanguage) -> String? {
        let table = NSDictionary(contentsOfFile: appPath + "/Contents/Resources/InfoPlist.loctable")
        guard let strings = table?[language.rawValue] as? [String: Any] else { return nil }
        let name = (strings["CFBundleDisplayName"] ?? strings["CFBundleName"]) as? String
        return name?.isEmpty == false ? name : nil
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

    /// A reply that opens with a heading already has its title. The question
    /// used to stand in for it, which printed the user's own sentence cut
    /// mid-word above an answer that then repeated its real title in the body.
    static func splitHeading(_ blocks: [AnswerBlock]) -> (title: String?, body: [AnswerBlock]) {
        guard let first = blocks.first else { return (nil, blocks) }
        switch first {
        case .title(let text), .section(let text), .subheading(let text):
            let line = title(question: text, fallback: "")
            return line.isEmpty ? (nil, blocks) : (line, Array(blocks.dropFirst()))
        default:
            return (nil, blocks)
        }
    }

    /// Prose without its "Sources" list: the chips carry them, and the same
    /// links as bare text above would say them twice.
    static func proseAndSources(of reply: String) -> (prose: String, sources: [MarkdownSplitter.SourceLink]) {
        let window = String(reply.prefix(MarkdownSplitter.islandWindow))
        let split = MarkdownSplitter.extractSources(MarkdownSplitter.split(window))
        guard !split.web.isEmpty else { return (reply, []) }
        return (MarkdownSplitter.plainText(split.rest), split.web)
    }

    /// What the result document paints from a reply: its own structure (the
    /// table stays a table, the bullets stay bullets) without the sources
    /// list the chips carry, the cards and fences the inline visuals draw,
    /// and the question the choice card already asks.
    static func document(of reply: String) -> (blocks: [AnswerBlock], sources: [MarkdownSplitter.SourceLink]) {
        let window = String(reply.prefix(MarkdownSplitter.islandWindow))
        let split = MarkdownSplitter.extractSources(MarkdownSplitter.split(window))
        let blocks = AnswerBlocks.blocks(parts: split.rest, endsInsideFence: MarkdownSplitter.endsInsideFence(window))
        return (blocks.compactMap(spoken), split.web)
    }

    /// The same filter the voice and the card's words use, so a tag meant for
    /// the model never paints; a block with nothing left is dropped.
    private static func spoken(_ block: AnswerBlock) -> AnswerBlock? {
        func clean(_ text: String) -> String { SpeechFilter.clean(text).trimmingCharacters(in: .whitespacesAndNewlines) }
        switch block {
        case .paragraph(let text): return nonEmpty(clean(text)).map(AnswerBlock.paragraph)
        case .title(let text): return nonEmpty(clean(text)).map(AnswerBlock.title)
        case .section(let text): return nonEmpty(clean(text)).map(AnswerBlock.section)
        case .subheading(let text): return nonEmpty(clean(text)).map(AnswerBlock.subheading)
        case .list(let ordered, let items):
            let kept = items.compactMap { item -> MarkdownSplitter.Item? in
                guard let text = nonEmpty(clean(item.text)) else { return nil }
                return MarkdownSplitter.Item(depth: item.depth, text: text)
            }
            return kept.isEmpty ? nil : .list(ordered: ordered, items: kept)
        // Drawn elsewhere on the card, or answered from it.
        case .card, .diagram, .choice: return nil
        default: return block
        }
    }

    private static func nonEmpty(_ text: String) -> String? { text.isEmpty ? nil : text }
}

