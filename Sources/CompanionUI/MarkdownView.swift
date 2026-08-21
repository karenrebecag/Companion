import CompanionCore
import SwiftUI

public struct MarkdownView: View {
    public let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Space.s8) {
            ForEach(MarkdownSplitter.split(text), id: \.id) { part in
                block(part.kind)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func block(_ kind: MarkdownSplitter.Kind) -> some View {
        switch kind {
        case .prose(let text):
            Text(text)
                .font(Tokens.Typography.body)
                .foregroundStyle(Tokens.Color.fg)
                .textSelection(.enabled)
        case .heading(let level, let text):
            Text(text)
                .font(level <= 2 ? Tokens.Typography.title : Tokens.Typography.body)
                .foregroundStyle(Tokens.Color.fg)
                .textSelection(.enabled)
        case .list(let ordered, let items):
            VStack(alignment: .leading, spacing: Tokens.Space.s4) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    Text(listLine(ordered: ordered, index: index, item: item))
                        .font(Tokens.Typography.body)
                        .foregroundStyle(Tokens.Color.fg)
                        .textSelection(.enabled)
                }
            }
        case .quote(let text):
            HStack(alignment: .top, spacing: Tokens.Space.s8) {
                Rectangle()
                    .fill(Tokens.Color.border)
                    .frame(width: 2)
                Text(text)
                    .font(Tokens.Typography.body)
                    .foregroundStyle(Tokens.Color.muted)
                    .textSelection(.enabled)
            }
        case .rule:
            Rectangle()
                .fill(Tokens.Color.border)
                .frame(height: 1)
                .padding(.vertical, Tokens.Space.s8)
        case .code(_, let body):
            // companion:* stays code until Wave 5 cards; broken JSON must remain visible.
            Text(body)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Tokens.Color.fg)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Tokens.Space.s8)
                .background(Tokens.Color.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Tokens.Color.border, lineWidth: 1)
                )
        case .table(let headers, let rows):
            Text(tableText(headers: headers, rows: rows))
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Tokens.Color.fg)
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
}
