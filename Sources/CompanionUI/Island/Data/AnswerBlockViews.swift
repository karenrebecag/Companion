import CompanionCore
import SwiftUI

// Wave 16m-1: the rich answer popup. `AnswerBlocks` (Core) decides WHAT a
// reply holds; this file only paints it, one view per ovx block, with the
// measures pinned in AnswerBlockTheme. Weights ride Geist's available cuts
// (650/620 → the nearest), so only sizes, paddings and alphas are pinned.

/// The popup: a close affordance, then the blocks, scrolling when tall.
struct AnswerPopupView: View {
    let blocks: [AnswerBlock]
    let screenWidth: CGFloat
    let maxHeight: CGFloat
    let onClose: () -> Void
    @State private var contentHeight: CGFloat = 0

    /// Names what it closes: the popup floats apart from the island.
    static var closeLabel: String { Localized.string("island.answer.close") }

    var body: some View {
        AnswerPopup(screenWidth: screenWidth) {
            HStack {
                Spacer(minLength: Space.none)
                CloseButton(variant: .island, label: Self.closeLabel, action: onClose)
            }
            // The popup hugs a short answer; the scroll appears only past
            // the cap. A greedy ScrollView made every popup cap-tall (16m
            // snapshot), and ImageRenderer skips scroll content besides.
            // The branches swap only on the opening frames (blocks are a
            // finished message, so contentHeight settles once), before any
            // fold/copy state exists to lose.
            if contentHeight > maxHeight {
                ScrollView(.vertical) { list }
                    .scrollIndicators(.never)
                    .frame(height: maxHeight, alignment: .top)
            } else {
                // Unmeasured first frame: the clamp keeps an over-tall list
                // from painting past the cap or over-reporting the island's
                // click area before the measure lands (review 16m).
                list
                    .frame(maxHeight: maxHeight, alignment: .top)
                    .clipped()
            }
        }
        .onExitCommand(perform: onClose)
    }

    private var list: some View {
        AnswerBlockList(blocks: blocks)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) {
                contentHeight = $0
            }
    }
}

struct AnswerBlockList: View {
    let blocks: [AnswerBlock]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                AnswerBlockView(block: block)
            }
        }
    }
}

struct AnswerBlockView: View {
    let block: AnswerBlock

