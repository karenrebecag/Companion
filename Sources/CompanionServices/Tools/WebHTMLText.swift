import CompanionCore
import Foundation

/// web_fetch returns what a page says, not its markup: a 200 KB document is
/// mostly script and head, and the model needs the words a reader would see.
/// Regexes rather than a parser, because a page that is not well formed still
/// has to yield its text, and the output is data the caller frames and caps.
package enum WebHTMLText {
    /// Bounds the regex work on a hostile page; the cap that reaches the model
    /// is applied later, by the same fence read_url uses.
    static let maxSourceCharacters = 1_000_000

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "ndash": "–", "mdash": "—", "hellip": "…", "copy": "©", "euro": "€",
        "laquo": "«", "raquo": "»", "middot": "·",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
    ]

    /// Elements whose content is never the page's words: code, styling,
    /// navigation chrome and the head (its title is read before it goes).
    private static let dropped = "script|style|noscript|template|nav|svg|iframe|head"

    private static let blockTags =
        "p|div|br|li|tr|h[1-6]|section|article|header|footer|main|table|ul|ol|blockquote|pre|hr|dt|dd|title"

    package static func page(from body: String, url: String) -> WebPage {
        let source = String(body.prefix(maxSourceCharacters))
        guard looksLikeHTML(source) else {
            return WebPage(title: "", url: url, text: source)
        }
        let title = collapse(text: decode(stripTags(captured(
            "<title[^>]*>(.*?)</title", in: source))))
        var text = substitute(source, "<!--.*?-->", options: [.dotMatchesLineSeparators]) { _ in "" }
        text = substitute(text, "<(\(dropped))\\b[^>]*>.*?</\\1\\s*>",
                          options: [.dotMatchesLineSeparators, .caseInsensitive]) { _ in "" }
        text = substitute(text, "</?(td|th)\\b[^>]*>", options: [.caseInsensitive]) { _ in " " }
        text = substitute(text, "</?(\(blockTags))\\b[^>]*>", options: [.caseInsensitive]) { _ in "\n" }
        text = collapse(text: decode(stripTags(text)))
        return WebPage(title: title, url: url, text: text)
    }

    /// A fragment with a paragraph is markup too; `<b>` alone in a JSON body is not.
    private static func looksLikeHTML(_ text: String) -> Bool {
        text.range(of: "<(!doctype|html|head|body|title|p|div|span|a|br|table|script|style|nav|h[1-6]|li|ul|ol)\\b",
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func stripTags(_ text: String) -> String {
        substitute(text, "<[^>]*>") { _ in "" }
    }

    private static func captured(_ pattern: String, in text: String) -> String {
        let regex = ConstantPattern.compile(
            pattern, options: [.dotMatchesLineSeparators, .caseInsensitive])
        guard let match = regex.firstMatch(
                in: text, range: NSRange(location: 0, length: (text as NSString).length)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return "" }
        return String(text[range])
    }

    /// Entities are decoded after the tags are gone, so an encoded `<` stays
    /// text instead of becoming markup the model would be told about.
    private static func decode(_ text: String) -> String {
        substitute(text, "&(#[xX][0-9a-fA-F]+|#[0-9]+|[A-Za-z]+);") { match in
            let name = String(match.dropFirst().dropLast())
            if name.hasPrefix("#") {
                let isHex = name.dropFirst().first.map { $0 == "x" || $0 == "X" } ?? false
                let digits = isHex ? String(name.dropFirst(2)) : String(name.dropFirst())
                guard let code = UInt32(digits, radix: isHex ? 16 : 10),
                      let scalar = Unicode.Scalar(code)
                else { return match }
                return String(scalar)
            }
            return namedEntities[name] ?? match
        }
    }

    /// Each line keeps its words with single spaces; blank runs become one
    /// blank line, so a page's layout does not spend the cap on whitespace.
    private static func collapse(text: String) -> String {
        var lines: [String] = []
        for raw in text.components(separatedBy: "\n") {
            let line = substitute(raw, "[ \t]+") { _ in " " }
                .trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                if let last = lines.last, !last.isEmpty { lines.append("") }
            } else {
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func substitute(
        _ text: String, _ pattern: String,
        options: NSRegularExpression.Options = [],
        with replacement: (String) -> String
    ) -> String {
        let regex = ConstantPattern.compile(pattern, options: options)
        let source = text as NSString
        var out = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            out += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            out += replacement(source.substring(with: match.range))
            cursor = match.range.location + match.range.length
        }
        out += source.substring(from: cursor)
        return out
    }
}
