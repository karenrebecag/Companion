import CompanionCore
import SwiftUI

/// Heading, paragraph, list, key/value, quote and divider. The chat draws
/// them with its own markdown view and the island with the answer popup's
/// blocks, so a present call reads like the text around it in both places.
struct PresentProse: View {
    let block: PresentBlock
    let compact: Bool

    var body: some View {
        switch block {
        case .keyvalue(let pairs):
            PresentKeyValueView(pairs: pairs)
        case .callout(let note):
            PresentNotice(note: note)
        case .quote(let text, let source):
            VStack(alignment: .leading, spacing: Space.x1) {
                rendered(.quote(text: text, source: nil))
                if let source, !source.isEmpty {
                    Text(source)
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                        .padding(.leading, Space.x3)
                }
            }
        default:
            rendered(block)
        }
    }

    @ViewBuilder
    private func rendered(_ block: PresentBlock) -> some View {
        if compact {
            if let answer = Self.answerBlock(block) { AnswerBlockView(block: answer) }
        } else if let kind = Self.markdownKind(block) {
            MarkdownView.part(kind)
        }
    }

    static func answerBlock(_ block: PresentBlock) -> AnswerBlock? {
        switch block {
        case .heading(let level, let text):
            switch level {
            case 1: .title(text)
            case 2: .section(text)
            default: .subheading(text)
            }
        case .paragraph(let text): .paragraph(text)
        case .list(let ordered, let items):
            .list(ordered: ordered, items: items.map { MarkdownSplitter.Item(depth: 0, text: $0) })
        case .quote(let text, _): .quote(text)
        case .divider: .rule
        default: nil
        }
    }

    static func markdownKind(_ block: PresentBlock) -> MarkdownSplitter.Kind? {
        switch block {
        case .heading(let level, let text): .heading(level: level, text: text)
        case .paragraph(let text): .prose(text)
        case .list(let ordered, let items):
            .list(ordered: ordered, items: items.map { MarkdownSplitter.Item(depth: 0, text: $0) })
        case .quote(let text, _): .quote(text)
        case .divider: .rule
        default: nil
        }
    }
}

/// Name and value pairs: the name quiet, the value in the body ink.
struct PresentKeyValueView: View {
    let pairs: [PresentKeyValue]

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: Space.x4, verticalSpacing: Space.x1_5) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                GridRow {
                    Text(pair.key)
                        .font(.uiBody)
                        .foregroundStyle(Semantic.mutedForeground)
                        .gridColumnAlignment(.leading)
                    Text(MarkdownView.inline(pair.value))
                        .font(.uiBody)
                        .foregroundStyle(Semantic.foreground)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A status banner. Tone is color and icon together, so the text never has to
/// carry the meaning alone.
struct PresentNotice: View {
    let note: PresentNote

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.x3) {
            Image(systemName: Self.symbol(note.tone))
                .font(.uiBody)
                .foregroundStyle(Self.ink(note.tone))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.x1) {
                if let title = note.title, !title.isEmpty {
                    Text(title)
                        .font(.uiLabel)
                        .fontWeight(.medium)
                        .foregroundStyle(Semantic.foreground)
                }
                Text(MarkdownView.inline(note.text))
                    .font(.uiBody)
                    .foregroundStyle(Semantic.mutedForeground)
                    .textSelection(.enabled)
            }
        }
        .padding(Space.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.bubble).fill(Self.wash(note.tone)))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.bubble)
                .stroke(Semantic.border, lineWidth: Stroke.hairline))
        .accessibilityElement(children: .combine)
    }

    static func symbol(_ tone: PresentTone) -> String {
        switch tone {
        case .neutral: "circle.fill"
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        }
    }

    static func ink(_ tone: PresentTone) -> Color {
        switch tone {
        case .neutral: Semantic.mutedForeground
        case .info: Semantic.link
        case .success: Semantic.success
        case .warning: Semantic.warning
        case .danger: Semantic.danger
        }
    }

    static func wash(_ tone: PresentTone) -> Color {
        switch tone {
        case .neutral: Semantic.hoverSubtle
        case .info: Semantic.linkMuted
        case .success: Semantic.successMuted
        case .warning: Semantic.warningMuted
        case .danger: Semantic.dangerMuted
        }
    }
}
