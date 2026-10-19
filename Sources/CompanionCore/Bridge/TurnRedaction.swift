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
        #"(?im)^([ \t]*(?:export[ \t]+)?[A-Za-z0-9_.\-]*(?:SECRET|CLAVE|PIN)[ \t]*(?:=|:(?![ \t"']*(?:iCloud|Keychain|Android|Autofill)\b))[ \t"']*)[^\s"'<>,;]{4,}"#,
        #"(?im)^([ \t]*(?:export[ \t]+)?[A-Za-z0-9_.\-]*(?:TOKEN|KEY|PASSKEYS?)[A-Za-z0-9_.\-]*[ \t]*(?:=|:)[ \t]*(?=\S*?(?:\d|\S{12}))).+$"#,
        // Strong label, inline ("la clave=hunter22", "client secret: ...").
        // A passphrase (password, contraseña) masks to a comma or semicolon.
        #"(?i)(\b(?:[A-Za-z0-9]+_)?(?:password|passwd|contraseña)[ \t]*[:=][ \t]*["']?)[^,;\n]+"#,
        // The exemptions are common Spanish prose after a label, not secrets.
        #"(?i)(\b(?:[A-Za-z0-9]+_)?(?:clave|secret|pin)[ \t]*(?:=|:(?![ \t"']*(?:iCloud|Keychain|Android|Autofill)\b))[ \t"']*)[^\s"'<>,;]{4,}"#,
        // Weak label: a digit or 12+ characters, or it is prose.
        #"(?i)\b([A-Za-z0-9_]*(?:api[ _-]?key|passkeys?|token|key)\w*[ \t]*[:=][ \t]*["']?)(?=[^\s"'<>,;]*\d|[^\s"'<>,;]{12})[^\s"'<>,;]{6,}"#,
        // A bare hex string is only a secret when a word says so
        #"(?i)\b((?:secret|client|token|key)(?:[ \t_\-]+[A-Za-z]{1,12}\b){0,2}[ \t]*[:=]?[ \t]*["']?)[0-9a-f]{32,}\b"#,
        // A two-factor code: 4 to 8 digits near its word. "código postal" is an address.
        #"(?i)(\b(?:c[oó]digo(?!\s*postal)|code|otp|verificaci[oó]n|verification)\b[^\d\n]{0,24}?)(?<!\d)\d{4,8}(?!\d)"#,
    ].map(compile)

    /// True when text names a strong label followed by its separator. The
    /// memory gate asks this so a fact such as "mi contraseña: ..." is refused
    /// even when the redaction above would change nothing.
    package static func holdsStrongLabel(_ text: String) -> Bool {
        strongLabel.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static let strongLabel = compile(
        #"(?i)(?<![A-Za-z0-9])(?:[A-Za-z0-9]+_)?(?:password|passwd|contraseña|clave|secret|pin)[ \t]*[:=]"#)

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
        var result = text
        for regex in patterns {
            result = replace(regex, in: result, with: mask)
        }
        for regex in keepingPrefix {
            result = replace(regex, in: result, with: "$1\(mask)")
        }
        result = maskDigitRuns(result)
        for (regex, isSensitive) in validated {
            result = maskMatches(regex, in: result, where: isSensitive)
        }
        return result
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    private static func maskMatches(
        _ regex: NSRegularExpression, in text: String, where isSensitive: (String) -> Bool
    ) -> String {
        var result = text
        // Back to front so earlier ranges stay valid while the string shrinks.
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result), isSensitive(String(result[range])) else { continue }
            result.replaceSubrange(range, with: mask)
        }
        return result
    }

    private static func maskDigitRuns(_ text: String) -> String {
        var result = text
        for match in digitRun.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let run = String(result[range])
            let masked = splitAtLongFractions(run).map { $0.isFraction ? String($0.text) : maskPiece(String($0.text)) }
            result.replaceSubrange(range, with: masked.joined())
        }
        return result
    }

    /// A float's fraction ("0.9999963045120239") shares the digit-run shape, but no
    /// card or CLABE prints a group longer than 6 digits after a dot. Only that
    /// fraction is set aside: skipping the whole run would let a card next to a
    /// price or an IP through.
    private static func splitAtLongFractions(_ run: String) -> [(text: Substring, isFraction: Bool)] {
        var parts: [(text: Substring, isFraction: Bool)] = []
        var start = run.startIndex
        var cursor = run.startIndex
        while let dot = run[cursor...].firstIndex(of: ".") {
            let fractionStart = run.index(after: dot)
            let fractionEnd = run[fractionStart...].firstIndex(where: { !$0.isNumber }) ?? run.endIndex
            cursor = fractionEnd
            guard run.distance(from: fractionStart, to: fractionEnd) > 6 else { continue }
            parts.append((run[start..<dot], false))
            parts.append((run[dot..<fractionEnd], true))
            start = fractionEnd
        }
        parts.append((run[start...], false))
        return parts
    }

    /// The whole piece first (a CLABE, or a card with a CVV glued to it), then
    /// every span of whole digit groups, so a card next to a short number or a
    /// second card in the same run still masks.
    private static func maskPiece(_ piece: String) -> String {
        let digitCount = piece.filter(\.isNumber).count
        guard digitCount >= 13 else { return piece }
        if digitCount == 18, IdentifierChecks.isCLABE(piece) { return mask }
        if let window = IdentifierChecks.cardWindow(in: piece) {
            return piece.replacingCharacters(in: window, with: mask)
        }
        return maskGroupSpans(piece)
    }

    private static func maskGroupSpans(_ piece: String) -> String {
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
        var result = piece
        for hit in hits.reversed() { result.replaceSubrange(hit, with: mask) }
        return result
    }

    private static func sensitiveSpanEnd(_ piece: String, groups: [Range<String.Index>], from first: Int) -> Int? {
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

    private static func groupRanges(_ piece: String) -> [Range<String.Index>] {
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
