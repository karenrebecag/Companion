import Foundation

/// The one place markdown becomes words for the voice and the island's
/// subtitle. A document goes through `show_document` and is never spoken
/// (`SpokenDocument`); this is the safety net for emphasis, a stray marker
/// or a glued line break ("mAhCámara", "3.Vierte") in what IS spoken.
package enum SpeechMarkdown {
    package enum Kind: Sendable, Equatable {
        case text
        case bullet
        /// "3." as the model wrote it; the number is kept, the space after it guaranteed.
        case ordered(String)
        /// A table row read as its cells.
        case row
    }

    package struct Line: Sendable, Equatable {
        package let text: String
        package let kind: Kind
    }

    /// A whole cut as speech: every line normalized, every break a space.
    package static func plain(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .compactMap { line(String($0)) }
            .map { line in
                if case .ordered(let number) = line.kind { return number + " " + line.text }
                return line.text
            }
            .joined(separator: " ")
    }

    /// One line without its markup; nil when it carries no words (a table
    /// separator, a rule, a blank).
    package static func line(_ raw: String) -> Line? {
        var line = raw.trimmingCharacters(in: .whitespaces)
        // The mouth closes a line without a mark with a full stop before it
        // cuts; after a row's last pipe that stop is not a word.
        if line.hasSuffix("|.") { line.removeLast() }
        guard !line.isEmpty, !isRule(line) else { return nil }
        if isTableLine(line) {
            if isSeparator(line) { return nil }
            let cells = line.split(separator: "|", omittingEmptySubsequences: true)
                .map { inline(String($0)) }
                .filter { !$0.isEmpty && $0 != "." }
            return cells.isEmpty ? nil : Line(text: cells.joined(separator: ", "), kind: .row)
        }
        var kind = Kind.text
        line = line.replacingOccurrences(of: #"^#{1,6}\s*"#, with: "", options: .regularExpression)
        line = line.replacingOccurrences(of: #"^>\s*"#, with: "", options: .regularExpression)
        if let marker = line.range(of: #"^[-*+•]\s+"#, options: .regularExpression) {
            kind = .bullet
            line = String(line[marker.upperBound...])
        } else if let marker = line.range(
            of: #"^\d{1,3}[.)](\s+|(?=[\p{L}¿¡«]))"#, options: .regularExpression) {
            let number = line[marker].trimmingCharacters(in: .whitespaces)
            kind = .ordered(String(number.dropLast()) + ".")
            line = String(line[marker.upperBound...])
        }
        let text = inline(line)
        return text.isEmpty ? nil : Line(text: text, kind: kind)
    }

    /// A row or separator of a pipe table, whether or not it opens with a pipe.
    package static func isTableLine(_ line: String) -> Bool {
        let pipes = line.filter { $0 == "|" }.count
        return pipes >= 2 || (pipes == 1 && (line.hasPrefix("|") || line.hasSuffix("|")))
    }

    package static func isSeparator(_ line: String) -> Bool {
        line.contains("-") && line.allSatisfy { "|-: .".contains($0) }
    }

    private static func isRule(_ line: String) -> Bool {
        line.count >= 3 && line.allSatisfy { "-*_ ".contains($0) }
    }

    private static func inline(_ text: String) -> String {
        var out = text
            .replacingOccurrences(
                of: #"\[([^\[\]]*)\]\([^)]{0,512}\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
        // A lone * or _ is emphasis only when it wraps a word; "snake_case"
        // and "2 * 3" stay as written.
        out = out.replacingOccurrences(
            of: #"(?<![\w*])\*(?=\S)([^*\n]+?)(?<=\S)\*(?![\w*])"#, with: "$1", options: .regularExpression)
        out = out.replacingOccurrences(
            of: #"(?<!\w)_(?=\S)([^_\n]+?)(?<=\S)_(?!\w)"#, with: "$1", options: .regularExpression)
        return out.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }
}
