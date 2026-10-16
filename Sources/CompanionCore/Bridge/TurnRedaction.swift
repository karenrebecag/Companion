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
        "list_directory", "sheet_read", "web_search", "read_skill",
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
        #"\bsk[-_][A-Za-z0-9_\-]{16,}"#,
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
    private static let keepingPrefix: [NSRegularExpression] = [
        #"(?im)^([ \t]*(?:export[ \t]+)?[A-Za-z0-9_.\-]*(?:SECRET|TOKEN|KEY|PASSWORD)[A-Za-z0-9_.\-]*[ \t]*[=:][ \t]*).+$"#,
        // The same, anywhere in a line ("client secret: Xy8Q~...")
        #"(?i)\b([A-Za-z0-9_]*(?:secret|token|password|passwd|clave|contraseña|key)\w*[ \t]*[:=][ \t]*["']?)[^\s"'<>,;]{6,}"#,
        // A bare hex string is only a secret when a word says so
        #"(?i)\b((?:secret|client|token|key)(?:[ \t_\-]+[A-Za-z]{1,12}\b){0,2}[ \t]*[:=]?[ \t]*["']?)[0-9a-f]{32,}\b"#,
    ].map(compile)

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

    /// A CLABE is a whole run of 18 digits; a card is any 13 to 19 digit window
    /// of a run that passes Luhn, so a CVV or a date glued to it cannot hide it.
    private static func maskDigitRuns(_ text: String) -> String {
        var result = text
        for match in digitRun.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let run = String(result[range])
            let digitCount = run.filter(\.isNumber).count
            guard digitCount >= 13 else { continue }
            if digitCount == 18, IdentifierChecks.isCLABE(run) {
                result.replaceSubrange(range, with: mask)
            } else if let window = IdentifierChecks.cardWindow(in: run) {
                result.replaceSubrange(range, with: run.replacingCharacters(in: window, with: mask))
            }
        }
        return result
    }
}
