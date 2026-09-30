import Foundation

/// Turns the sidecar model's text into a brief. Pure: no network, no image.
package enum ScreenBriefParser {
    package static func parse(_ raw: String) -> ScreenBrief {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ScreenBrief() }
        var summary: String?
        var snippets: [ScreenSnippet] = []
        let lines = text.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        var inSnippets = false
        for line in lines {
            let upper = line.uppercased()
            if upper.hasPrefix("SUMMARY:") {
                inSnippets = false
                let rest = String(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { summary = rest }
                continue
            }
            if upper.hasPrefix("SNIPPETS:") {
                inSnippets = true
                continue
            }
            if inSnippets, let snippet = snippet(from: line) {
                snippets.append(snippet)
            }
        }
        if snippets.count > 12 { snippets = Array(snippets.prefix(12)) }
        return ScreenBrief(summary: summary, snippets: snippets)
    }

    /// `[Safari] "the visible words"` or `[Safari] the visible words`. The
    /// model drops the `[App]` often enough that a quoted or bulleted line
    /// counts too; loose prose does not.
    private static func snippet(from line: String) -> ScreenSnippet? {
        guard line.first == "[" else { return unbracketed(line) }
        guard let close = line.firstIndex(of: "]") else { return nil }
        let app = String(line[line.index(after: line.startIndex)..<close])
            .trimmingCharacters(in: .whitespaces)
        guard !app.isEmpty else { return nil }
        var rest = String(line[line.index(after: close)...])
            .trimmingCharacters(in: .whitespaces)
        if rest.hasPrefix("\"") && rest.hasSuffix("\"") && rest.count >= 2 {
            rest = String(rest.dropFirst().dropLast())
        }
        rest = rest.trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }
        return ScreenSnippet(app: app, text: rest)
    }

    private static func unbracketed(_ line: String) -> ScreenSnippet? {
        var rest = line
        let bulleted = rest.hasPrefix("- ") || rest.hasPrefix("* ")
        if bulleted { rest = String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        let quoted = rest.hasPrefix("\"") && rest.hasSuffix("\"") && rest.count >= 2
        guard bulleted || quoted else { return nil }
        if quoted { rest = String(rest.dropFirst().dropLast()) }
        rest = rest.trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? nil : ScreenSnippet(app: "screen", text: rest)
    }
}
