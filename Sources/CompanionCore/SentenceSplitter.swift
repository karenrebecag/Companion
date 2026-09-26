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

extension SentenceSplitter {
    /// Wave 15d-5: marks that end the first utterance early. A clause is
    /// enough for the first audio; waiting for a full sentence was the
    /// 0.7-3.5 s gap between first token and first sound.
    private static let firstCutMarks: Set<Character> = [",", ";", ":", ".", "!", "?", "…"]

    /// The first utterance of a reply: at the first clause mark followed by
    /// whitespace, or on the last whole word within `maxChars`. A mark at the
    /// end of the buffer waits, like `takeSentence`: "3," may still be "3,5".
    public static func takeFirstCut(
        _ buffer: String, maxChars: Int = 40
    ) -> (sentence: String, rest: String)? {
        var count = 0
        var sawWord = false
        var wordEnd: String.Index?
        var i = buffer.startIndex
        while i < buffer.endIndex {
            count += 1
            let c = buffer[i]
            if c.isNewline, sawWord { return cut(buffer, at: i) }
            if firstCutMarks.contains(c), sawWord {
                let next = buffer.index(after: i)
                if next < buffer.endIndex, buffer[next].isWhitespace {
                    return cut(buffer, at: next)
                }
            }
            if c.isWhitespace, sawWord, count - 1 <= maxChars || wordEnd == nil {
                wordEnd = i
            }
            if !c.isWhitespace { sawWord = true }
            if count > maxChars, let end = wordEnd {
                return cut(buffer, at: end)
            }
            i = buffer.index(after: i)
        }
        return nil
    }

    private static func cut(
        _ buffer: String, at index: String.Index
    ) -> (sentence: String, rest: String) {
        let sentence = String(buffer[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = String(buffer[index...].drop(while: \.isWhitespace))
        return (sentence, rest)
    }
}

/// Wave 15d-5: what the hold's mouth has heard from the model but not yet
/// spoken. The first utterance of a turn cuts early (`takeFirstCut`, or a
/// stall through `takeStalled`); every later one keeps `takeSentence`.
public struct MouthBuffer: Sendable, Equatable {
    public private(set) var pending = ""
    public private(set) var firstCutDone = false

    public init() {}

    /// True while a stall timer still has a job: nothing spoken yet, and at
    /// least one word waiting.
    public var awaitsFirstCut: Bool {
        !firstCutDone && pending.contains { !$0.isWhitespace }
    }

    public mutating func append(_ piece: String) -> [String] {
        pending += piece
        var out: [String] = []
        if !firstCutDone {
            guard let first = SentenceSplitter.takeFirstCut(pending) else { return out }
            out.append(first.sentence)
            pending = first.rest
            firstCutDone = true
        }
        while let next = SentenceSplitter.takeSentence(pending) {
            out.append(next.sentence)
            pending = next.rest
        }
        return out
    }

    /// The stream went quiet before any cut: say what is there, up to the
    /// last whitespace. A stall can land mid-token ("Claro que s"), and a
    /// word spoken in halves sounds broken; the tail waits for the next cut.
    /// No whitespace at all means one word, said whole.
    public mutating func takeStalled() -> String? {
        guard !firstCutDone else { return nil }
        let body = pending.drop(while: \.isWhitespace)
        guard !body.isEmpty else { return nil }
        let split = body.last?.isWhitespace == true
            ? body.endIndex : body.lastIndex(where: \.isWhitespace)
        let spoken = split.map { String(body[..<$0]) } ?? String(body)
        pending = split.map { String(body[$0...].drop(while: \.isWhitespace)) } ?? ""
        firstCutDone = true
        return spoken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Everything left, said whole (before acting, and at the end of a turn).
    public mutating func drain() -> String? {
        let text = pending.trimmingCharacters(in: .whitespacesAndNewlines)
        pending = ""
        guard !text.isEmpty else { return nil }
        firstCutDone = true
        return text
    }
}
