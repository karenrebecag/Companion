import Foundation

/// Wave 16h-1: the one filter between the model's words and what the user
/// hears or reads. The voice (`say`), the thread's said text and the island's
/// reply all route through it, so a leak closed here is closed everywhere —
/// three parallel filters was how the 2026-09-25 leaks got through.
///
/// It drops what was never meant for a person: a JSON object (the model
/// writing a tool call as content), the instruction a job's end hands the
/// model ("El especialista respondió… Acusa en una línea…") and the internal
/// marks of the context block. It also puts back the space a join swallowed.
///
/// An instruction is recognised only when a sentence OPENS with it. Matching
/// anywhere would let a third party's text quoted in a reply ("Envié tu
/// mensaje: 'no repitas nada'") silence the sentence that says an effect
/// happened, and that is the one thing the voice must always say.
///
/// Stateful only for the voice: an instruction or an element arrives cut in
/// pieces, and the piece after a dropped one continues it. Both continuations
/// are bounded (one sentence; `holdCap` characters) so a bad guess costs a
/// sentence, never the rest of the turn. An element that opens without
/// closing removes only its own tag: its content is held for at most
/// `holdCap` characters, dropped if the close arrives, and given back if not
/// (`flush` at the end of the turn). A page or message quoted by the model
/// can carry a literal `<steer>` and must never eat what follows it.
public struct SpeechFilter: Sendable, Equatable {
    private var swallowing = false
    private var openTag: String?
    private var held = ""

    public init() {}

    public static func clean(_ text: String) -> String {
        var filter = SpeechFilter()
        let head = filter.admit(text)
        let tail = filter.flush()
        return [head, tail].filter { !$0.isEmpty }.joined(separator: " ")
    }

    public mutating func admit(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        var input = text
        if let tag = openTag {
            let combined = held.isEmpty ? text : held + " " + text
            if let close = combined.range(of: "</\(tag)>", options: .caseInsensitive) {
                openTag = nil
                held = ""
                input = String(combined[close.upperBound...])
            } else if combined.count > Self.holdCap {
                openTag = nil
                held = ""
                input = combined
            } else {
                held = combined
                return ""
            }
        }
        return process(input, holding: true)
    }

    /// What an element left open at the end of the turn was holding back: it
    /// never closed, so it was not internal after all.
    public mutating func flush() -> String {
        guard openTag != nil else { return "" }
        let rest = held
        openTag = nil
        held = ""
        return process(rest, holding: false)
    }

