import Foundation

/// Puente QA: text that leaves for the agent passes through here first. The
/// turn can read a page or a file that holds a credential, and the agent is a
/// third party; a pattern that is not recognised still leaves, so this lowers
/// the odds, it does not make the output safe.
package enum TurnRedaction {
    package static let mask = "[redacted]"

    private static let patterns: [NSRegularExpression] = [
        #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?(-----END [A-Z ]*PRIVATE KEY-----|$)"#,
        #"\bsk-[A-Za-z0-9_\-]{16,}"#,
        #"(?i)\bBearer\s+[A-Za-z0-9._~+/\-]{8,}=*"#,
        #"\b(AKIA|ASIA)[0-9A-Z]{16}\b"#,
        #"\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}"#,
        #"\bgithub_pat_[A-Za-z0-9_]{20,}"#,
        #"\bxox[bpas]-[A-Za-z0-9\-]{10,}"#,
        #"(?im)^([ \t]*(?:export[ \t]+)?[A-Za-z0-9_.\-]*(?:SECRET|TOKEN|KEY|PASSWORD)[A-Za-z0-9_.\-]*[ \t]*[=:][ \t]*).+$"#,
    ].map { pattern in
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("redaction pattern does not compile: \(pattern)")
        }
    }

    package static func redact(_ text: String) -> String {
        var result = text
        for (index, regex) in patterns.enumerated() {
            let range = NSRange(result.startIndex..., in: result)
            // The KEY=value rule keeps the name and masks the value.
            let template = index == patterns.count - 1 ? "$1\(mask)" : mask
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: template)
        }
        return result
    }
}
