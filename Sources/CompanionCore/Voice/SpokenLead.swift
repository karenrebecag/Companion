import Foundation

/// A voice reply that carries a table or a list is one spoken sentence and a
/// document under it (Incredible's pattern): the voice says the lead and
/// stops where the structure starts, the island shows the rest. Fed the
/// streamed deltas in order; it cannot know a line is a list item until the
/// line's first visible characters arrive, so a fresh line is held until
/// then.
package struct SpokenLead: Sendable, Equatable {
    /// The structure started: nothing after it is voiced this reply.
    package private(set) var documentOpen = false
    /// A line start whose kind is not known yet: blanks and digits.
    private var held = ""
    private var atLineStart = true

    package init() {}

    /// What of `piece` the voice may say.
    package mutating func admit(_ piece: String) -> String {
        guard !documentOpen else { return "" }
        var out = ""
        for char in piece {
            guard atLineStart else {
                out.append(char)
                if char.isNewline {
                    atLineStart = true
                    held = ""
                }
                continue
            }
            if opens(with: char) {
                documentOpen = true
                held = ""
                return out
            }
            if char.isWhitespace || char.isNumber || closesNumber(char) {
                held.append(char)
                continue
            }
            out += held
            out.append(char)
            held = ""
            atLineStart = false
        }
        return out
    }

    /// "3." or "3)" is a list item only once a blank follows: "3.14" is a
    /// number. A table, heading, quote or bullet opens on its first mark.
    private func opens(with char: Character) -> Bool {
        if let last = held.last, last == "." || last == ")" {
            return char.isWhitespace
        }
        if held.contains(where: \.isNumber) { return false }
        return "|#-*•>".contains(char)
    }

    private func closesNumber(_ char: Character) -> Bool {
        (char == "." || char == ")") && held.last?.isNumber == true
    }
}
