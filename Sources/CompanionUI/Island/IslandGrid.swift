import SwiftUI

/// Arc's grid on the island (the agent run's `24px minmax(0, 1fr)` rail and
/// now-playing's one grid for every state): a lead column for the mark of a
/// row (the orb, a step's node, a notice's icon, a receipt's check), the
/// content, and a trail for counters and controls. Every state uses the same
/// columns, so text always starts at the same x and the orb sits in the same
/// place whether the island is a bar or open.
package enum IslandGrid {
    package static let lead: CGFloat = 32
    package static let gap: CGFloat = Space.x3
    /// Where the content column starts inside the shell.
    package static let contentInset: CGFloat = lead + gap
    /// Rows of one group sit this far apart; groups, `groupGap`.
    package static let rowGap: CGFloat = Space.x1
    package static let groupGap: CGFloat = Space.x3
    package static let minRadius: CGFloat = 6
    /// The open island's inner width: what every row and nested piece fills.
    package static let openColumn: CGFloat = IslandChrome.cardWidth - IslandChrome.shellMargin * 2

    /// Arc's concentric corners: inner = outer - padding, clamped small.
    package static func innerRadius(outer: CGFloat, padding: CGFloat) -> CGFloat {
        max(minRadius, outer - padding)
    }

    /// Anything nested in the open island (a field, a result, an attachment).
    package static var nestedRadius: CGFloat {
        innerRadius(outer: NotchShape.openRadius, padding: IslandChrome.shellMargin)
    }
}

/// One row on the island's grid.
struct IslandGridRow<Lead: View, Content: View, Trail: View>: View {
    var alignment: VerticalAlignment = .center
    @ViewBuilder var lead: () -> Lead
    @ViewBuilder var content: () -> Content
    @ViewBuilder var trail: () -> Trail

    var body: some View {
        HStack(alignment: alignment, spacing: IslandGrid.gap) {
            // A zero-height spacer holds the column even when the lead is
            // empty: an HStack drops an EmptyView, frame and all.
            ZStack {
                Color.clear.frame(height: Space.none)
                lead()
            }
            .frame(width: IslandGrid.lead)
            content().frame(maxWidth: .infinity, alignment: .leading)
            trail()
        }
    }
}

extension IslandGridRow where Trail == EmptyView {
    init(alignment: VerticalAlignment = .center, @ViewBuilder lead: @escaping () -> Lead,
         @ViewBuilder content: @escaping () -> Content) {
        self.init(alignment: alignment, lead: lead, content: content, trail: { EmptyView() })
    }
}

extension View {
    /// Puts a block in the content column: under the row's text, not under its mark.
    func islandContentColumn() -> some View {
        padding(.leading, IslandGrid.contentInset)
    }
}
