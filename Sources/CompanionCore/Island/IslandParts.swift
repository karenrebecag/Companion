import Foundation

/// The island's menu (spec 16c §2): Incredible's five, in its order.
package enum IslandMenuItem: String, Sendable, Equatable, CaseIterable {
    case settings, openWindow, shortcuts, feedback, clearHistory

    /// Painted red: the one entry that loses something.
    package var destructive: Bool { self == .clearHistory }
}

/// A reply as the island shows it: a title and one line, "Ver →" for the
/// rest. The voice points here instead of reading the list aloud.
package struct IslandResult: Sendable, Equatable {
    package static let maxTitle = 60
    package static let maxLine = 120

    package let title: String
    package let line: String?

    package init?(reply: String) {
        let prose = MarkdownSplitter.islandProse(reply)
        // A card-only reply still has a title to show, never its JSON.
        let source = prose.isEmpty
            ? (MarkdownSplitter.firstCardTitle(String(reply.prefix(MarkdownSplitter.islandWindow))) ?? "")
            : prose
        let lines = source.split(whereSeparator: \.isNewline)
            .map { Self.plain(String($0)) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return nil }
        title = Self.clip(first, Self.maxTitle)
        line = lines.dropFirst().first.map { Self.clip($0, Self.maxLine) }
    }

    /// Headings, bullets, emphasis and code marks are layout, not words.
    static func plain(_ text: String) -> String {
        var line = text.trimmingCharacters(in: .whitespaces)
        while let first = line.first, "#->*".contains(first) {
            line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        for mark in ["**", "__", "`"] { line = line.replacingOccurrences(of: mark, with: "") }
        return line.trimmingCharacters(in: .whitespaces)
    }

    static func clip(_ text: String, _ limit: Int) -> String {
        text.count > limit
            ? String(text.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…" : text
    }
}
