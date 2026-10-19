import CompanionCore
import Foundation

/// web_fetch returns what a page says, not its markup. One linear pass over
/// the scalars. An unterminated comment, element or tag runs to the end of the
/// capped source and is dropped, as browsers drop it, so no input makes the
/// pass rescan: regexes here were quadratic on a page of unclosed openers, and
/// NSRegularExpression cannot be cancelled.
package enum WebHTMLText {
    /// The source is cut before the scan, in bytes, so the work is bounded.
    static let maxSourceBytes = 200_000

    private static let skipped: Set<String> = [
        "script", "style", "noscript", "template", "nav", "svg", "iframe",
    ]
    private static let blockTags: Set<String> = [
        "p", "div", "br", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6", "section",
        "article", "header", "footer", "main", "table", "ul", "ol", "blockquote", "pre",
        "hr", "dt", "dd",
    ]
    private static let cellTags: Set<String> = ["td", "th"]
    /// Markers that make a body HTML rather than data that only looks like tags.
    private static let markers: Set<String> = [
        "!doctype", "html", "head", "body", "title", "p", "div", "span", "a", "br",
        "table", "script", "style", "nav", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol",
    ]
    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
        "ndash": "–", "mdash": "—", "hellip": "…", "copy": "©", "euro": "€",
        "laquo": "«", "raquo": "»", "middot": "·",
        "lsquo": "‘", "rsquo": "’", "ldquo": "“", "rdquo": "”",
    ]

    package static func page(from body: String, url: String) -> WebPage {
        extract(body, url: url).page
    }

    /// `steps` is the work the scan did, counted per scalar examined, so a test
    /// can assert linearity without a clock.
    static func extract(_ body: String, url: String) -> (page: WebPage, steps: Int) {
        let source = String(decoding: body.utf8.prefix(maxSourceBytes), as: UTF8.self)
        guard looksLikeHTML(source) else {
            return (WebPage(title: "", url: url, text: source), 0)
        }
        var scanner = Scanner(source: Array(source.unicodeScalars))
        scanner.run()
        return (WebPage(title: collapse(scanner.title), url: url, text: collapse(scanner.text)),
                scanner.steps)
    }

    private static func looksLikeHTML(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars)
        for start in scalars.indices where scalars[start] == "<" {
            var name = ""
            var k = start + 1
            while k < scalars.count, name.count < 9, isLetter(scalars[k]) || scalars[k] == "!" {
                name.unicodeScalars.append(scalars[k])
                k += 1
            }
            if markers.contains(name.lowercased()) { return true }
        }
        return false
    }

    private static func isLetter(_ c: Unicode.Scalar) -> Bool {
        (c >= "a" && c <= "z") || (c >= "A" && c <= "Z")
    }

    /// Entity at `start` (an "&"): a name up to ";" within a short window.
    /// Windows never contain "&", so the windows of all entities together stay
    /// linear in the source.
    private static func entity(at start: Int, in s: [Unicode.Scalar]) -> (text: String, next: Int)? {
        var k = start + 1
        while k < s.count, k - start <= 32 {
            let c = s[k]
            if c == ";" {
                let name = String(String.UnicodeScalarView(s[(start + 1)..<k]))
                if name.hasPrefix("#") {
                    let hex = name.dropFirst().first.map { $0 == "x" || $0 == "X" } ?? false
                    let digits = hex ? String(name.dropFirst(2)) : String(name.dropFirst())
                    guard let code = UInt32(digits, radix: hex ? 16 : 10),
                          let scalar = Unicode.Scalar(code)
                    else { return nil }
                    return (String(scalar), k + 1)
                }
                return namedEntities[name].map { ($0, k + 1) }
            }
            guard isLetter(c) || (c >= "0" && c <= "9") || c == "#" else { return nil }
            k += 1
        }
        return nil
    }

    /// Each line keeps its words with single spaces; blank runs become one
    /// blank line, so a page's layout does not spend the cap on whitespace.
    private static func collapse(_ raw: String) -> String {
        var lines: [String] = []
        for part in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = part.split(whereSeparator: { $0 == " " || $0 == "\t" }).joined(separator: " ")
            if line.isEmpty {
                if let last = lines.last, !last.isEmpty { lines.append("") }
            } else {
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct Scanner {
        let s: [Unicode.Scalar]
        var i = 0
        var steps = 0
        var text = ""
        var title = ""
        private var titleSeen = false

        init(source: [Unicode.Scalar]) { s = source }

        mutating func run() {
            while i < s.count {
                steps += 1
                let c = s[i]
                if c == "<" {
                    markup()
                } else if c == "&" {
                    if let decoded = WebHTMLText.entity(at: i, in: s) {
                        text += decoded.text
                        i = decoded.next
                    } else {
                        text += "&"
                        i += 1
                    }
                } else {
                    text.unicodeScalars.append(c)
                    i += 1
                }
            }
        }

        /// `i` is at "<". Anything that is not a tag or comment is literal text.
        private mutating func markup() {
            guard i + 1 < s.count else {
                text += "<"
                i += 1
                return
            }
            let next = s[i + 1]
            if next == "!" {
                if matches("<!--", at: i) {
                    i = indexAfter("-->", from: i + 4)
                } else {
                    i = indexAfterByte(">", from: i + 2)
                }
                return
            }
            if next == "?" {
                i = indexAfterByte(">", from: i + 2)
                return
            }
            let closing = next == "/"
            var j = closing ? i + 2 : i + 1
            let nameStart = j
            while j < s.count, isNameScalar(s[j]) {
                steps += 1
                j += 1
            }
            guard j > nameStart, isLetterScalar(s[nameStart]) else {
                text += "<"
                i += 1
                return
            }
            let name = String(String.UnicodeScalarView(s[nameStart..<j])).lowercased()
            guard let end = tagEnd(from: j) else {
                i = s.count
                return
            }
            i = end + 1
            if closing {
                if blockTags.contains(name) { text += "\n" }
                return
            }
            if name == "title" {
                captureTitle()
                return
            }
            if skipped.contains(name), !(end > 0 && s[end - 1] == "/") {
                i = indexAfterElement(name)
                return
            }
            if blockTags.contains(name) {
                text += "\n"
            } else if cellTags.contains(name) {
                text += " "
            }
        }

        /// The first title is what the page is called. Its text runs to
        /// "</title"; a title with no close runs to the end, as any unclosed element does.
        private mutating func captureTitle() {
            let start = i
            let close = findClose("title", from: start)
            if !titleSeen {
                titleSeen = true
                title = decodeAll(Array(s[start..<close.contentEnd]))
            }
            steps += close.contentEnd - start
            i = close.resume
        }

        private func decodeAll(_ raw: [Unicode.Scalar]) -> String {
            var out = ""
            var k = 0
            while k < raw.count {
                if raw[k] == "&", let decoded = WebHTMLText.entity(at: k, in: raw) {
                    out += decoded.text
                    k = decoded.next
                } else {
                    out.unicodeScalars.append(raw[k])
                    k += 1
                }
            }
            return out
        }

        /// Index just past the closing tag of a skipped element, or the end.
        private mutating func indexAfterElement(_ name: String) -> Int {
            let close = findClose(name, from: i)
            steps += close.contentEnd - i
            return close.resume
        }

        /// Where the content of element `name` ends, and where scanning resumes.
        /// Missing close: content runs to the end, resume there.
        private mutating func findClose(_ name: String, from start: Int) -> (contentEnd: Int, resume: Int) {
            let needle = Array("</\(name)".unicodeScalars)
            var k = start
            while k < s.count {
                steps += 1
                if matchesCaseless(needle, at: k) {
                    let after = k + needle.count
                    if after >= s.count { break }
                    let boundary = s[after]
                    if boundary == ">" || boundary == " " || boundary == "\t" || boundary == "\n" || boundary == "/" {
                        let end = tagEnd(from: after) ?? s.count - 1
                        return (k, min(end + 1, s.count))
                    }
                }
                k += 1
            }
            return (s.count, s.count)
        }

        /// The ">" that closes a tag, skipping quoted attribute values. Nil when
        /// the tag never closes; the caller drops the rest of the source.
        private mutating func tagEnd(from start: Int) -> Int? {
            var quote: Unicode.Scalar?
            var k = start
            while k < s.count {
                steps += 1
                let c = s[k]
                if let open = quote {
                    if c == open { quote = nil }
                } else if c == "\"" || c == "'" {
                    quote = c
                } else if c == ">" {
                    return k
                }
                k += 1
            }
            return nil
        }

        private mutating func indexAfterByte(_ mark: Unicode.Scalar, from start: Int) -> Int {
            var k = start
            while k < s.count {
                steps += 1
                if s[k] == mark { return k + 1 }
                k += 1
            }
            return s.count
        }

        private mutating func indexAfter(_ marker: String, from start: Int) -> Int {
            let needle = Array(marker.unicodeScalars)
            var k = start
            while k < s.count {
                steps += 1
                if matches(needle, at: k) { return k + needle.count }
                k += 1
            }
            return s.count
        }

        private func matches(_ marker: String, at k: Int) -> Bool {
            matches(Array(marker.unicodeScalars), at: k)
        }

        private func matches(_ needle: [Unicode.Scalar], at k: Int) -> Bool {
            guard k + needle.count <= s.count else { return false }
            for offset in needle.indices where s[k + offset] != needle[offset] { return false }
            return true
        }

        private func matchesCaseless(_ needle: [Unicode.Scalar], at k: Int) -> Bool {
            guard k + needle.count <= s.count else { return false }
            for offset in needle.indices where lowered(s[k + offset]) != lowered(needle[offset]) {
                return false
            }
            return true
        }

        private func lowered(_ c: Unicode.Scalar) -> Unicode.Scalar {
            c >= "A" && c <= "Z" ? Unicode.Scalar(c.value + 32) ?? c : c
        }

        private func isLetterScalar(_ c: Unicode.Scalar) -> Bool { WebHTMLText.isLetter(c) }

        private func isNameScalar(_ c: Unicode.Scalar) -> Bool {
            WebHTMLText.isLetter(c) || (c >= "0" && c <= "9") || c == "-" || c == ":"
        }
    }
}
