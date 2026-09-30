import Foundation

// 16q-3a: what the judge is shown of an action's arguments. The rule that
// governs the whole file: a summary that hides part of the arguments must say
// so (`isComplete`), because a judge shown half of a destination can only
// guess, and a guess must never come out covered.

extension ActionSummary {
    static let maxKeys = 16
    static let maxText = 80
    static let maxKey = 40
    static let maxListItems = 5
    /// Arguments come from a model or a third-party MCP server, and parsing
    /// builds a full tree before anything is capped. Past this size the
    /// arguments are a body, not a target: the judge could not be shown them
    /// anyway, so they are never parsed (incomplete, and the version hashes
    /// the raw bytes).
    static let maxArgumentBytes = 64 * 1024

    /// Only the top level, only what names a target. Anything else becomes a
    /// length or a count, so a body never travels (D2).
    ///
    /// HACK: prose over the cap (text with whitespace) stays complete and
    /// travels as its length only, so a destination buried in a long message
    /// is not shown. Revisit with the shadow metric before 16q-4: if failed
    /// rate from incompleteness exceeds 10%, or a false cover hides behind a
    /// prose placeholder. Whatever the metric says, before 16q-4 enforce this
    /// becomes a keyed allowlist of body fields (body, text, message).
    package static func make(argumentsJSON: String) -> ActionSummary {
        guard argumentsJSON.utf8.count <= maxArgumentBytes,
              case .object(let object)? = JSONValue.parse(Data(argumentsJSON.utf8))
        else {
            return ActionSummary(values: [:], isComplete: false)
        }
        var values: [String: Value] = [:]
        var complete = object.count <= maxKeys
        for key in object.keys.sorted().prefix(maxKeys) {
            guard let raw = object[key] else { continue }
            let shown = TextSanitizer.display(key, maxLength: maxKey)
            // An empty key names nothing, and a second key that shows the same
            // would overwrite the first: either way the judge misses a value.
            guard !shown.isEmpty, values[shown] == nil else {
                complete = false
                continue
            }
            // A key the judge sees differently from the one the tool receives
            // (cleaned or cut) may be pointing its value at another field.
            // A credential never names a destination, so the judge loses
            // nothing by seeing only its length (Karen, 2026-09-30).
            let (value, whole) = isSecret(key) ? (.text(lengthMarker(raw)), true) : summarise(raw)
            complete = complete && whole && shown == key
            values[shown] = value
        }
        return ActionSummary(values: values, isComplete: complete)
    }

    /// Within both caps: 80 characters and, so combining marks cannot stack a
    /// kilobyte into one character, four unicode scalars per character.
    static func fits(_ text: String, limit: Int) -> Bool {
        text.count <= limit && text.unicodeScalars.count <= limit * TextSanitizer.scalarsPerCharacter
    }

    /// Sanitised text within the caps, or a placeholder that says how long it
    /// was. Never a silent cut: a cut destination reads as a different one.
    static func bounded(_ text: String, limit: Int, label: String) -> String {
        fits(text, limit: limit)
            ? TextSanitizer.display(text, maxLength: limit) : "<\(label): \(text.count) chars>"
    }

    /// The value the judge is shown, and whether that is all of it. `false`
    /// wherever the judge would be deciding on a destination it cannot see.
    private static func summarise(_ value: JSONValue) -> (value: Value, whole: Bool) {
        switch value {
        case .null: return (.text("<null>"), true)
        case .bool(let flag): return (.bool(flag), true)
        // A rounded id shown as a number would read as another id.
        case .number(let lexeme, let number): return (.number(number), JSONValue.roundTrips(lexeme, number))
        case .string(let text):
            // Prose is a body and travels as its length (D2); one long token
            // with no whitespace is a URL, address, path or id.
            guard fits(text, limit: maxText) else {
                return (.text(bounded(text, limit: maxText, label: "text")), text.contains(where: \.isWhitespace))
            }
            let shown = TextSanitizer.display(text, maxLength: maxText)
            return (.text(shown), isUnchanged(text, shown))
        case .object(let object): return (.text("<object: \(object.count) keys>"), false)
        case .array(let items): return summarise(list: items)
        }
    }

    private static func summarise(list items: [JSONValue]) -> (value: Value, whole: Bool) {
        var texts: [String] = []
        var unchanged = true
        for item in items {
            guard case .string(let text) = item, fits(text, limit: maxText) else {
                return (.text("<list: \(items.count) items>"), false)
            }
            let clean = TextSanitizer.display(text, maxLength: maxText)
            unchanged = unchanged && isUnchanged(text, clean)
            texts.append(clean)
        }
        let shown = Array(texts.prefix(maxListItems))
        let cut = texts.count - shown.count
        return (.list(cut > 0 ? shown + ["+\(cut) more"] : shown), cut == 0 && unchanged)
    }

    /// Matched as substrings of the folded key, because keys are written run
    /// together (`accesstoken`, `APIToken`), numbered (`password1`) or as
    /// synonyms. `key` alone is not here: it names ordinary fields.
    static let secretFragments = [
        "token", "secret", "passw", "passphrase", "pwd", "apikey", "privatekey", "accesskey",
        "credential", "bearer", "authoriz", "cookie", "session", "jwt",
    ]

    /// Counts and lists that contain a fragment without being a credential
    /// (`max_tokens`, `sessions`). Removed before matching, so a real
    /// credential key still matches on what is left.
    static let countWords = ["tokenizer", "tokens", "sessions"]

    /// NFKC folds fullwidth and other compatibility forms onto ASCII; keeping
    /// letters only drops separators, digits and case so every spelling of a
    /// key compares as one string.
    static func isSecret(_ key: String) -> Bool {
        var folded = String(key.precomposedStringWithCompatibilityMapping.lowercased().filter(\.isLetter))
        for word in countWords { folded = folded.replacingOccurrences(of: word, with: " ") }
        return secretFragments.contains { folded.contains($0) }
    }

    /// The same form prose uses, so a secret reads as any other hidden body.
    /// A nested value is measured by its canonical bytes, never opened.
    private static func lengthMarker(_ value: JSONValue) -> String {
        if case .string(let text) = value { return "<text: \(text.count) chars>" }
        return "<text: \(value.canonicalBytes().count) chars>"
    }

    /// Sanitising strips zero-width, bidi, control and tag characters, so the
    /// judge would approve `ana@x.com` while the tool receives another address.
    /// Compared by scalars: `==` on `String` is canonical equivalence and would
    /// call two different byte sequences the same text.
    private static func isUnchanged(_ raw: String, _ shown: String) -> Bool {
        raw.unicodeScalars.elementsEqual(shown.unicodeScalars)
    }
}
