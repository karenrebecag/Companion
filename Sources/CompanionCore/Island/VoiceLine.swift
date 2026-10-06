import Foundation

/// P3: what the voice says in passive, as Incredible's voice line chip shows it
/// (referencia local): the turn's words cut into sentences, the one being said, and a
/// label for assistive tech.
package struct VoiceLine: Sendable, Equatable {
    package let turn: UUID
    package let words: [String]
    package let lines: [[String]]
    package let current: Int
    package let settled: Bool
    package let label: String

    /// Incredible draws only the last 600 words of a turn; a runaway reply stays bounded.
    package static let wordLimit = 600
    /// A word with no spaces would pass the word cap at any length; cut it so the chip stays bounded.
    package static let wordCharLimit = 64
    /// How long the chip stays once the turn is over, and how long it takes to leave.
    package static let lingerAfterSettle: TimeInterval = 6
    package static let leave: TimeInterval = 0.26

    /// A sentence ends on . ! ? or an ellipsis, even when a closing quote or bracket
    /// follows; what is left unclosed is the last line.
    package static func lines(_ words: [String]) -> [[String]] {
        var lines: [[String]] = []
        var line: [String] = []
        for word in words {
            line.append(word)
            if endsSentence(word) {
                lines.append(line)
                line = []
            }
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }

    /// The first line with a word still unsaid; once all is said, the last.
    package static func current(_ lines: [[String]], spoken: Int) -> Int {
        var said = 0
        for (index, line) in lines.enumerated() {
            said += line.count
            if said > spoken { return index }
        }
        return max(lines.count - 1, 0)
    }

    /// Nil unless the turn is quiet (the island is not carrying it) and has words.
    package static func make(
        turn: UUID, text: String, spoken: Int, settled: Bool, cards: [String], quiet: Bool
    ) -> VoiceLine? {
        let all = text.split(whereSeparator: \.isWhitespace).map { String($0.prefix(wordCharLimit)) }
        guard quiet, !all.isEmpty else { return nil }
        let dropped = max(all.count - wordLimit, 0)
        let words = Array(all.suffix(wordLimit))
        let lines = lines(words)
        return VoiceLine(
            turn: turn, words: words, lines: lines,
            current: current(lines, spoken: max(spoken - dropped, 0)), settled: settled,
            label: cards.isEmpty ? words.joined(separator: " ") : cards.joined(separator: ", "))
    }

    private static let closers: Set<Character> = ["\"", "'", "\u{201D}", "\u{2019}", ")", "]"]
    private static let enders: Set<Character> = [".", "!", "?", "\u{2026}"]

    private static func endsSentence(_ word: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: .whitespaces)
        guard let last = trimmed.reversed().first(where: { !closers.contains($0) }) else { return false }
        return enders.contains(last)
    }
}
