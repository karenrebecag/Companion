import Foundation

/// Text that leaves for the agent or the model passes through here first: the bridge
/// result and the output of the tools that read the screen or content. The
/// turn can read a page or a file that holds a credential, and the agent is a
/// third party; a pattern that is not recognised still leaves, so this lowers
/// the odds, it does not make the output safe.
package enum TurnRedaction {
    package static let mask = "[redacted]"

    /// Tools whose output is screen or file content: it reaches the model, not
    /// only the bridge, so the reader is also told that values were hidden.
    package static let readingTools: Set<String> = [
        "look", "see", "read_focused", "browser_read", "read_file", "web_fetch",
        "list_directory", "sheet_read", "web_search", "read_url", "read_skill",
    ]

    /// Every tool output is masked (a click repeats a control's label; the
    /// history stores whatever a tool said). Only a reading tool gets the
    /// note, so the model does not type the mask as if it were the value.
    package static func redact(_ outcome: ParentToolOutcome, tool: String) -> ParentToolOutcome {
        var masked = outcome
        masked.output = redact(outcome.output)
        guard readingTools.contains(tool) else { return masked }
        let hidden = count(in: masked.output) - count(in: outcome.output)
        if hidden > 0 {
            masked.output += "\n(\(hidden) value(s) hidden for privacy as \(mask); never type \(mask) as if it were the value)"
        }
        return masked
    }

    private static func count(in text: String) -> Int {
        text.components(separatedBy: mask).count - 1
    }

    private static let patterns: [NSRegularExpression] = [
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?(-----END [A-Z ]*PRIVATE KEY-----|$)"#,
        // csk- is Cerebras; the lookbehind keeps a word that ends in "sk" out.
        #"(?<![A-Za-z0-9])(?:csk|sk)[-_][A-Za-z0-9_\-]{16,}"#,
        #"\b(?:rk|pk)_(?:live_|test_)?[A-Za-z0-9]{16,}"#,
        #"\bsb_secret_[A-Za-z0-9_\-]{16,}"#,
        #"\bAIza[0-9A-Za-z_\-]{35}"#,
        #"(?i)\bBearer\s+[A-Za-z0-9._~+/\-]{8,}=*"#,
        #"\b(AKIA|ASIA)[0-9A-Z]{16}\b"#,
        #"\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}"#,
        #"\bgithub_pat_[A-Za-z0-9_]{20,}"#,
        #"\bxox[bpas]-[A-Za-z0-9\-]{10,}"#,
        // A header always starts with {" (eyJ); a cut token still has two segments
        #"\beyJ[A-Za-z0-9_\-]{5,}\.[A-Za-z0-9_\-]{5,}(?:\.[A-Za-z0-9_\-]*)?"#,
    ].map(compile)

    /// The name stays so the agent knows what was hidden; the value goes.
    ///
    /// Two tiers. A strong label names a secret by its meaning (password,
    /// clave, secret, pin), so its value is masked whatever it looks like.
    /// A weak label (key, token, passkey) also names things that are plain
    /// prose ("Passkeys: iCloud"), so only a value that looks like a secret
    /// is masked. QA 606 caught the weak tier over-matching; the strong tier
    /// keeps the old coverage.
    private static let keepingPrefix: [NSRegularExpression] = [
        // Whole line, env style (`DB_PASSWORD=...`). A passphrase runs to a
        // comma or semicolon, so the rest of a sentence after it survives.
        #"(?im)^([ \t]*(?:export[ \t]+)?[A-Za-z0-9_.\-]*(?:PASSWORD|PASSWD|CONTRASEÑA)[ \t]*[=:][ \t]*)[^,;\n]+"#,
        #"(?im)^([ \t]*(?:export[ \t]+)?[A-Za-z0-9_.\-]*(?:SECRET|CLAVE|PIN)[ \t]*(?:=|:(?![ \t"']*(?:iCloud|Keychain|Android|Autofill)(?![A-Za-z0-9_\-~])(?:[ \t]*(?:\n|$)|[ \t]+(?-i:[a-záéíóúñ]+)(?![A-Za-z0-9]))))[ \t"']*)[^,;\n]+"#,
        #"(?im)^([ \t]*(?:export[ \t]+)?[A-Za-z0-9_.\-]*(?:TOKEN|KEY|PASSKEYS?)[A-Za-z0-9_.\-]*[ \t]*(?:=[ \t]*|:[ \t]*(?=\S*?(?:\d|\S{12})))).+$"#,
        // Strong label, inline ("la clave=hunter22", "client secret: ...").
        // A passphrase (password, contraseña) masks to a comma or semicolon.
        #"(?i)(\b[A-Za-z0-9_]*(?:password|passwd|contraseña)[ \t]*[:=][ \t]*["']?)[^,;\n]+"#,
        // The exemptions are common Spanish prose after a label, not secrets.
        #"(?i)(\b(?:[A-Za-z0-9_]*(?:clave|secret)|(?:[A-Za-z0-9]+_)?pin)[ \t]*(?:=|:(?![ \t"']*(?:iCloud|Keychain|Android|Autofill)(?![A-Za-z0-9_\-~])(?:[ \t]*(?:\n|$)|[ \t]+(?-i:[a-záéíóúñ]+)(?![A-Za-z0-9]))))[ \t"']*)[^,;\n]+"#,
        // Weak label: a digit or 12+ characters, or it is prose.
        #"(?i)\b([A-Za-z0-9_]*(?:api[ _-]?key|passkeys?|token|key)\w*(?:[ \t]*=[ \t]*["']?|[ \t]*:[ \t]*["']?(?=[^\s"'<>,;]*\d|[^\s"'<>,;]{12})))[^\s"'<>,;]{6,}"#,
        // A bare hex string is only a secret when a word says so
        #"(?i)\b((?:secret|client|token|key)(?:[ \t_\-]+[A-Za-z]{1,12}\b){0,2}[ \t]*[:=]?[ \t]*["']?)[0-9a-f]{32,}\b"#,
        // A two-factor code: 4 to 8 digits near its word. "código postal" is an address.
        #"(?i)((?<!\b(?:status|error|exit|http|source|postal)[ \t]{1,3})\b(?:c[oó]digo|code|verificaci[oó]n|verification)(?:[ \t]*[:=][ \t]*|[ \t]+(?:de[ \t]+\w+[ \t]+)?(?:es|is)[ \t]+)|\botp[ \t]*[:=]?[ \t]*)(?<!\d)\d{4,8}(?!\d)"#,
    ].map(compile)

    /// True when text names a strong label followed by its separator. The
    /// memory gate asks this so a fact such as "mi contraseña: ..." is refused
    /// even when the redaction above would change nothing.
    package static func holdsStrongLabel(_ text: String) -> Bool {
        strongLabel.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static let strongLabel = compile(
        #"(?i)(?<![A-Za-z0-9])[A-Za-z0-9_]*(?:password|passwd|contraseña|clave|secret|pin)[ \t]*[:=]"#)

    /// Shapes that look like anything unless a format agrees, so a random
    /// string is left alone.
    private static let validated: [(NSRegularExpression, @Sendable (String) -> Bool)] = [
        (compile(#"\b[A-Z]{4}\d{6}[HM][A-Z]{2}[B-DF-HJ-NP-TV-Z]{3}[A-Z0-9]\d\b"#), IdentifierChecks.isCURP),
        (compile(#"\b[A-ZÑ&]{3,4}\d{6}[A-Z0-9]{3}\b"#), IdentifierChecks.isRFC),
        (compile(#"[A-Za-z0-9+/]{64,}={0,2}"#), IdentifierChecks.isBase64Blob),
    ]

    /// Digits with spaces, dashes or dots between them.
    private static let digitRun = compile(#"(?<!\d)\d(?:[ .\-]?\d)*"#)

    private static func compile(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("redaction pattern does not compile: \(pattern)")
        }
    }

    package static func redact(_ text: String) -> String {
        var result = ""
        var cursor = text.startIndex
        for span in protectedRanges(in: text) {
            result += text[cursor..<span.lowerBound] + mask
            cursor = span.upperBound
        }
        return result + text[cursor...]
    }

    /// Where the secrets sit in `text`, merged and in order. Every rule reads
    /// the original text, not a half-masked copy, so a caller can keep each
    /// value on the Mac and send only a reference to it (computah keeps source
    /// ranges the same way, `CommandLanguage.swift:45`).
    package static func protectedRanges(in text: String) -> [Range<String.Index>] {
        let whole = NSRange(text.startIndex..., in: text)
        var spans: [Range<String.Index>] = []
        for regex in patterns {
            spans += regex.matches(in: text, range: whole).compactMap { Range($0.range, in: text) }
        }
        for regex in keepingPrefix {
            spans += regex.matches(in: text, range: whole).compactMap { match in
                let start = NSMaxRange(match.range(at: 1))
                return Range(NSRange(location: start, length: NSMaxRange(match.range) - start), in: text)
            }
        }
        spans += digitRunSpans(text)
        for (regex, isSensitive) in validated {
            spans += regex.matches(in: text, range: whole).compactMap { Range($0.range, in: text) }
                .filter { isSensitive(String(text[$0])) }
        }
        return merged(spans.filter { !$0.isEmpty })
    }

    /// Touching spans become one, so a value split across two rules is one mask.
    private static func merged(_ spans: [Range<String.Index>]) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        for span in spans.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            if let last = result.last, span.lowerBound <= last.upperBound {
                result[result.count - 1] = last.lowerBound..<max(last.upperBound, span.upperBound)
            } else {
                result.append(span)
            }
        }
        return result
    }

    private static func digitRunSpans(_ text: String) -> [Range<String.Index>] {
        digitRun.matches(in: text, range: NSRange(text.startIndex..., in: text)).flatMap { match in
            guard let run = Range(match.range, in: text) else { return [Range<String.Index>]() }
            return outsideLongFractions(text[run]).flatMap(pieceSpans)
        }
    }

    /// A float's fraction ("0.9999963045120239") shares the digit-run shape, but no
    /// card or CLABE prints a group longer than 6 digits after a dot. Only that
    /// fraction is set aside: skipping the whole run would let a card next to a
    /// price or an IP through.
    private static func outsideLongFractions(_ run: Substring) -> [Substring] {
        var pieces: [Substring] = []
        var start = run.startIndex
        var cursor = run.startIndex
        while let dot = run[cursor...].firstIndex(of: ".") {
            let fractionStart = run.index(after: dot)
            let fractionEnd = run[fractionStart...].firstIndex(where: { !$0.isNumber }) ?? run.endIndex
            cursor = fractionEnd
            guard run.distance(from: fractionStart, to: fractionEnd) > 6 else { continue }
            pieces.append(run[start..<dot])
            start = fractionEnd
        }
        pieces.append(run[start...])
        return pieces
    }

    /// The whole piece first (a CLABE, or a card with a CVV glued to it), then
    /// every span of whole digit groups, so a card next to a short number or a
    /// second card in the same run still masks.
    private static func pieceSpans(_ piece: Substring) -> [Range<String.Index>] {
        guard piece.filter(\.isNumber).count >= 13 else { return [] }
        let copy = String(piece)
        if copy.filter(\.isNumber).count == 18, IdentifierChecks.isCLABE(copy) {
            return [piece.startIndex..<piece.endIndex]
        }
        if let window = IdentifierChecks.cardWindow(in: copy) {
            let lower = piece.index(piece.startIndex, offsetBy: copy.distance(from: copy.startIndex, to: window.lowerBound))
            let upper = piece.index(lower, offsetBy: copy.distance(from: window.lowerBound, to: window.upperBound))
            return [lower..<upper]
        }
        return groupSpans(piece)
    }

    private static func groupSpans(_ piece: Substring) -> [Range<String.Index>] {
        let groups = groupRanges(piece)
        var hits: [Range<String.Index>] = []
        var first = 0
        while first < groups.count {
            guard let last = sensitiveSpanEnd(piece, groups: groups, from: first) else {
                first += 1
                continue
            }
            hits.append(groups[first].lowerBound..<groups[last].upperBound)
            first = last + 1
        }
        return hits
    }

    private static func sensitiveSpanEnd(_ piece: Substring, groups: [Range<String.Index>], from first: Int) -> Int? {
        var digits = 0
        for last in first..<groups.count {
            digits += piece.distance(from: groups[last].lowerBound, to: groups[last].upperBound)
            if digits > 19 { return nil }
            let span = String(piece[groups[first].lowerBound..<groups[last].upperBound])
            if digits == 18, IdentifierChecks.isCLABE(span) { return last }
            if digits >= 13, IdentifierChecks.isCardNumber(span) { return last }
        }
        return nil
    }

    private static func groupRanges(_ piece: Substring) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var cursor = piece.startIndex
        while let start = piece[cursor...].firstIndex(where: \.isNumber) {
            let end = piece[start...].firstIndex(where: { !$0.isNumber }) ?? piece.endIndex
            ranges.append(start..<end)
            cursor = end
        }
        return ranges
    }
}
