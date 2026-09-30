import Foundation

/// Words the ear should get right (spec 16c §2, Incredible's "words it should
/// get right"): what the user typed in Settings, as spelling bias only.
package enum Vocabulary {
    /// The ear keeps its own cap on contextual strings; this one keeps the
    /// setting from growing into a document.
    package static let maxWords = 50
    /// A name or a term, not a sentence.
    static let maxLength = 40

    package static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in text.split(whereSeparator: { $0 == "," || $0.isNewline }) {
            let word = raw.trimmingCharacters(in: .whitespaces)
            guard !word.isEmpty, word.count <= maxLength,
                  seen.insert(word.lowercased()).inserted else { continue }
            out.append(word)
            if out.count == maxWords { break }
        }
        return out
    }

    /// The list page (16g) adds one word at a time; going through `parse`
    /// keeps the same cap, length and duplicate rules as the text field had.
    package static func adding(_ word: String, to text: String) -> String {
        parse(text + "\n" + word).joined(separator: "\n")
    }

    package static func removing(_ word: String, from text: String) -> String {
        let gone = word.lowercased()
        return parse(text).filter { $0.lowercased() != gone }.joined(separator: "\n")
    }
}
