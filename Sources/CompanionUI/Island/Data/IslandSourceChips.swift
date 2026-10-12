import CompanionUIPro
import SwiftUI

/// A reply's sources as the chips the result card shows, for the places that
/// have no card around them (the thread). Same labels, same web-only opening.
struct IslandSourceChips: View {
    let links: IslandResultCardModel.Links
    let onOpen: (URL) -> Void

    var body: some View {
        if !links.chips.isEmpty {
            WrappingRow(spacing: Space.x2) {
                ForEach(links.chips) { chip in
                    if let url = links.urls[chip.id] {
                        Button { onOpen(url) } label: { label(chip) }
                            .buttonStyle(.plain)
                            .accessibilityHint(url.absoluteString)
                    } else {
                        label(chip)
                    }
                }
            }
        }
    }

    private func label(_ chip: AIResultLink) -> some View {
        HStack(spacing: Space.x1) {
            Image(systemName: chip.kind == .app ? "app" : "doc.text").imageScale(.small).foregroundStyle(ArcTone.textMuted.color)
            Text(chip.label).lineLimit(1).truncationMode(.middle)
        }
        .font(GeistFont.uiCaption)
        .foregroundStyle(ArcTone.textSecondary.color)
        .padding(.horizontal, Space.x2 + 2)
        .frame(height: 28)
        .background(Capsule().fill(ArcTone.surfaceMuted.color))
        .contentShape(Capsule())
    }
}
