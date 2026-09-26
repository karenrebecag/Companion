import SwiftUI

/// Volume and the menu as bare icons in the notch band, top left, where
/// Incredible puts its volume control.
struct IslandHeaderControls: View {
    @Binding var popover: IslandPopoverKind?

    var body: some View {
        HStack(spacing: Space.x1) {
            icon("speaker.wave.2", label: "island.tip.volume", opens: .volume)
            icon("ellipsis", label: "island.menu", opens: .menu)
        }
    }

    private func icon(_ symbol: String, label: String, opens kind: IslandPopoverKind) -> some View {
        IslandHeaderIcon(symbol: symbol, label: Localized.string(label), active: popover == kind) {
            popover = IslandPopoverToggle.next(current: popover, tapped: kind)
        }
        .portal(popover == kind ? .popover(kind) : nil)
    }
}

private struct IslandHeaderIcon: View {
    let symbol: String
    let label: String
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: TypeSize.sectionTitle, weight: .regular))
                .foregroundStyle(active || hovering ? IslandInk.text : IslandInk.secondary)
                .frame(width: IslandFieldMetrics.tool, height: IslandFieldMetrics.tool)
                .background(Circle().fill(active ? IslandInk.chipPressed : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .islandTooltip(label)
        .accessibilityLabel(label)
    }
}