    var body: some View {
        switch block {
        case .title(let text):
            Text(AnswerInline.rich(text))
                .font(Fonts.geist(AnswerBlockMetrics.titleSize).weight(.bold))
                .tracking(AnswerBlockMetrics.titleSize * -0.02)
                .foregroundStyle(.white)
                .textSelection(.enabled)
        case .section(let text):
            Text(AnswerInline.rich(text))
                .font(Fonts.geist(AnswerBlockMetrics.sectionSize).weight(.semibold))
                .tracking(AnswerBlockMetrics.sectionSize * -0.01)
                .foregroundStyle(AnswerInk.white(AnswerInk.text))
                .textSelection(.enabled)
        case .eyebrow(let text):
            Text(text.uppercased())
                .font(Fonts.geist(AnswerBlockMetrics.eyebrowSize).weight(.semibold))
                .foregroundStyle(AnswerInk.white(AnswerInk.muted))
                .textSelection(.enabled)
        case .paragraph(let text):
            paragraph(text)
        case .list(let ordered, let items):
            list(ordered: ordered, items: items)
        case .tasks(let lines):
            tasks(lines)
        case .quote(let text):
            quote(text)
        case .callout(let title, let body):
            callout(title: title, body: body)
        case .rule:
            Rectangle().fill(AnswerInk.white(AnswerInk.line)).frame(height: Stroke.hairline)
        case .code(let language, let body):
            AnswerCodeBlock(language: language, body: body)
        case .table(let headers, let rows):
            table(headers: headers, rows: rows)
        case .fileChip(let path):
            fileChip(path)
        case .card(.chart(let chart)):
            IslandChartVisual(block: chart)
        case .card(let payload):
            CardView(card: Card(payload: payload, source: .model))
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(AnswerInline.rich(text))
            .font(Fonts.geist(AnswerBlockMetrics.bodySize))
            .lineSpacing(AnswerBlockMetrics.lineSpacing(
                size: AnswerBlockMetrics.bodySize, leading: AnswerBlockMetrics.bodyLeading))
            .foregroundStyle(AnswerInk.white(AnswerInk.text))
            // Incredible caps prose at a 66-character measure; wider popups
            // keep the column, not the sprawl.
            .frame(maxWidth: AnswerBlockMetrics.bodyMaxWidth, alignment: .leading)
            .textSelection(.enabled)
    }

    private func list(ordered: Bool, items: [MarkdownSplitter.Item]) -> some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
                    Text(Self.marker(ordered: ordered, index: index))
                        .font(Fonts.geist(AnswerBlockMetrics.bodySize))
                        .foregroundStyle(AnswerInk.white(AnswerInk.muted))
                    Text(AnswerInline.rich(item.text))
                        .font(Fonts.geist(AnswerBlockMetrics.bodySize))
                        .lineSpacing(AnswerBlockMetrics.lineSpacing(
                            size: AnswerBlockMetrics.bodySize, leading: AnswerBlockMetrics.listLeading))
                        .foregroundStyle(AnswerInk.white(AnswerInk.text))
                        .textSelection(.enabled)
                }
                .padding(.leading, CGFloat(item.depth) * Space.x4)
            }
        }
    }

    private func tasks(_ lines: [TaskLine]) -> some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
                    Image(systemName: line.done ? "checkmark.square.fill" : "square")
                        .font(Fonts.geist(AnswerBlockMetrics.bodySize - 1))
                        .foregroundStyle(AnswerInk.white(AnswerInk.muted))
                    Text(AnswerInline.rich(line.text))
                        .font(Fonts.geist(AnswerBlockMetrics.bodySize))
                        .foregroundStyle(AnswerInk.white(
                            line.done ? AnswerInk.secondary : AnswerInk.text))
                        .strikethrough(line.done, color: AnswerInk.white(AnswerInk.muted))
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func quote(_ text: String) -> some View {
        Text(AnswerInline.rich(text))
            .font(Fonts.geist(AnswerBlockMetrics.quoteSize))
            .lineSpacing(AnswerBlockMetrics.lineSpacing(
                size: AnswerBlockMetrics.quoteSize, leading: AnswerBlockMetrics.quoteLeading))
            .foregroundStyle(AnswerInk.white(AnswerInk.secondary))
            .padding(.vertical, AnswerBlockMetrics.quotePaddingY)
            .padding(.horizontal, AnswerBlockMetrics.quotePaddingX)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: AnswerBlockMetrics.innerRadius)
                .fill(AnswerInk.white(AnswerInk.fill)))
            .textSelection(.enabled)
    }

    private func callout(title: String, body: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AnswerBlockMetrics.calloutGap) {
            Image(systemName: "info.circle")
                .font(Fonts.geist(AnswerBlockMetrics.bodySize))
                .foregroundStyle(AnswerInk.accent.color)
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(title)
                    .font(Fonts.geist(AnswerBlockMetrics.bodySize).weight(.semibold))
                    .foregroundStyle(AnswerInk.white(AnswerInk.text))
                Text(AnswerInline.rich(body))
                    .font(Fonts.geist(AnswerBlockMetrics.bodySize))
                    .foregroundStyle(AnswerInk.white(AnswerInk.secondary))
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, AnswerBlockMetrics.calloutPaddingY)
        .padding(.horizontal, AnswerBlockMetrics.calloutPaddingX)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AnswerBlockMetrics.innerRadius)
            .fill(AnswerInk.accent.color.opacity(AnswerBlockMetrics.calloutTone)))
        .overlay(RoundedRectangle(cornerRadius: AnswerBlockMetrics.innerRadius)
            .strokeBorder(AnswerInk.accent.color.opacity(AnswerBlockMetrics.calloutBorder),
                          lineWidth: Stroke.hairline))
    }

    private func table(headers: [String], rows: [[String]]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: Space.none, verticalSpacing: Space.none) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    cell(header, weight: .semibold, ink: AnswerInk.secondary)
                }
            }
            Divider().overlay(AnswerInk.white(AnswerInk.lineStrong)).gridCellUnsizedAxes(.vertical)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, value in
                        cell(value, weight: .regular, ink: AnswerInk.text)
                    }
                }
                if index < rows.count - 1 {
                    Divider().overlay(AnswerInk.white(AnswerInk.line)).gridCellUnsizedAxes(.vertical)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: AnswerBlockMetrics.innerRadius)
            .fill(AnswerInk.white(AnswerInk.fill)))
        .overlay(RoundedRectangle(cornerRadius: AnswerBlockMetrics.innerRadius)
            .strokeBorder(AnswerInk.white(AnswerInk.line), lineWidth: Stroke.hairline))
        .clipShape(RoundedRectangle(cornerRadius: AnswerBlockMetrics.innerRadius))
    }

    private func cell(_ text: String, weight: Font.Weight, ink: Double) -> some View {
        Text(AnswerInline.rich(text))
            .font(Fonts.geist(AnswerBlockMetrics.tableSize).weight(weight))
            .lineSpacing(AnswerBlockMetrics.lineSpacing(
                size: AnswerBlockMetrics.tableSize, leading: AnswerBlockMetrics.tableLeading))
            .foregroundStyle(AnswerInk.white(ink))
            .padding(.vertical, Space.x2)
            .padding(.horizontal, Space.x3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
    }

    /// Layout glyphs, not copy: the bullet and the number never localize.
    private static func marker(ordered: Bool, index: Int) -> String {
        ordered ? "\(index + 1)." : "•"
    }

    private func fileChip(_ path: String) -> some View {
        Text(path)
            .font(Fonts.mono(AnswerBlockMetrics.chipSize))
            .foregroundStyle(AnswerInk.white(AnswerInk.secondary))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.leading, AnswerBlockMetrics.chipPaddingLeading)
            .padding(.trailing, AnswerBlockMetrics.chipPaddingTrailing)
            .padding(.vertical, AnswerBlockMetrics.chipPaddingY)
            .background(RoundedRectangle(cornerRadius: AnswerBlockMetrics.chipRadius)
                .fill(AnswerInk.white(AnswerInk.fill)))
    }
}

