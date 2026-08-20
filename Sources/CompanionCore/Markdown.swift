import Foundation

public struct MarkdownSplitter: Sendable {
    public struct Item: Sendable, Equatable {
        public var depth: Int
        public var text: String
        public init(depth: Int, text: String) {
            self.depth = depth
            self.text = text
        }
    }

    public enum Kind: Sendable, Equatable {
        case prose(String)
        case heading(level: Int, text: String)
        case list(ordered: Bool, items: [Item])
        case quote(String)
        case rule
        case code(language: String, body: String)
        case table(headers: [String], rows: [[String]])
    }

    public struct Part: Sendable, Equatable {
        public var id: Int
        public var kind: Kind
        public init(id: Int, kind: Kind) {
            self.id = id
            self.kind = kind
        }
    }

    public struct SourceLink: Sendable, Equatable {
        public var title: String
        public var url: String
        public var detail: String?
        public init(title: String, url: String, detail: String? = nil) {
            self.title = title
            self.url = url
            self.detail = detail
        }
    }

    /// Cards stay visible: they are the answer, not the process behind the fold.
    public static func reportCut(_ text: String)
        -> (summary: [Part], cards: [Part], detail: [Part]) {
        var summary: [Part] = [], cards: [Part] = [], detail: [Part] = []
        for part in split(text) {
            if case .code(let lang, _) = part.kind, lang.hasPrefix("companion:") {
                cards.append(part)
            } else if summary.isEmpty {
                summary.append(part)
            } else {
                detail.append(part)
            }
        }
        return (summary, cards, detail)
    }

    /// Copy excludes fences and tables: those copy from their own components.
    public static func plainText(_ parts: [Part]) -> String {
        var out: [String] = []
        for part in parts {
            switch part.kind {
            case .prose(let t), .heading(_, let t), .quote(let t):
                out.append(t)
            case .list(_, let items):
                out.append(items.map {
                    String(repeating: "  ", count: $0.depth) + "- " + $0.text
                }.joined(separator: "\n"))
            case .code, .table, .rule:
                continue
            }
        }
        return out.joined(separator: "\n\n")
    }

    public static func extractSources(_ parts: [Part])
        -> (rest: [Part], web: [SourceLink]) {
        guard let start = parts.firstIndex(where: { isSourcesHeader($0.kind) })
        else { return (parts, []) }

        var web: [SourceLink] = []
        var end = start + 1
        while end < parts.count {
            switch parts[end].kind {
            case .list(_, let items):
                for item in items {
                    let found = links(in: item.text)
                    guard let first = found.first else { continue }
                    web.append(SourceLink(
                        title: first.title, url: first.url,
                        detail: detail(of: item.text)))
                    web.append(contentsOf: found.dropFirst())
                }
            case .prose(let text):
                let found = links(in: text)
                guard !found.isEmpty else { break }
                web.append(contentsOf: found)
            default:
                break
            }
            if case .list = parts[end].kind { end += 1; continue }
            if case .prose(let t) = parts[end].kind, !links(in: t).isEmpty {
                end += 1; continue
            }
            break
        }
        guard !web.isEmpty else { return (parts, []) }
        var seen = Set<String>()
        let unique = web.filter { seen.insert($0.url).inserted }
        var rest = parts
        rest.removeSubrange(start..<end)
        return (rest, unique)
    }

    public static func split(_ text: String) -> [Part] {
        var kinds: [Kind] = []
        for chunk in splitFences(text) {
            guard case .prose(let p) = chunk else {
                kinds.append(chunk)
                continue
            }
            for t in splitTables(p) {
                if case .prose(let inner) = t {
                    kinds.append(contentsOf: splitBlocks(inner))
                } else {
                    kinds.append(t)
                }
            }
        }
        return kinds.enumerated().map { Part(id: $0.offset, kind: $0.element) }
    }

