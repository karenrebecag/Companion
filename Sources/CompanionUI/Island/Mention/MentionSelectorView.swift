import CompanionCore
import SwiftUI

/// The list under the field while `@` is being typed (16m-7). Paints the
/// model; the keys come through the field, which keeps the keyboard.
struct MentionSelectorView: View {
    let model: MentionSelectorModel
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        list
            .padding(MentionMetrics.padding)
            .background(RoundedRectangle(cornerRadius: MentionMetrics.radius).fill(IslandInk.popover))
            .overlay(RoundedRectangle(cornerRadius: MentionMetrics.radius)
                .stroke(IslandInk.hairline, lineWidth: Stroke.hairline))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Localized.string("mention.list"))
    }

    /// Hugs a short list and scrolls past the cap; a greedy ScrollView would
    /// make every list 240 tall.
    @ViewBuilder
    private var list: some View {
        if contentHeight > MentionMetrics.maxHeight {
            ScrollViewReader { proxy in
                ScrollView(.vertical) { rowsView }
                    .scrollIndicators(.never)
                    .frame(height: MentionMetrics.maxHeight)
                    .onChange(of: model.cursor) { _, index in
                        guard let index, model.rows.indices.contains(index) else { return }
                        proxy.scrollTo(model.rows[index].id)
                    }
            }
        } else {
            rowsView
        }
    }

    private var rowsView: some View {
        VStack(spacing: Space.none) {
            ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                MentionRow(
                    row: row, lit: model.cursor == index,
                    accessibility: MentionCopy.accessibility(row, index: index, count: model.rows.count),
                    hint: MentionCopy.hint(canExpand: canExpand(row)),
                    onPick: { model.choose(index) },
                    onHover: { over in if over { model.hover(index) } })
                    .id(row.id)
            }
            if model.suggestsTyping {
                Text(Localized.string("mention.typeToSearch"))
                    .font(GeistFont.uiCaption)
                    .foregroundStyle(IslandInk.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, MentionMetrics.itemPaddingX)
                    .padding(.vertical, MentionMetrics.itemPaddingY)
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { contentHeight = $0 }
    }

    private func canExpand(_ row: MentionSelectorModel.Row) -> Bool {
        if case .candidate(let item) = row { return item.kind == .contact }
        return false
    }
}

private struct MentionRow: View {
    let row: MentionSelectorModel.Row
    let lit: Bool
    let accessibility: String
    let hint: String
    let onPick: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: Space.x2) {
                Image(systemName: symbol)
                    .foregroundStyle(IslandInk.secondary)
                    .frame(width: IslandInk.slotSide)
                    .accessibilityHidden(true)
                Text(row.title)
                    .font(GeistFont.uiLabel)
                    .foregroundStyle(IslandInk.text)
                    .lineLimit(1)
                Spacer(minLength: Space.none)
                if case .channel(_, let channel) = row, let label = channel.label {
                    Text(label).font(GeistFont.uiCaption).foregroundStyle(IslandInk.secondary)
                }
            }
            .padding(.vertical, MentionMetrics.itemPaddingY)
            .padding(.horizontal, MentionMetrics.itemPaddingX)
            .background(RoundedRectangle(cornerRadius: MentionMetrics.itemRadius)
                .fill(lit ? IslandPalette.accent.color.opacity(MentionMetrics.hoverAlpha) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
        .accessibilityLabel(accessibility)
        .accessibilityHint(hint)
        .accessibilityAddTraits(lit ? .isSelected : [])
    }

    private var symbol: String {
        switch row {
        case .channel(_, let channel): channel.kind == .email ? "envelope" : "phone"
        case .nameOnly: "person.crop.circle"
        case .candidate(let item):
            switch item.kind {
            case .contact: "person.crop.circle"
            case .app: "square.grid.2x2"
            case .file: "doc"
            }
        }
    }
}
