import Foundation

/// What a finished reply asks of the reader. The result card used to leave
/// after the settle (0.2 s) whatever it held: a 1000-character answer was
/// gone in 289 ms (live 2026-10-16). The time it stays is a function of this.
package struct ReadingLoad: Sendable, Equatable {
    package var words: Int
    /// Table rows and list items: each is a glance of its own.
    package var rows: Int
    /// The card would pass the column's cap and scroll: nobody can say how
    /// long that takes to read, so it has no clock and closes by hand.
    package var needsScroll: Bool

    package init(words: Int, rows: Int, needsScroll: Bool = false) {
        self.words = words
        self.rows = rows
        self.needsScroll = needsScroll
    }
}

package enum ReadingClock {
    package static let base: TimeInterval = 2.5
    /// 0.28 s a word is about 215 words a minute.
    package static let perWord: TimeInterval = 0.28
    package static let perRow: TimeInterval = 0.4
    package static let minimum: TimeInterval = 4
    package static let maximum: TimeInterval = 20

    /// Nil: no clock, the card stays until it is closed or replaced.
    package static func duration(for load: ReadingLoad) -> TimeInterval? {
        guard !load.needsScroll else { return nil }
        let raw = base + perWord * Double(max(0, load.words)) + perRow * Double(max(0, load.rows))
        return min(maximum, max(minimum, raw))
    }

    /// The island's column cap (IslandChrome.columnMaxHeight) at the notch band
    /// of a laptop; the exact figure only moves where scrolling begins.
    static let columnHeight = 560.0
    private static let charsPerLine = 68.0
    private static let lineHeight = 22.0
    private static let rowHeight = 30.0
    /// Title, padding, the continue chip and the gaps between blocks.
    private static let chrome = 150.0

    /// Reads the reply the way the card will lay it out. Nil when there is
    /// nothing to read (a reply of only tool calls), so no clock is armed.
    // HACK: the height is estimated from character counts, not measured.
    // Upgrade trigger: when the view can report its overflow to the session
    // (IslandColumn knows it), send that instead and drop the estimate.
    package static func load(of markdown: String) -> ReadingLoad? {
        var words = 0
        var rows = 0
        var height = chrome
        func prose(_ text: String) {
            words += text.split(whereSeparator: \.isWhitespace).count
            height += (Double(text.count) / charsPerLine).rounded(.up) * lineHeight
        }
        for block in AnswerBlocks.blocks(from: markdown) {
            switch block {
            case .title(let text), .section(let text), .subheading(let text),
                 .paragraph(let text), .quote(let text):
                prose(text)
            case .callout(let title, let body):
                prose(title)
                prose(body)
            case .list(_, let items):
                rows += items.count
                items.forEach { prose($0.text) }
            case .tasks(let lines):
                rows += lines.count
                lines.forEach { prose($0.text) }
            case .table(_, let body):
                rows += body.count
                height += Double(body.count + 1) * rowHeight
            case .code(_, let body):
                height += Double(body.split(separator: "\n", omittingEmptySubsequences: false).count) * lineHeight
            case .card, .diagram, .choice, .fileChip:
                height += rowHeight * 4
            case .rule:
                break
            }
        }
        guard words > 0 || rows > 0 else { return nil }
        return ReadingLoad(words: words, rows: rows, needsScroll: height > columnHeight)
    }
}
