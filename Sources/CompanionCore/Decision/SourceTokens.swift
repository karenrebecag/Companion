import Foundation

/// One word or punctuation mark of what the user said, with where it sits in
/// the original text. A value is picked as a first and a last token, and the
/// text between them is copied out of the utterance: the judge never writes
/// a value, so it cannot write one the user did not say.
package struct SourceToken: Sendable, Equatable {
    package var id: String
    package var text: String
    /// UTF-16 offsets into the utterance, end exclusive.
    package var start: Int
    package var end: Int
}

package enum SourceTokens {
    /// Words are runs of letters, digits and in-word marks (', -, ., @, /,
    /// :) so "o'clock", "foo.com" and "10:30" stay whole; any other
    /// non-space character is a token of its own.
    package static func tokens(_ utterance: String) -> [SourceToken] {
        var found: [SourceToken] = []
        var current = ""
        var start = 0
        var offset = 0
        func flush() {
            guard !current.isEmpty else { return }
            found.append(SourceToken(
                id: "t\(found.count)", text: current, start: start, end: offset))
            current = ""
        }
        for character in utterance {
            let width = character.utf16.count
            if character.isLetter || character.isNumber
                || (!current.isEmpty && "'’-.@/:".contains(character)) {
                if current.isEmpty { start = offset }
                current.append(character)
            } else {
                // A trailing in-word mark ("hola." / "done:") is punctuation.
                trimTrailingMarks(&current, &offset, into: &found, start: start)
                flush()
                if !character.isWhitespace {
                    found.append(SourceToken(
                        id: "t\(found.count)", text: String(character),
                        start: offset, end: offset + width))
                }
            }
            offset += width
        }
        trimTrailingMarks(&current, &offset, into: &found, start: start)
        flush()
        return found
    }

    /// The original text from `first` through `last`, or nil when they are
    /// out of order or not this utterance's tokens.
    package static func copy(
        _ utterance: String, from first: SourceToken, through last: SourceToken
    ) -> String? {
        let units = Array(utterance.utf16)
        guard first.start <= last.start, first.start >= 0, last.end <= units.count,
              first.start < last.end
        else { return nil }
        return String(utf16CodeUnits: Array(units[first.start..<last.end]), count: last.end - first.start)
    }

    private static func trimTrailingMarks(
        _ current: inout String, _ offset: inout Int, into found: inout [SourceToken], start: Int
    ) {
        var marks: [Character] = []
        while let last = current.last, "'’-.@/:".contains(last) {
            marks.insert(current.removeLast(), at: 0)
        }
        guard !marks.isEmpty else { return }
        let markWidth = marks.reduce(0) { $0 + $1.utf16.count }
        let wordEnd = offset - markWidth
        if !current.isEmpty {
            found.append(SourceToken(id: "t\(found.count)", text: current, start: start, end: wordEnd))
            current = ""
        }
        var at = wordEnd
        for mark in marks {
            let width = mark.utf16.count
            found.append(SourceToken(id: "t\(found.count)", text: String(mark), start: at, end: at + width))
            at += width
        }
    }
}