/// The code well: a 26-pt bar with the language, copy and fold, then the
/// highlighted body, sitting deeper than the popup around it.
struct AnswerCodeBlock: View {
    let language: String
    let body_: String
    @State private var folded = false
    @State private var copied = false

    init(language: String, body: String) {
        self.language = language
        body_ = body
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.none) {
            HStack(spacing: Space.x2) {
                Text(Self.tag(for: language))
                    .font(Fonts.mono(AnswerBlockMetrics.eyebrowSize))
                    .foregroundStyle(AnswerInk.white(AnswerInk.muted))
                Spacer(minLength: Space.none)
                Button(action: copy) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(Fonts.geist(TypeSize.micro))
                        .foregroundStyle(AnswerInk.white(AnswerInk.secondary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Localized.string("island.answer.copy"))
                Button(action: { folded.toggle() }) {
                    Image(systemName: folded ? "chevron.down" : "chevron.up")
                        .font(Fonts.geist(TypeSize.micro))
                        .foregroundStyle(AnswerInk.white(AnswerInk.secondary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Localized.string("island.answer.fold"))
            }
            .padding(.horizontal, Space.x3)
            .frame(height: AnswerBlockMetrics.codeBar)
            if !folded {
                ScrollView(.horizontal) {
                    Text(SyntaxHighlighter.attributed(body_, language: language))
                        .font(Fonts.mono(AnswerBlockMetrics.inlineCodeSize))
                        .textSelection(.enabled)
                        .padding(.horizontal, Space.x3)
                        .padding(.bottom, Space.x2)
                }
                .scrollIndicators(.never)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AnswerBlockMetrics.innerRadius)
            .fill(AnswerInk.codeWell))
        .overlay(RoundedRectangle(cornerRadius: AnswerBlockMetrics.innerRadius)
            .strokeBorder(AnswerInk.white(AnswerInk.line), lineWidth: Stroke.hairline))
    }

    /// A wire tag, not copy: fence languages never localize.
    private static func tag(for language: String) -> String {
        language.isEmpty ? "text" : language
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(body_, forType: .string)
        copied = true
        Task { @MainActor in
            do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
            copied = false
        }
    }
}

/// Inline markdown with the popup's own touches: code runs read as chips
/// (mono over a quiet fill) and links take the ovx accent. The base parse —
/// including the anti-phishing link stripping — stays MarkdownView's.
enum AnswerInline {
    static func rich(_ text: String) -> AttributedString {
        var parsed = MarkdownView.inline(text)
        let codeRuns = parsed.runs.compactMap { run -> Range<AttributedString.Index>? in
            run.inlinePresentationIntent?.contains(.code) == true ? run.range : nil
        }
        for range in codeRuns {
            parsed[range].font = Fonts.mono(AnswerBlockMetrics.inlineCodeSize)
            parsed[range].backgroundColor = .white.opacity(AnswerInk.fill)
        }
        let linkRuns = parsed.runs.compactMap { $0.link == nil ? nil : $0.range }
        for range in linkRuns {
            parsed[range].foregroundColor = AnswerInk.accent.color
        }
        return parsed
    }
}
