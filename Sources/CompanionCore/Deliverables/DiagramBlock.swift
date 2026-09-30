import Foundation

/// A Mermaid diagram the model wrote into a `companion:diagram` fence
/// (16m-5b). The body is the Mermaid text itself, not JSON: a model that
/// knows Mermaid writes it fluently, and wrapping it in JSON only adds
/// escaping to get wrong.
public struct DiagramBlock: Sendable, Equatable, Hashable {
    /// Mermaid's own `maxTextSize` is 50 000 characters; a diagram that fits
    /// the island's 504-wide canvas is far smaller than that.
    // HACK: a round number, not measured against real answers. Raise it when
    // a legitimate diagram lands on the cap and reads fine.
    public static let maxSourceBytes = 16 * 1024
    public var source: String

    public init(source: String) { self.source = source }
}

public extension CompanionBlocks {
    static let diagramLanguage = "companion:diagram"

    /// Nil sends the fence back to a code block, visible: an over-cap or
    /// empty diagram is never half drawn, and never silently cut.
    static func diagram(_ body: String) -> DiagramBlock? {
        guard body.utf8.count <= DiagramBlock.maxSourceBytes else { return nil }
        // Line endings first: the sanitizer drops a lone CR, which would glue
        // the lines of an old-style body into one.
        let unified = body.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let text = TextSanitizer.display(unified, maxLength: DiagramBlock.maxSourceBytes)
        guard let stripped = DiagramSource.stripped(text) else { return nil }
        let source = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        return source.isEmpty ? nil : DiagramBlock(source: source)
    }
}

/// What Mermaid text may carry into the page. The page fixes the theme and
/// the security level; the model's text may not move either, and a callback
/// or link is behavior, not drawing. Text that cannot be cleaned without
/// guessing is refused (nil) so it shows whole, as code, never half-eaten.
enum DiagramSource {
    static func stripped(_ text: String) -> String? {
        guard let clean = withoutDirectives(text) else { return nil }
        var kept: [String] = []
        for line in withoutFrontmatter(clean.components(separatedBy: "\n")) {
            // `A --> B; click A href ...` is two statements on one line.
            if line.components(separatedBy: ";").dropFirst().contains(where: isInteraction) { return nil }
            if isInteraction(line) { continue }
            kept.append(line)
        }
        return kept.joined(separator: "\n")
    }

    /// `%%{ ... }%%`, on one line or several, anywhere (Mermaid reads it
    /// anywhere). An unclosed one is nil: cutting to the end would delete the
    /// rest of the diagram without a word.
    private static func withoutDirectives(_ text: String) -> String? {
        var out = text
        while let open = out.range(of: "%%{") {
            guard let close = out.range(of: "}%%", range: open.upperBound ..< out.endIndex) else { return nil }
            out.removeSubrange(open.lowerBound ..< close.upperBound)
        }
        return out
    }

    /// `---` ... `---` at the top carries `config:`; only a CLOSED block goes.
    private static func withoutFrontmatter(_ lines: [String]) -> [String] {
        guard let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              lines[first].trimmingCharacters(in: .whitespaces) == "---",
              let close = lines[(first + 1)...].firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return lines }
        return Array(lines[(close + 1)...])
    }

    /// `click`, and the `link`/`links` of sequence diagrams and the
    /// `link`/`callback` of class diagrams. A node that is merely NAMED like
    /// one (`link --> B`) has an arrow, not a name or a quote, after it.
    private static func isInteraction(_ segment: String) -> Bool {
        let tokens = segment.trimmingCharacters(in: .whitespaces).split(whereSeparator: \.isWhitespace)
        guard let head = tokens.first?.lowercased() else { return false }
        guard ["click", "link", "links", "callback"].contains(head), tokens.count >= 2 else { return false }
        let second = tokens[1]
        // `click A callback ...`, `click A href ...`, `click A "url"`; a node
        // that is merely NAMED click has an arrow or a bracket after it.
        if head == "click" { return isName(second) }
        if second.hasSuffix(":"), isName(second.dropLast()) { return true }
        return tokens.count >= 3 && isName(second) && (tokens[2].first == "\"" || tokens[2].first == "'")
    }

    private static func isName(_ text: Substring) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
