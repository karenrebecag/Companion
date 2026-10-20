import Foundation

/// A secret the owner writes stays on this Mac. The thread, the disk and the
/// model only see a reference such as `[[ref:1]]`; an input tool gets the
/// value back right before it types. Computah works the same way: the model
/// points at a source range, and the code types the original text
/// (`CommandLanguage.swift:364`). The values live in memory only, so a
/// reference from an earlier launch can no longer be opened.
package struct SecretVault: Sendable, Equatable {
    /// The only tools that may receive a value: they type it on this Mac.
    /// Every other tool can send its arguments off the machine.
    package static let inputTools: Set<String> = ["type_text", "browser_type"]

    private var values: [String] = []

    package init() {}

    /// The text with each detected secret replaced by its reference. The same
    /// value always gets the same reference.
    package func sealing(_ text: String) -> (vault: SecretVault, text: String) {
        var next = self
        var result = ""
        var cursor = text.startIndex
        for span in TurnRedaction.protectedRanges(in: text) {
            let value = String(text[span])
            if !next.values.contains(value) { next.values.append(value) }
            result += text[cursor..<span.lowerBound] + next.reference(for: value)
            cursor = span.upperBound
        }
        return (next, result + text[cursor...])
    }

    /// Tool output can repeat what was typed ("typed hunter22 into Name"), so
    /// every known value goes back to its reference before the model sees it.
    /// One pass, longest value first, so a short value never rewrites a
    /// reference already put in. A value under `minimumResealed` characters
    /// would rewrite ordinary digits and words, so it is left to the shape
    /// rules that run after (`TurnRedaction.redact`).
    package func resealing(_ text: String) -> String {
        let candidates = values.filter { $0.count >= Self.minimumResealed }.sorted { $0.count > $1.count }
        guard !candidates.isEmpty else { return text }
        let alternation = candidates.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: alternation)
        } catch {
            preconditionFailure("escaped secret values always compile")
        }
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: reference(for: String(result[range])))
        }
        return result
    }

    static let minimumResealed = 4

    /// `text` with every reference replaced by its value, or nil when one of
    /// them is not in this vault.
    package func opening(_ text: String) -> String? {
        let matches = Self.referencePattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var result = text
        for match in matches.reversed() {
            guard let whole = Range(match.range, in: result),
                  let digits = Range(match.range(at: 1), in: result),
                  let number = Int(result[digits]), values.indices.contains(number - 1)
            else { return nil }
            result.replaceSubrange(whole, with: values[number - 1])
        }
        return result
    }

    package static func holdsReference(_ text: String) -> Bool {
        referencePattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private func reference(for value: String) -> String {
        "[[ref:\((values.firstIndex(of: value) ?? values.count) + 1)]]"
    }

    private static let referencePattern: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: #"\[\[ref:(\d+)\]\]"#)
        } catch {
            preconditionFailure("secret reference pattern does not compile")
        }
    }()
}

/// One vault for the whole app: chat and voice seal into it, and every tool
/// path opens from it at the moment of typing, so a reference means the same
/// value wherever it travels. It lives as long as the process on purpose:
/// nothing about a secret outlives a quit.
package final class SecretKeeper: @unchecked Sendable {
    package static let shared = SecretKeeper()

    private let lock = NSLock()
    private var vault = SecretVault()

    package init() {}

    package func seal(_ text: String) -> String {
        lock.withLock {
            let result = vault.sealing(text)
            vault = result.vault
            return result.text
        }
    }

    package func reseal(_ text: String) -> String {
        lock.withLock { vault.resealing(text) }
    }

    package func open(_ text: String) -> String? {
        lock.withLock { vault.opening(text) }
    }
}
