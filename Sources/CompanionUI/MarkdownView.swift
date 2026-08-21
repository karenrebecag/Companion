import CompanionCore
import SwiftUI

public struct MarkdownView: View {
    public let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
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
            Text(text)
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
                    Text(listLine(ordered: ordered, index: index, item: item))
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
                Text(text)
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
                    MapCard(block: locations)
                } else {
                    codeBlock(body, language: language)
                }
            } else if language == CompanionBlocks.galleryLanguage {
                if let gallery = CompanionBlocks.gallery(body) {
                    GalleryCard(block: gallery)
                } else {
                    codeBlock(body, language: language)
                }
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
