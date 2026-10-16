import CompanionCore
import SwiftUI

/// The reply's own structure painted as a document: paragraphs, bullets,
/// a table, in the measure and rhythm of the result card. What the popup
/// paints with its smaller step goes through `AnswerBlockView`; only the
/// blocks whose size or spacing the document sets differently live here.
struct IslandDocProse: View {
    let blocks: [AnswerBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.none) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                if index > 0 {
                    Color.clear.frame(height: Self.gap(between: blocks[index - 1], and: block))
                }
                view(for: block)
                    .modifier(DocFadeIn(index: index))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// CSS margins collapse: the space between two blocks is the larger of
    /// what the first leaves after it and the second asks before it.
    static func gap(between above: AnswerBlock, and below: AnswerBlock) -> CGFloat {
        max(margins(above).after, margins(below).before)
    }

    private static func margins(_ block: AnswerBlock) -> (before: CGFloat, after: CGFloat) {
        switch block {
        case .paragraph: (Space.none, DocCardMetrics.paragraphGap)
        case .list, .tasks: (DocCardMetrics.listGapBefore, DocCardMetrics.listGapAfter)
        case .table: (DocCardMetrics.tableGapBefore, DocCardMetrics.tableGapAfter)
        case .section: (DocCardMetrics.headingGapBefore, DocCardMetrics.headingGapAfter)
        case .subheading: (DocCardMetrics.headingGapBefore, DocCardMetrics.headingGapAfter)
        case .title: (Space.none, DocCardMetrics.headingGapAfter)
        default: (DocCardMetrics.listGapBefore, DocCardMetrics.tableGapAfter)
        }
    }

    @ViewBuilder
    private func view(for block: AnswerBlock) -> some View {
        switch block {
        case .paragraph(let text): paragraph(text)
        case .list(let ordered, let items): list(ordered: ordered, items: items)
        case .table(let headers, let rows): table(headers: headers, rows: rows)
        case .section(let text): heading(text, size: DocCardMetrics.headingSize)
        case .title(let text): heading(text, size: DocCardMetrics.titleSize)
        case .subheading(let text): heading(text, size: DocCardMetrics.subheadingSize)
        default: AnswerBlockView(block: block)
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(AnswerInline.rich(text))
            .font(Fonts.geist(DocCardMetrics.proseSize))
            .foregroundStyle(Color.white.opacity(DocCardInk.prose))
            .docLineBox(size: DocCardMetrics.proseSize, leading: DocCardMetrics.proseLeading)
            .frame(maxWidth: DocCardMetrics.proseMeasure, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func heading(_ text: String, size: CGFloat) -> some View {
        Text(AnswerInline.rich(text))
            .font(Fonts.geist(size).weight(AnswerType.medium))
            .tracking(size * DocCardMetrics.titleTracking)
            .foregroundStyle(Color.white.opacity(DocCardInk.title))
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .textSelection(.enabled)
    }

    private func list(ordered: Bool, items: [MarkdownSplitter.Item]) -> some View {
        VStack(alignment: .leading, spacing: DocCardMetrics.listItemGap) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: Space.none) {
                    marker(ordered: ordered, index: index)
                        .frame(width: DocCardMetrics.listIndent, alignment: .leading)
                    paragraph(item.text)
                }
                .padding(.leading, CGFloat(item.depth) * DocCardMetrics.listIndent)
            }
        }
        .frame(maxWidth: DocCardMetrics.proseMeasure, alignment: .leading)
    }

    @ViewBuilder
    private func marker(ordered: Bool, index: Int) -> some View {
        if ordered {
            Text("\(index + 1).") // token-exempt: list number, not copy
                .font(Fonts.geist(DocCardMetrics.proseSize).monospacedDigit())
                .foregroundStyle(Color.white.opacity(DocCardInk.bullet))
        } else {
            Circle().fill(Color.white.opacity(DocCardInk.bullet))
                .frame(width: DocCardMetrics.bulletSize, height: DocCardMetrics.bulletSize)
                .padding(.leading, DocCardMetrics.bulletInset)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] + DocCardMetrics.bulletSize - DocCardMetrics.bulletDrop }
        }
    }

    private func table(headers: [String], rows: [[String]]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Space.none, verticalSpacing: Space.none) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    cell(header, size: DocCardMetrics.tableHeadSize, weight: AnswerType.medium, ink: DocCardInk.tableHead)
                }
            }
            .background(Color.white.opacity(DocCardInk.tableHeadFill))
            Divider().overlay(Color.white.opacity(DocCardInk.lineStrong)).gridCellUnsizedAxes(.vertical)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                        cell(value, size: DocCardMetrics.tableSize, weight: .regular, ink: DocCardInk.tableCell)
                    }
                }
                if index < rows.count - 1 {
                    Divider().overlay(Color.white.opacity(DocCardInk.line)).gridCellUnsizedAxes(.vertical)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DocCardMetrics.tableRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: DocCardMetrics.tableRadius, style: .continuous)
            .strokeBorder(Color.white.opacity(DocCardInk.line), lineWidth: Stroke.hairline))
    }

    private func cell(_ text: String, size: CGFloat, weight: Font.Weight, ink: Double) -> some View {
        Text(AnswerInline.rich(text))
            .font(Fonts.geist(size).weight(weight))
            .foregroundStyle(Color.white.opacity(ink))
            .docLineBox(size: size, leading: DocCardMetrics.tableLeading)
            .padding(.vertical, DocCardMetrics.tablePadY)
            .padding(.horizontal, DocCardMetrics.tablePadX)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }
}
