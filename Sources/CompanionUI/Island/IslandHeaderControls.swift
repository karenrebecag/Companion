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
        IconButton(symbol, label: Localized.string(label), size: .island, tone: .island,
                   active: popover == kind) {
            popover = IslandPopoverToggle.next(current: popover, tapped: kind)
        }
        .portal(popover == kind ? .popover(kind) : nil)
    }
}
