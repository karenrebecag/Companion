import Foundation

public enum SentenceSplitter: Sendable {
    private static let terminators: Set<Character> = [".", "!", "?", "…"]

    public static func takeSentence(_ buffer: String,
                                    minChars: Int = 25) -> (sentence: String, rest: String)? {
        var count = 0
        var i = buffer.startIndex
        while i < buffer.endIndex {
            count += 1
            if buffer[i] == "\n", count >= minChars {
                let sentence = String(buffer[..<i])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let rest = String(buffer[buffer.index(after: i)...])
                if !sentence.isEmpty { return (sentence, rest) }
            }
            if terminators.contains(buffer[i]), count >= minChars {
                let next = buffer.index(after: i)
                // Terminator at EOF: still might be "3." of "3.14" or an unfinished token.
                if next == buffer.endIndex { return nil }
                if buffer[next] == " " || buffer[next] == "\n" {
                    let sentence = String(buffer[..<next])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let rest = String(buffer[next...].drop(while: { $0 == " " || $0 == "\n" }))
                    if !sentence.isEmpty { return (sentence, rest) }
                }
            }
            i = buffer.index(after: i)
        }
        return nil
    }

    public static func splitFirstSentence(_ text: String) -> (String, String?) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var count = 0
        var i = trimmed.startIndex
        while i < trimmed.endIndex {
            count += 1
            if terminators.contains(trimmed[i]), count >= 25 {
                let next = trimmed.index(after: i)
                if next == trimmed.endIndex { break }
                if trimmed[next] == " " {
                    let first = String(trimmed[..<next]).trimmingCharacters(in: .whitespaces)
                    let rest = String(trimmed[next...]).trimmingCharacters(in: .whitespaces)
                    return rest.isEmpty ? (first, nil) : (first, rest)
                }
            }
            i = trimmed.index(after: i)
        }
        return (trimmed, nil)
    }

    public static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var rest: String? = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let chunk = rest, !chunk.isEmpty {
            let (first, tail) = splitFirstSentence(chunk)
            out.append(first)
            rest = tail
        }
        return out
    }
}
