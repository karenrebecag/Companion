import Foundation

/// Wave 16h-1 (criterion 3): a card carries the detail, so the voice says a
/// line and points at it. Once a card is on screen the rest of the turn is
/// at most `maxSentences` sentences and `maxWords` words in total: what was
/// said before the card counts too, or a long preamble would buy a second
/// long answer. Without a card nothing is cut — a plain answer is heard whole.
package struct SpeechBudget: Sendable, Equatable {
    package static let maxWords = 25
    package static let maxSentences = 2

    package var cardShown = false
    private var words = 0
    private var sentences = 0

    package init() {}

    /// The cut as it may be said now; nil when the budget is spent. Every
    /// sentence in the cut counts. A piece that ends in a clause mark
    /// ("Claro que sí,") is not yet a sentence: its rest, in the next cut,
    /// is the same one.
    package mutating func admit(_ cut: String) -> String? {
        var said: [String] = []
        for part in SpeechFilter.sentences(of: cut) {
            guard let next = admitOne(part) else { break }
            said.append(next)
        }
        return said.isEmpty ? nil : said.joined(separator: " ")
    }

    /// The whole reply under the rule, for text that is not streamed.
    package static func brief(_ text: String, hasCard: Bool) -> String {
        var budget = SpeechBudget()
        budget.cardShown = hasCard
        return budget.admit(text) ?? ""
    }

    /// True when the text holds a card that will actually paint: a fence that
    /// fails to parse shows as code, and the voice must not shorten for it.
    package static func hasCard(in text: String) -> Bool {
        guard text.contains("```companion:") else { return false }
        return AnswerBlocks.blocks(from: text).contains {
            // A question with options is a card the voice must not read out.
            if case .card = $0 { return true }
            if case .diagram = $0 { return true }
            return $0.isChoice
        }
    }

    private mutating func admitOne(_ sentence: String) -> String? {
        let all = sentence.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !all.isEmpty else { return nil }
        guard cardShown else { return record(sentence, words: all.count) }
        let room = Self.maxWords - words
        guard sentences < Self.maxSentences, room > 0 else { return nil }
        guard all.count > room else { return record(sentence, words: all.count) }
        words = Self.maxWords
        sentences = Self.maxSentences
        return Self.trimmed(Array(all.prefix(room)))
    }

    /// Up to the last clause that fits whole, so the voice never stops
    /// mid-phrase. With no clause mark in reach, the words that fit: an
    /// added full stop would be heard as a sentence that was never written.
    private static func trimmed(_ words: [String]) -> String {
        let marks: Set<Character> = [",", ";", ":", ".", "!", "?", "…"]
        guard let last = words.lastIndex(where: { $0.last.map(marks.contains) ?? false }) else {
            return words.joined(separator: " ")
        }
        let clause = words[...last].joined(separator: " ")
        guard let end = clause.last, end == "," || end == ";" || end == ":" else { return clause }
        return String(clause.dropLast()) + "."
    }

    private mutating func record(_ sentence: String, words count: Int) -> String {
        words += count
        if let last = sentence.trimmingCharacters(in: .whitespacesAndNewlines).last,
           SpeechFilter.terminators.contains(last) {
            sentences += 1
        }
        return sentence
    }
}