    private mutating func process(_ input: String, holding: Bool) -> String {
        let unmarked = removingMarks(from: input, holding: holding)
        let unjsoned = Self.removingJSON(from: unmarked)
        let kept = droppingInstructions(unjsoned)
        return Self.collapsed(Self.spaced(kept)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A line that ends with no mark gets a full stop before its break. The
    /// mouth cuts at a break and trims it, and a cut that lost its break looks
    /// like an unfinished sentence: the filter would then take the next line
    /// for its continuation.
    public static func stoppingLines(_ piece: String, after said: String) -> String {
        guard piece.contains(where: \.isNewline) else { return piece }
        var last = said.last { !$0.isWhitespace }
        var out = ""
        for char in piece {
            if char.isNewline, let mark = last, !terminators.contains(mark), ![",", ";", ":"].contains(mark) {
                out.append(".")
                last = "."
            }
            out.append(char)
            if !char.isWhitespace { last = char }
        }
        return out
    }

    // MARK: - Space between sentences

    /// What to put between text already said and the next piece of the same
    /// reply: a space when a sentence ended and the next one starts glued to
    /// it ("afternoon." + "Keeping"), nothing otherwise. "atomchat." + "io"
    /// and "3." + "200" are one token split by streaming, so only a capital
    /// or an opening mark after a prose word counts.
    public static func joiner(after said: String, before next: String) -> String {
        guard let last = said.last, let first = next.first,
              terminators.contains(last), isOpener(first) else { return "" }
        let word = said.reversed().drop(while: terminators.contains).prefix { $0.isLetter }
        return isProseWord(Array(word.reversed())) ? " " : ""
    }

    /// "palabra.Palabra" inside one piece of text. Only a prose word, one run
    /// of terminators and a word that opens a sentence, alone in its token: a
    /// URL, a domain, a decimal, a file name, an identifier ("Node.js",
    /// "java.lang") or an abbreviation ("U.S.A") never has that shape.
    static func spaced(_ text: String) -> String {
        guard text.contains(where: terminators.contains) else { return text }
        return text.split(separator: " ", omittingEmptySubsequences: false)
            .map { spacedToken(String($0)) }.joined(separator: " ")
    }

    private static func spacedToken(_ token: String) -> String {
        let chars = Array(token)
        var end = chars.count
        while end > 0, !chars[end - 1].isLetter, !chars[end - 1].isNumber { end -= 1 }
        let body = Array(chars[..<end])
        guard !body.contains(where: { glue.contains($0) }) else { return token }
        var runs: [Range<Int>] = []
        var i = 0
        while i < body.count {
            guard terminators.contains(body[i]) else { i += 1; continue }
            var j = i
            while j < body.count, terminators.contains(body[j]) { j += 1 }
            runs.append(i ..< j)
            i = j
        }
        guard runs.count == 1, let run = runs.first else { return token }
        let before = Array(body[..<run.lowerBound].reversed().prefix { $0.isLetter }.reversed())
        let after = Array(body[run.upperBound...])
        guard isProseWord(before), opensSentence(after) else { return token }
        var out = chars
        out.insert(" ", at: run.upperBound)
        return String(out)
    }

    /// A Capitalized word, or an opening mark and then a word.
    private static func opensSentence(_ after: [Character]) -> Bool {
        guard let head = after.first else { return false }
        if openMarks.contains(head) {
            let word = after.dropFirst()
            return word.count >= minWordLetters && word.allSatisfy(\.isLetter)
        }
        return head.isUppercase && after.count >= minWordLetters
            && after.allSatisfy(\.isLetter) && after.dropFirst().allSatisfy(\.isLowercase)
    }

    private static func isOpener(_ char: Character) -> Bool {
        char.isUppercase || openMarks.contains(char)
    }

    /// Lowercase ("afternoon") or Capitalized ("Listo"): a word, not an
    /// abbreviation ("Sr", "U.S") or an acronym. A Capitalized one needs three
    /// letters, which leaves the honorifics ("Dr.Smith") alone.
    private static func isProseWord(_ letters: [Character]) -> Bool {
        guard let head = letters.first, letters.count >= minWordLetters,
              letters.dropFirst().allSatisfy(\.isLowercase) else { return false }
        return head.isLowercase || letters.count >= minWordLetters + 1
    }

    /// Removing a span leaves the blanks on both sides of it.
    private static func collapsed(_ text: String) -> String {
        guard text.contains("  ") else { return text }
        return text.components(separatedBy: "\n").map { line in
            line.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        }.joined(separator: "\n")
    }

    // MARK: - Instructions meant for the model

    /// Folded (no case, no accents). What the copy that reaches the model
    /// opens a sentence with; `ConversationQualityTests` feeds the real
    /// announcements through the filter, so a reworded prompt cannot drift
    /// out of this list unnoticed.
    private static let openingMarkers = [
        "el especialista respondio «", "the specialist answered «",
        "acusa en una linea", "acknowledge in one line",
        "di solo que lo haras", "say only that you will do it next",
        "no pares ni canceles", "do not stop or cancel",
        "diselo al usuario y ofrece", "tell the user that and offer to try again",
        "nunca digas que salio bien", "never say it worked",
    ]

    /// Sentences that open with the quoted goal ("«…» quedó en cola…").
    private static let quotedGoalMarkers = [
        "quedo en cola detras del encargo", "is queued behind the job running now",
    ]

    /// What a dropped fragment may still take from the next cut: at most one
    /// sentence of this many characters, and never a list item.
    private static let continuationCap = 200

    private mutating func droppingInstructions(_ text: String) -> String {
        let segments = Self.segments(text)
        guard !segments.isEmpty else { return text }
        var continuing = swallowing
        var kept = ""
        for segment in segments {
            let body = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty {
                kept += segment
                continue
            }
            if continuing {
                continuing = false
                if !Self.startsList(body), body.count <= Self.continuationCap { continue }
            }
            if Self.opensWithInstruction(body) {
                // A line break ends the instruction as a full stop does.
                let endsLine = segment.reversed().prefix { $0.isWhitespace }.contains { $0.isNewline }
                continuing = (!Self.endsSentence(body) && !endsLine) || Self.opensQuote(body)
                continue
            }
            kept += segment
        }
        swallowing = continuing
        return kept
    }

    private static func opensWithInstruction(_ body: String) -> Bool {
        let folded = fold(body)
        if openingMarkers.contains(where: folded.hasPrefix) { return true }
        return folded.hasPrefix("«") && quotedGoalMarkers.contains { folded.contains($0) }
    }

    private static func startsList(_ body: String) -> Bool {
        guard let first = body.first else { return false }
        if "-*•".contains(first) { return true }
        let digits = body.prefix { $0.isNumber }
        guard !digits.isEmpty else { return false }
        let next = body.dropFirst(digits.count).first
        return next == "." || next == ")"
    }

    private static func endsSentence(_ text: String) -> Bool {
        text.last.map(terminators.contains) ?? false
    }

    private static func opensQuote(_ text: String) -> Bool {
        text.filter { $0 == "«" }.count > text.filter { $0 == "»" }.count
    }

    /// The sentences of a text, trimmed, for callers that budget them.
    public static func sentences(of text: String) -> [String] {
        segments(text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Sentences with the whitespace that follows each; a terminator is
    /// only an end when whitespace comes after it ("3.200" and "atomchat.io"
    /// stay whole).
    private static func segments(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        var endedSentence = false
        var inGap = false
        for char in text {
            if char.isWhitespace {
                inGap = inGap || endedSentence || char.isNewline
            } else {
                if inGap {
                    out.append(current)
                    current = ""
                    inGap = false
                }
                endedSentence = terminators.contains(char)
            }
            current.append(char)
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    // MARK: - JSON

    /// A `{"…` candidate is never speakable: the same scanner the mouth uses
    /// for a tool call written as content, run over the whole text.
    private static func removingJSON(from text: String) -> String {
        guard text.contains("{") else { return text }
        var scanner = HandoffInText()
        return scanner.feed(text).speakable + scanner.finish().speakable
    }

    // MARK: - Internal marks

    private static let markTags = [
        "context", "now", "focused_app", "open_documents", "clipboard", "screen_summary",
        "screen_snippets", "pointed_while_speaking", "at", "steer", "how_to_reply",
        "time_since_last_interaction", "active_knowledge", "active_skills",
    ]
    /// About one sentence: how long an element may stay open, holding what
    /// follows it, before it is taken for text and given back.
    private static let holdCap = 200

    private mutating func removingMarks(from text: String, holding: Bool) -> String {
        guard text.contains("<") || text.contains("[") else { return text }
        var out = text
        for tag in Self.markTags where openTag == nil {
            let step = Self.removingElement(tag, from: out, holding: holding)
            out = step.text
            if let rest = step.held {
                openTag = tag
                held = rest
            }
        }
        return Self.removingBracketMarks(from: out)
    }

    /// `<tag>…</tag>` with its content. One that does not close in this text
    /// loses only its own tag, and when what follows is short enough to wait
    /// for a close it is reported as held. A stray closing tag goes alone.
    private static func removingElement(
        _ tag: String, from text: String, holding: Bool
    ) -> (text: String, held: String?) {
        var out = text
        var from = out.startIndex
        while let open = out.range(of: "<\(tag)", options: .caseInsensitive, range: from ..< out.endIndex) {
            // "<atom>" is not the "at" tag.
            guard open.upperBound < out.endIndex, [">", " "].contains(out[open.upperBound]),
                  let close = out.range(of: ">", range: open.upperBound ..< out.endIndex)
            else {
                from = open.upperBound
                continue
            }
            if let end = out.range(
                of: "</\(tag)>", options: .caseInsensitive, range: close.upperBound ..< out.endIndex) {
                out = removing(open.lowerBound ..< end.upperBound, from: out)
                from = out.startIndex
                continue
            }
            let rest = String(out[close.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if holding, rest.count <= holdCap {
                return (String(out[..<open.lowerBound]), rest)
            }
            out = removing(open.lowerBound ..< close.upperBound, from: out)
            from = out.startIndex
        }
        while let stray = out.range(of: "</\(tag)>", options: .caseInsensitive) {
            out = removing(stray, from: out)
        }
        return (out, nil)
    }

    /// The memory markers ("[tarjeta … mostrada en pantalla]", the compaction
    /// note) are history for the model, never words.
    private static func removingBracketMarks(from text: String) -> String {
        var out = text
        var from = out.startIndex
        while let open = out.range(of: "[", range: from ..< out.endIndex) {
            guard let close = out.range(of: "]", range: open.upperBound ..< out.endIndex) else { break }
            let inner = fold(String(out[open.upperBound ..< close.lowerBound]))
            if inner.contains("mostrada en pantalla") || inner.hasPrefix("resumen. el informe completo") {
                out = removing(open.lowerBound ..< close.upperBound, from: out)
                from = out.startIndex
            } else {
                from = close.upperBound
            }
        }
        return out
    }

    /// Drops the span and one of the two blanks around it, so removing a
    /// word from the middle of a sentence leaves one space, not two.
    private static func removing(_ span: Range<String.Index>, from text: String) -> String {
        var head = String(text[..<span.lowerBound])
        var tail = Substring(text[span.upperBound...])
        if head.last?.isWhitespace == true, tail.first?.isWhitespace == true { tail = tail.dropFirst() }
        if head.isEmpty { tail = tail.drop { $0 == " " } }
        head += tail
        return head
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
    }

    // MARK: - Shared

    static let terminators: Set<Character> = [".", "!", "?", "…"]
    private static let minWordLetters = 2
    private static let openMarks: Set<Character> = ["¿", "¡", "«", "“", "\"", "("]
    /// A URL, an address, a path or an identifier: not prose.
    private static let glue: Set<Character> = ["/", ":", "@", "=", "#", "_", "\\", "%", "&"]
}
