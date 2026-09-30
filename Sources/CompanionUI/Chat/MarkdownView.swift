import CompanionCore
import SwiftUI

package struct MarkdownView: View {
    package let text: String

    package init(text: String) {
        self.text = text
    }

    package var body: some View {
        // Sources leave the prose and become links: extractSources returns the
        // remaining parts precisely so the section is not rendered twice.
        let split = MarkdownSplitter.extractSources(MarkdownSplitter.split(text))
        VStack(alignment: .leading, spacing: Space.x2) {
            ForEach(split.rest, id: \.id) { part in
                block(part.kind)
            }
            if !split.web.isEmpty {
                SourcesCard(webSources: split.web, fileSources: [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func block(_ kind: MarkdownSplitter.Kind) -> some View {
        switch kind {
        case .prose(let text):
            Text(Self.inline(text))
                .font(Font.uiBody)
                .foregroundStyle(Semantic.foreground)
                .textSelection(.enabled)
        case .heading(let level, let text):
            Text(text)
                .font(level <= 2 ? Font.uiTitle : Font.uiBody)
                .foregroundStyle(Semantic.foreground)
                .textSelection(.enabled)
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: Space.x1) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Text(Self.inline(listLine(ordered: ordered, index: index, item: item)))
                        .font(Font.uiBody)
                        .foregroundStyle(Semantic.foreground)
                        .textSelection(.enabled)
                }
            }
        case .quote(let text):
            HStack(alignment: .top, spacing: Space.x2) {
                Rectangle()
                    .fill(Semantic.border)
                    .frame(width: 2)
                Text(Self.inline(text))
                    .font(Font.uiBody)
                    .foregroundStyle(Semantic.mutedForeground)
                    .textSelection(.enabled)
            }
        case .rule:
            Rectangle()
                .fill(Semantic.border)
                .frame(height: 1)
                .padding(.vertical, Space.x2)
        case .code(let language, let body):
            // Companion card blocks: try to render as rich cards, degrade to code on JSON error.
            if language == CompanionBlocks.locationsLanguage {
                if let locations = CompanionBlocks.locations(body) {
                    // From a fence: the model authored it, and the card says so.
                    CardView(card: Card(
                        payload: .locations(locations), source: .model))
                } else {
                    codeBlock(body, language: language)
                }
            } else if language == CompanionBlocks.galleryLanguage {
                if let gallery = CompanionBlocks.gallery(body) {
                    CardView(card: Card(
                        payload: .gallery(gallery), source: .model))
                } else {
                    codeBlock(body, language: language)
                }
            } else if language == CompanionBlocks.choiceLanguage, let choice = CompanionBlocks.choice(body) {
                // A saved transcript has no reply channel: the question and
                // its options read as text; answering lives in the island.
                choiceText(choice)
            } else if let payload = Self.dataCard(language: language, body: body) {
                CardView(card: Card(payload: payload, source: .model))
            } else {
                codeBlock(body, language: language)
            }
        case .table(let headers, let rows):
            Text(tableText(headers: headers, rows: rows))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Semantic.foreground)
                .textSelection(.enabled)
        }
    }

    /// Wave 20: the data fences. Nil keeps a broken one visible as code.
    nonisolated static func dataCard(language: String, body: String) -> CardPayload? {
        switch language {
        case CompanionBlocks.statsLanguage: CompanionBlocks.stats(body).map { .stats($0) }
        case CompanionBlocks.tableLanguage: CompanionBlocks.table(body).map { .table($0) }
        case CompanionBlocks.chartLanguage: CompanionBlocks.chart(body)
        default: nil
        }
    }

    /// Bold, italics, code and links drawn, not shown as marks. Only web
    /// links stay clickable: the model writes them, and a file or app URL
    /// from a reply must not open with one click.
    nonisolated static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        guard var parsed = try? AttributedString(markdown: text, options: options) else {
            return AttributedString(text)
        }
        // Ranges first: writing while walking the runs invalidates them.
        let unsafe = parsed.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard let link = run.link else { return nil }
            let web = ["http", "https"].contains(link.scheme?.lowercased() ?? "")
            let label = String(parsed[run.range].characters)
            return web && !disguises(label, link) ? nil : run.range
        }
        for range in unsafe { parsed[range].link = nil }
        return parsed
    }

    /// A label that reads as one site while the link goes to another is a
    /// phishing shape (security review 16j-2): it stays text.
    nonisolated static func disguises(_ label: String, _ link: URL) -> Bool {
        guard let shown = siteName(label) else { return false }
        let target = siteName(link.host ?? "") ?? ""
        return shown != target && !target.hasSuffix("." + shown)
    }

    nonisolated private static func siteName(_ text: String) -> String? {
        var host = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !host.isEmpty, !host.contains(where: \.isWhitespace) else { return nil }
        if let range = host.range(of: "://") { host = String(host[range.upperBound...]) }
        host = String(host.prefix { $0 != "/" && $0 != "?" && $0 != "#" })
        guard host.contains(".") else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private func listLine(
        ordered: Bool, index: Int, item: MarkdownSplitter.Item
    ) -> String {
        let indent = String(repeating: "  ", count: item.depth)
        let mark = ordered ? "\(index + 1)." : "•"
        return "\(indent)\(mark) \(item.text)"
    }

    private func tableText(headers: [String], rows: [[String]]) -> String {
        let head = headers.joined(separator: " | ")
        let body = rows.map { $0.joined(separator: " | ") }.joined(separator: "\n")
        return body.isEmpty ? head : head + "\n" + body
    }

    /// Layout glyphs, not copy: the number and the dash never localize.
    nonisolated static func choiceLines(_ choice: ChoiceBlock) -> [String] {
        [choice.question] + choice.options.enumerated().map { index, option in
            let line = "\(index + 1). \(option.label)"
            return option.detail.map { line + " — " + $0 } ?? line
        }
    }

    private func choiceText(_ choice: ChoiceBlock) -> some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            ForEach(Array(Self.choiceLines(choice).enumerated()), id: \.offset) { index, line in
                Text(line).fontWeight(index == 0 ? .semibold : .regular)
            }
        }
        .font(Font.uiBody)
        .foregroundStyle(Semantic.foreground)
        .textSelection(.enabled)
    }

    private func codeBlock(_ body: String, language: String) -> some View {
        Text(SyntaxHighlighter.attributed(body, language: language))
            .font(Font.uiCode)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Space.x2)
            .background(Semantic.surface)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md)
                    .stroke(Semantic.border, lineWidth: Stroke.hairline)
            )
    }
}
