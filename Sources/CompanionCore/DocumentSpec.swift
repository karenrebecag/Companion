import Foundation

// Wave 20-2 (spec 20 §4 D4): a document is a list of blocks the model picks;
// the template owns the look, as Incredible's Doc()/Deck() do. The model
// never writes HTML, so nothing it says can become markup or script.

public enum DocumentFormat: String, Sendable, Equatable {
    case pdf, xlsx

    public init?(path: String) {
        self.init(rawValue: URL(fileURLWithPath: path).pathExtension.lowercased())
    }
}

public struct DocumentSpec: Sendable, Equatable {
    public enum Tone: String, Sendable, Equatable { case info, success, warning, danger }

    public enum Block: Sendable, Equatable {
        case cover(title: String, subtitle: String?, date: String?)
        case heading(String, level: Int)
        case paragraph(String)
        case bullets([String])
        case stats(StatsBlock)
        case table(TableBlock)
        case chart(ChartBlock)
        case callout(String, tone: Tone)
        case divider
    }

    public static let maxBlocks = 200
    public static let maxText = 20_000
    public static let maxBullets = 100

    public var title: String
    public var subtitle: String?
    public var blocks: [Block]
    /// Only an explicit request turns "=..." table cells into live formulas
    /// in an .xlsx; otherwise they are literal text.
    public var allowFormulas: Bool

    public init(title: String, subtitle: String? = nil, blocks: [Block], allowFormulas: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self.blocks = blocks
        self.allowFormulas = allowFormulas
    }

    /// Providers send a nested argument either as JSON text or as an object.
    public static func parse(any value: Any?) -> DocumentSpec? {
        if let text = value as? String { return parse(text) }
        if let dict = value as? [String: Any] { return parse(dict: dict) }
        return nil
    }

    public static func parse(_ json: String) -> DocumentSpec? {
        CompanionBlocks.jsonObject(json).flatMap(parse(dict:))
    }

    static func parse(dict: [String: Any]) -> DocumentSpec? {
        guard let title = text(dict["title"]), !title.isEmpty,
              let raw = dict["blocks"] as? [Any] else { return nil }
        // An unknown block is skipped, not fatal: one odd block from the
        // model must not cost the whole report.
        let blocks = raw.compactMap { ($0 as? [String: Any]).flatMap(block(from:)) }
            .prefix(maxBlocks)
        guard !blocks.isEmpty else { return nil }
        return DocumentSpec(title: title, subtitle: text(dict["subtitle"]), blocks: Array(blocks),
                            allowFormulas: dict["formulas"] as? Bool == true)
    }

    private static func block(from dict: [String: Any]) -> Block? {
        switch dict["type"] as? String {
        case "cover":
            return text(dict["title"]).map { .cover(title: $0, subtitle: text(dict["subtitle"]), date: text(dict["date"])) }
        case "heading":
            let level = (dict["level"] as? Int).map { min(max($0, 1), 3) } ?? 1
            return text(dict["text"]).map { .heading($0, level: level) }
        case "paragraph":
            return text(dict["text"]).map { .paragraph($0) }
        case "bullets":
            let items = (dict["items"] as? [Any] ?? []).compactMap(text).prefix(maxBullets)
            return items.isEmpty ? nil : .bullets(Array(items))
        case "stats":
            return CompanionBlocks.stats(from: dict).map { .stats($0) }
        case "table":
            return CompanionBlocks.table(from: dict).map { .table($0) }
        case "chart":
            switch CompanionBlocks.chart(from: dict) {
            case .chart(let chart): return .chart(chart)
            case .table(let table): return .table(table)
            default: return nil
            }
        case "callout":
            let tone = (dict["tone"] as? String).flatMap(Tone.init(rawValue:)) ?? .info
            return text(dict["text"]).map { .callout($0, tone: tone) }
        case "divider":
            return .divider
        default:
            return nil
        }
    }

    private static func text(_ raw: Any?) -> String? {
        guard let value = DataCells.text(raw)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return String(value.prefix(maxText))
    }
}

/// What a finished document is, for the receipt: the model hears the path
/// and the size; the file itself never enters its context.
public struct DocumentReceipt: Sendable, Equatable {
    public var pages: Int?
    public var bytes: Int

    public init(pages: Int?, bytes: Int) {
        self.pages = pages
        self.bytes = bytes
    }
}

public enum DocumentError: Error, Sendable, Equatable {
    case unsupportedFormat
    case renderFailed
    case timedOut
}

/// Port for `create_document` (spec 20-2): the template and the printer live
/// in Services; Core only says what to draw.
public protocol DocumentRendering: Sendable {
    func render(_ spec: DocumentSpec, format: DocumentFormat, to url: URL) async throws -> DocumentReceipt
}
