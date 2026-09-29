import Foundation

/// One checkbox line of a task block.
public struct TaskLine: Sendable, Equatable {
    public var done: Bool
    public var text: String
    public init(done: Bool, text: String) {
        self.done = done
        self.text = text
    }
}

/// The typed blocks of the island's rich answer popup (16m-1). Incredible's
/// catalog names blocks the markdown splitter does not — tasks, callout,
/// file chip, eyebrow — so they are DERIVED here, in Core, where a test can
/// pin exactly which markdown becomes which block before any view exists.
public enum AnswerBlock: Sendable, Equatable {
    case title(String)
    case section(String)
    case eyebrow(String)
    case paragraph(String)
    case list(ordered: Bool, items: [MarkdownSplitter.Item])
    case tasks([TaskLine])
    case quote(String)
    case callout(title: String, body: String)
    case rule
    case code(language: String, body: String)
    case table(headers: [String], rows: [[String]])
    case fileChip(String)
    case card(CardPayload)
    case choice(ChoiceBlock)
}

public extension AnswerBlock {
    var isChoice: Bool {
        if case .choice = self { return true }
        return false
    }
}

public enum AnswerBlocks {
    /// The card's summary cap (IslandResult.maxLine): anything the card can
    /// already say whole has no popup to earn.
    static let plainCap = 240

    public static func blocks(from markdown: String) -> [AnswerBlock] {
        MarkdownSplitter.split(markdown).map { block(of: $0.kind) }
    }

    /// True when the answer holds more than the result card can say: any
    /// structured block, or prose past the card's own cap (D2, spec §5 —
    /// a short phrase never opens the popup).
    public static func isRich(_ blocks: [AnswerBlock]) -> Bool {
        var plain = 0
        for block in blocks {
            switch block {
            case .paragraph(let text): plain += text.count
            // Answered from the island itself: it earns no popup.
            case .choice: continue
            default: return true
            }
        }
        return plain > plainCap
    }

    private static func block(of kind: MarkdownSplitter.Kind) -> AnswerBlock {
        switch kind {
        case .heading(let level, let text):
            switch level {
            case 1: return .title(text)
            case 2: return .section(text)
            default: return .eyebrow(text)
            }
        case .prose(let text):
            if let path = lonePath(text) { return .fileChip(path) }
            return .paragraph(text)
        case .list(let ordered, let items):
            if let tasks = taskLines(items) { return .tasks(tasks) }
            return .list(ordered: ordered, items: items)
        case .quote(let text):
            if let callout = callout(text) { return callout }
            return .quote(text)
        case .rule:
            return .rule
        case .code(let language, let body):
            if language == CompanionBlocks.choiceLanguage, let choice = CompanionBlocks.choice(body) {
                return .choice(choice)
            }
            if let payload = fencePayload(language: language, body: body) {
                return .card(payload)
            }
            return .code(language: language, body: body)
        case .table(let headers, let rows):
            return .table(headers: headers, rows: rows)
        }
    }

    /// Every item a checkbox, or none: one stray checkbox must not turn its
    /// plain siblings into tasks.
    private static func taskLines(_ items: [MarkdownSplitter.Item]) -> [TaskLine]? {
        var lines: [TaskLine] = []
        for item in items {
            guard let range = item.text.range(
                of: #"^\[( |x|X)\]\s+"#, options: .regularExpression)
            else { return nil }
            let mark = item.text[range]
            lines.append(TaskLine(
                done: mark.contains("x") || mark.contains("X"),
                text: String(item.text[range.upperBound...])))
        }
        return lines.isEmpty ? nil : lines
    }

    /// "> **Título:** cuerpo" reads as a callout: the bold lead is the title,
    /// the rest the body. A quote without that shape stays a quote.
    private static func callout(_ text: String) -> AnswerBlock? {
        guard text.hasPrefix("**"),
              let close = text.range(of: "**", range:
                text.index(text.startIndex, offsetBy: 2) ..< text.endIndex)
        else { return nil }
        var title = String(text[text.index(text.startIndex, offsetBy: 2) ..< close.lowerBound])
        if title.hasSuffix(":") { title = String(title.dropLast()) }
        let body = text[close.upperBound...]
            .trimmingCharacters(in: CharacterSet(charactersIn: ": "))
        guard !title.isEmpty, !body.isEmpty else { return nil }
        return .callout(title: title, body: body)
    }

    /// A line that is nothing but `a/path.ext` in inline code is a file
    /// chip. Spaces mean prose; no separator or dot means it is not a path.
    private static func lonePath(_ text: String) -> String? {
        guard text.hasPrefix("`"), text.hasSuffix("`"), text.count > 2
        else { return nil }
        let inner = String(text.dropFirst().dropLast())
        guard !inner.contains("`"), !inner.contains(where: \.isWhitespace),
              inner.contains("/") || inner.contains(".")
        else { return nil }
        return inner
    }

    /// The window's data fences are cards in the popup too; a broken one
    /// stays visible as code. Gallery is the exception (security review
    /// 16m): its card loads model-supplied paths and URLs at RENDER time,
    /// no click, and the popup floats above every app — a zero-click
    /// beacon. Until CompanionBlocks validates the gallery (https-only,
    /// path allowlist), the fence shows as code here. Locations already
    /// validates https-only, so it stays.
    private static func fencePayload(language: String, body: String) -> CardPayload? {
        switch language {
        case CompanionBlocks.statsLanguage: return CompanionBlocks.stats(body).map { .stats($0) }
        case CompanionBlocks.tableLanguage: return CompanionBlocks.table(body).map { .table($0) }
        case CompanionBlocks.chartLanguage: return CompanionBlocks.chart(body)
        case CompanionBlocks.locationsLanguage:
            return CompanionBlocks.locations(body).map { .locations($0) }
        default: return nil
        }
    }
}