    private static func isSourcesHeader(_ kind: Kind) -> Bool {
        let t: String
        switch kind {
        case .heading(_, let h): t = h
        case .prose(let p): t = p
        default: return false
        }
        let clean = t.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":*"))
            .lowercased()
        return ["sources", "fuentes", "referencias"].contains(clean)
    }

    /// Leftover after stripping the link is the source's contribution, if any.
    private static func detail(of text: String) -> String? {
        let stripped = text
            .replacing(/\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/, with: "")
            .replacing(/https?:\/\/[^\s)>\]]+/, with: "")
        let clean = stripped.trimmingCharacters(
            in: CharacterSet(charactersIn: " \t-—–·:,;"))
        return clean.isEmpty ? nil : clean
    }

    static func links(in text: String) -> [SourceLink] {
        let markdownLink = /\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)/
        var out: [SourceLink] = []
        for match in text.matches(of: markdownLink) {
            out.append(SourceLink(title: String(match.1), url: String(match.2)))
        }
        let consumed = text.replacing(markdownLink, with: " ")
        for match in consumed.matches(of: /https?:\/\/[^\s)>\]]+/) {
            let url = String(match.0)
            out.append(SourceLink(title: URL(string: url)?.host ?? url, url: url))
        }
        return out
    }

    static func splitBlocks(_ text: String) -> [Kind] {
        var out: [Kind] = []
        var para: [String] = []
        var items: [Item] = []
        var quote: [String] = []
        var ordered = false

        func flushPara() {
            let joined = para.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { out.append(.prose(joined)) }
            para = []
        }
        func flushList() {
            if !items.isEmpty { out.append(.list(ordered: ordered, items: items)) }
            items = []
        }
        func flushQuote() {
            let joined = quote.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { out.append(.quote(joined)) }
            quote = []
        }

        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushPara(); flushList(); flushQuote(); continue
            }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushPara(); flushList(); flushQuote()
                out.append(.rule); continue
            }
            if trimmed.hasPrefix(">") {
                flushPara(); flushList()
                quote.append(String(trimmed.dropFirst()
                    .trimmingCharacters(in: .whitespaces)))
                continue
            }
            if !quote.isEmpty { flushQuote() }
            if let h = heading(trimmed) {
                flushPara(); flushList(); out.append(h); continue
            }
            if let (isOrdered, body) = bullet(trimmed) {
                flushPara()
                if !items.isEmpty, ordered != isOrdered { flushList() }
                ordered = isOrdered
                let indent = line.prefix { $0 == " " || $0 == "\t" }.count
                items.append(Item(depth: min(indent / 2, 3), text: body))
                continue
            }
            flushList()
            para.append(trimmed)
        }
        flushPara(); flushList(); flushQuote()
        return out
    }

    private static func heading(_ line: String) -> Kind? {
        var level = 0
        var rest = Substring(line)
        while rest.first == "#", level < 6 {
            level += 1
            rest = rest.dropFirst()
        }
        guard level > 0, rest.first == " " else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : .heading(level: level, text: text)
    }

    private static func bullet(_ line: String) -> (Bool, String)? {
        if let f = line.first, "-*+".contains(f), line.dropFirst().first == " " {
            return (false, String(line.dropFirst(2)))
        }
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty, digits.count <= 3 else { return nil }
        let after = line.dropFirst(digits.count)
        guard let sep = after.first, sep == "." || sep == ")",
              after.dropFirst().first == " " else { return nil }
        return (true, String(after.dropFirst(2)))
    }

    private static func splitTables(_ text: String) -> [Kind] {
        let lines = text.components(separatedBy: "\n")
        var kinds: [Kind] = []
        var prose: [String] = []
        var i = 0

        func flushProse() {
            let body = prose.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty { kinds.append(.prose(body)) }
            prose = []
        }

        while i < lines.count {
            if i + 1 < lines.count, isRow(lines[i]), isSeparator(lines[i + 1]) {
                flushProse()
                let headers = cells(lines[i])
                let width = max(headers.count, 1)
                i += 2
                var rows: [[String]] = []
                while i < lines.count, isRow(lines[i]), !isSeparator(lines[i]) {
                    rows.append(pad(cells(lines[i]), to: width))
                    i += 1
                }
                kinds.append(.table(headers: pad(headers, to: width), rows: rows))
                continue
            }
            prose.append(lines[i])
            i += 1
        }
        flushProse()
        return kinds
    }

    private static func isRow(_ line: String) -> Bool {
        line.contains("|") && !line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func isSeparator(_ line: String) -> Bool {
        let parts = cells(line)
        guard !parts.isEmpty else { return false }
        return parts.allSatisfy { cell in
            let t = cell.filter { !$0.isWhitespace }
            guard t.contains("-") else { return false }
            return t.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func cells(_ line: String) -> [String] {
        var raw = line.trimmingCharacters(in: .whitespaces)
        if raw.hasPrefix("|") { raw.removeFirst() }
        if raw.hasSuffix("|") { raw.removeLast() }
        return raw.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func pad(_ row: [String], to width: Int) -> [String] {
        if row.count >= width { return Array(row.prefix(width)) }
        return row + Array(repeating: "", count: width - row.count)
    }
}
