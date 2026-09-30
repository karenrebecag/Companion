import Foundation

/// What a language recognizer concluded about a piece of text. `code` is a
/// bare ISO 639-1 code ("es", "en"), compared against `AppLanguage.rawValue`.
package struct DetectedLanguage: Sendable, Equatable {
    package var code: String
    package var confidence: Double

    package init(code: String, confidence: Double) {
        self.code = code
        self.confidence = confidence
    }
}

/// Port for the system recognizer (NaturalLanguage lives in Services, so
/// Core stays pure and tests use a fake). Nil means no verdict.
package protocol LanguageRecognizing: Sendable {
    func dominant(_ text: String) -> DetectedLanguage?
}

/// Wave 15f-2: the hold brain once leaked English reasoning into a Spanish
/// reply. Each sentence of a cut is checked before it reaches the mouth; one
/// the recognizer is confident is in another language is dropped.
///
/// Only while the conversation is otherwise in the app language: a sentence
/// is dropped only once the user's words or an earlier sentence of the reply
/// were confidently in it. Without that evidence the whole reply may simply
/// be in another language, and saying it beats a silent turn. The rule is
/// causal on purpose: holding sentences back to decide later would delay the
/// first audio this wave is trying to bring forward.
///
/// Code review 2026-09-25 (HIGH-A): a reply often QUOTES the other language
/// — an error line, a build result, a translation — and dropping those cut
/// the answer the user asked for. So a foreign sentence is dropped only when
/// it looks like a reasoning leak: never after a quoting lead-in, and only
/// when it opens like reasoning or is a long unannounced sentence in a reply
/// otherwise wholly in the app language.
package struct MouthLanguageGate: Sendable {
    /// Below this, a sentence is a name or a neutral fragment ("OK",
    /// "Abrí Safari") the recognizer cannot judge.
    package static let minWords = 4
    package static let minConfidence = 0.6
    /// Shorter unannounced foreign lines ("Build succeeded with zero
    /// warnings.") are more likely quoted output than a leak.
    package static let minLeakWords = 6

    /// How the hold brain's leaked reasoning starts (log 2026-09-25).
    static let reasoningOpeners = [
        "we need", "we should", "let me", "i need", "the user", "wait,", "actually,", "hmm",
    ]
    static let quoteMarks: Set<Character> = ["«", "»", "\"", "“", "”", "'"]

    private static let terminators: Set<Character> = [".", "!", "?", "…"]

    package let language: AppLanguage
    package private(set) var dropped: [String] = []
    private let recognizer: any LanguageRecognizing
    private var inAppLanguage = false
    /// Every judged sentence so far was in the app language.
    private var replyInAppLanguage = true
    /// The last sentence said, which may introduce a quote in the next one.
    private var previous = ""

    package init(
        language: AppLanguage, recognizer: any LanguageRecognizing, heard: String = ""
    ) {
        self.language = language
        self.recognizer = recognizer
        inAppLanguage = Self.verdict(heard, recognizer).map { $0.code == language.rawValue } ?? false
    }

    /// The cut without its foreign sentences; nil when nothing is left.
    package mutating func admit(_ cut: String) -> String? {
        let sentences = Self.sentences(cut)
        var kept: [String] = []
        for sentence in sentences {
            let verdict = Self.verdict(sentence, recognizer)
            let foreign = verdict.map { $0.code != language.rawValue } ?? false
            if foreign, inAppLanguage, Self.judgeable(sentence), isLeak(sentence) {
                dropped.append(sentence)
                continue
            }
            if verdict?.code == language.rawValue { inAppLanguage = true }
            if foreign { replyInAppLanguage = false }
            previous = sentence
            kept.append(sentence)
        }
        guard !kept.isEmpty else { return nil }
        // Untouched cuts keep their own line breaks and spacing.
        return kept.count == sentences.count ? cut : kept.joined(separator: " ")
    }

    /// The reply as it was actually said, for the thread and the transcript.
    package static func removing(_ sentences: [String], from text: String) -> String {
        var out = text
        for sentence in sentences {
            guard let range = out.range(of: sentence) else { continue }
            let before = out[..<range.lowerBound].reversed().drop(while: \.isWhitespace)
            let after = out[range.upperBound...].drop(while: \.isWhitespace)
            let head = String(before.reversed())
            let tail = String(after)
            out = head.isEmpty || tail.isEmpty ? head + tail : head + " " + tail
        }
        return out
    }

    private func isLeak(_ sentence: String) -> Bool {
        if Self.introducesQuote(previous, language) || Self.quotes(sentence) { return false }
        let lower = sentence.lowercased()
        if Self.reasoningOpeners.contains(where: lower.hasPrefix) { return true }
        return replyInAppLanguage
            && sentence.split(whereSeparator: \.isWhitespace).count >= Self.minLeakWords
    }

    /// The sentence carries its own lead-in ("Dice: …") or quote marks.
    private static func quotes(_ sentence: String) -> Bool {
        sentence.contains(":") || hasQuoteMark(sentence)
    }

    /// A `'` between two letters is an apostrophe ("don't"), not a quote:
    /// counting it would exempt most English reasoning from the drop.
    private static func hasQuoteMark(_ text: String) -> Bool {
        let chars = Array(text)
        return chars.indices.contains { i in
            guard quoteMarks.contains(chars[i]) else { return false }
            guard chars[i] == "'" else { return true }
            let letterBefore = i > 0 && chars[i - 1].isLetter
            let letterAfter = i + 1 < chars.count && chars[i + 1].isLetter
            return !(letterBefore && letterAfter)
        }
    }

    /// What was said just before announces a quote: it ends with a colon,
    /// holds quote marks, or names what is being read out.
    private static func introducesQuote(_ sentence: String, _ language: AppLanguage) -> Bool {
        guard !sentence.isEmpty else { return false }
        if sentence.hasSuffix(":") || hasQuoteMark(sentence) { return true }
        let lower = sentence.lowercased()
        let words = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
        switch language {
        case .es:
            return !words.isDisjoint(with: ["dice", "decía", "error", "título"])
                || lower.contains("en inglés")
        case .en:
            return !words.isDisjoint(with: ["says", "reads", "title"])
        }
    }

    private static func judgeable(_ sentence: String) -> Bool {
        sentence.split(whereSeparator: \.isWhitespace).count >= minWords
    }

    /// A confident verdict, or nil.
    private static func verdict(
        _ text: String, _ recognizer: any LanguageRecognizing
    ) -> DetectedLanguage? {
        guard !text.isEmpty, let verdict = recognizer.dominant(text),
              verdict.confidence >= minConfidence else { return nil }
        return verdict
    }

    /// Sentences at a terminator followed by whitespace, with no minimum
    /// length: a cut can carry a short leak glued to a Spanish sentence.
    static func sentences(_ cut: String) -> [String] {
        var out: [String] = []
        var current = ""
        var previousEnds = false
        for char in cut {
            if previousEnds, char.isWhitespace {
                append(current, to: &out)
                current = ""
                previousEnds = false
                continue
            }
            current.append(char)
            previousEnds = terminators.contains(char)
        }
        append(current, to: &out)
        return out
    }

    private static func append(_ sentence: String, to out: inout [String]) {
        let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { out.append(trimmed) }
    }
}
