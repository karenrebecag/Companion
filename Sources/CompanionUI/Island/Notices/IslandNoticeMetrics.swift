import SwiftUI

// Wave 16m-4: the notice grids as Incredible's overlay CSS measures them
// (docs/research/incredible-isla-componentes.md §5). Pinned in
// Island16m4Tests.
//
// Where the research gives one measure for a family, the others inherit it:
// every notice is padding 18 × 20; the diagnostic grid reuses the limit's
// gaps; the update grid reuses them too. The permission notice has no row of
// its own in the CSS, so it sits on the consent grid (340-440, gap 10): both
// ask the user to grant something.

/// Nonisolated: the width `Layout` below reads it off the main actor.
public nonisolated enum IslandNoticeMetrics {
    /// Límite de uso: 380 wide, a 38 icon column then the rest, gap 10 × 12
    /// (CSS `gap: row column`).
    public static let limitWidth: CGFloat = 380
    public static let limitGutter: CGFloat = 38
    public static let limitRowGap: CGFloat = 10
    public static let limitColumnGap: CGFloat = 12
    public static let paddingY: CGFloat = 18
    public static let paddingX: CGFloat = 20

    /// Actualización disponible: 522 wide, 30 + rest + actions.
    public static let updateWidth: CGFloat = 522
    public static let updateGutter: CGFloat = 30

    /// Consentimiento: 340-440, gap 10.
    public static let consentMinWidth: CGFloat = 340
    public static let consentMaxWidth: CGFloat = 440
    public static let consentGap: CGFloat = 10

    /// Diagnóstico: min(420, 86 %), a 38 icon column then the rest.
    public static let diagnosticWidth: CGFloat = 420
    public static let diagnosticFraction: CGFloat = 0.86
    public static let diagnosticGutter: CGFloat = 38

    /// The card's width in the room it is given: the measured width, never
    /// more than the room. The update card asks for the wide shape
    /// (`IslandState.Size.wideCard`, 16m-6) so its 522 fits; in the plain 492
    /// shape it would still be capped at 460.
    static func width(_ grid: IslandNotice.Grid, available: CGFloat, ideal: CGFloat? = nil) -> CGFloat {
        switch grid {
        case .limit: min(limitWidth, available)
        case .update: min(updateWidth, available)
        // 340-440 is a clamp on what the words ask for, capped by the room.
        case .permission: min(available, min(max(ideal ?? consentMaxWidth, consentMinWidth), consentMaxWidth))
        case .diagnostic: min(diagnosticWidth, (available * diagnosticFraction).rounded(.down))
        }
    }

    /// The icon column: the tile's side.
    static func gutter(_ grid: IslandNotice.Grid) -> CGFloat {
        switch grid {
        case .limit: limitGutter
        case .update, .permission: updateGutter
        case .diagnostic: diagnosticGutter
        }
    }

    /// A card asked for its ideal width (no proposal) takes the widest one.
    static let unbounded: CGFloat = 10_000
}

/// The offer the island makes about a new release: only while one exists and
/// this session has not waved it away. Dismissing a version never silences a
/// newer one.
enum IslandUpdate {
    static func visibleTag(available: UpdateState.Available?, dismissed: String?) -> String? {
        guard let tag = available?.tag, tag != dismissed else { return nil }
        return tag
    }
}

/// Gives a notice card its grid's width inside whatever room the island
/// leaves, so the 86 % of the diagnostic card is 86 % of the real room.
struct IslandNoticeWidth: Layout {
    let grid: IslandNotice.Grid

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // A zero proposal is a measuring pass with no room: nothing to lay out.
        guard let card = subviews.first, proposal.width != 0 else { return .zero }
        let ideal = grid == .permission ? card.sizeThatFits(.unspecified).width : nil
        let width = IslandNoticeMetrics.width(
            grid, available: proposal.width ?? IslandNoticeMetrics.unbounded, ideal: ideal)
        let height = card.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}
