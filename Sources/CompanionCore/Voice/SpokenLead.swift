import Foundation

/// A voice reply that carries a table or a list is one spoken sentence and a
/// document under it (Incredible's pattern): the voice says the lead and
/// stops where the structure starts, the island shows the rest. Fed the
/// streamed deltas in order; a mark is only known by what follows it ("- "
/// is a bullet, "-5 °C" is not; "3. " is a list, "3.14" a number), so a
/// candidate is held until the next character decides it.
package struct SpokenLead: Sendable, Equatable {
    /// The structure started: nothing after it is voiced this reply.
    package private(set) var documentOpen = false
    private var held = ""
    private var atLineStart = true
    /// Backticks and the tag after them, until a blank says what they open.
    private var fence = ""

    package init() {}

    /// What of `piece` the voice may say.
    package mutating func admit(_ piece: String) -> String {
        guard !documentOpen else { return "" }
        var out = ""
        for char in piece {
            if feedFence(char, into: &out) { continue }
            if documentOpen { return out }
            if atLineStart {
                lineStart(char, into: &out)
                if documentOpen { return out }
            } else {
                out.append(char)
                if char.isNewline { atLineStart = true }
            }
        }
        return out
    }

    /// The whole reply is in: a candidate still held was text after all.
    package mutating func finish() -> String {
        defer {
            held = ""
            fence = ""
        }
        return documentOpen ? "" : held + fence
    }

    private mutating func lineStart(_ char: Character, into out: inout String) {
        let mark = held.trimmingCharacters(in: .whitespacesAndNewlines)
        if char.isWhitespace, !mark.isEmpty, Self.isMark(mark) {
            documentOpen = true
            return
        }
        if char == "|", mark.isEmpty {
            documentOpen = true
            return
        }
        if char.isWhitespace || char.isNumber || "-*+•>#.)".contains(char) {
            held.append(char)
            return
        }
        out += held
        out.append(char)
        held = ""
        atLineStart = false
    }

    /// True while the character belongs to a fence still being read. A
    /// ```markdown or ```md fence is the document; any other fence, or one or
    /// two backticks, goes back to the text, where code is the filter's.
    private mutating func feedFence(_ char: Character, into out: inout String) -> Bool {
        if char == "`" {
            fence.append(char)
            return true
        }
        guard !fence.isEmpty else { return false }
        if fence.hasPrefix("```"), char.isLetter {
            fence.append(char)
            return true
        }
        let tag = fence.drop { $0 == "`" }.lowercased()
        // A companion: card paints on its own and is never read either.
        if fence.hasPrefix("```"), ["markdown", "md", "companion"].contains(tag) {
            documentOpen = true
            fence = ""
            return true
        }
        let text = fence
        fence = ""
        if atLineStart {
            out += held + text
            held = ""
            atLineStart = false
        } else {
            out += text
        }
        return false
    }

    private static func isMark(_ mark: String) -> Bool {
        if ["-", "*", "+", "•", ">"].contains(mark) { return true }
        if mark.allSatisfy({ $0 == "#" }), mark.count <= 6 { return true }
        return mark.range(of: #"^\d{1,3}[.)]$"#, options: .regularExpression) != nil
    }
}
