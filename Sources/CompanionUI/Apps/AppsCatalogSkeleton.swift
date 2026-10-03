import CompanionCore
import SwiftUI

/// Incredible 0.2.36's `connectors-skeleton` (local reference): what the
/// Apps page shows while the first catalog page is on its way. Its cards are
/// the connector card's silhouette, not AppCard's, because that is what
/// Incredible draws.
package enum AppsSkeletonMetrics {
    package static let cards = 8
    package static let columns = 2
    package static let gridTop: CGFloat = Space.x1
    package static let cardPadding: CGFloat = Space.x6
    package static let cardRadius: CGFloat = Radius.card
    package static let cardGap: CGFloat = Space.x4
    package static let icon: CGFloat = 52
    package static let iconRadius: CGFloat = Radius.xl
    /// Tailwind's plain `rounded` resolves to Incredible's --radius (10).
    package static let lineRadius: CGFloat = Radius.chip
    package static let titleHeight: CGFloat = Space.x3_5
    package static let titleWidth: CGFloat = 144
    package static let lineHeight: CGFloat = Space.x2_5
    package static let lineWidth: CGFloat = 256
    package static let shortLineWidth: CGFloat = 160
    package static let titleToLine: CGFloat = Space.x2_5
    package static let lineToLine: CGFloat = Space.x1_5
}

/// What the page's body shows under the search field. Pure so the
/// spinner-to-skeleton swap is checked without rendering.
package enum AppsContentKind: Equatable {
    case setup, skeleton, catalog
    case failed(AppsFailure)

    package static func of(phase: AppsModel.Phase, hasApps: Bool, editing: Bool) -> AppsContentKind {
        if editing { return .setup }
        switch phase {
        case .setup: return .setup
        case .failed(let failure): return .failed(failure)
        // Only the first page waits on a skeleton; a search over a list
        // already on screen keeps that list instead of blanking it.
        case .loading where !hasApps: return .skeleton
        case .loading, .ready: return .catalog
        }
    }
}

struct AppsCatalogSkeleton: View {
    var body: some View {
        SkeletonPulse { opacity in
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: AppsMetrics.gridGap),
                               count: AppsSkeletonMetrics.columns),
                spacing: AppsMetrics.gridGap
            ) {
                ForEach(0..<AppsSkeletonMetrics.cards, id: \.self) { _ in card(opacity) }
            }
        }
        .padding(.top, AppsSkeletonMetrics.gridTop)
        // Incredible marks the grid aria-busy and every shape aria-hidden;
        // VoiceOver gets one label instead of sixteen empty shapes.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Localized.string("apps.loading"))
    }

    private func card(_ opacity: Double) -> some View {
        HStack(spacing: AppsSkeletonMetrics.cardGap) {
            SkeletonBlock(width: AppsSkeletonMetrics.icon, height: AppsSkeletonMetrics.icon,
                          radius: AppsSkeletonMetrics.iconRadius, opacity: opacity)
                // The lines column is greedy; the icon keeps its square first.
                .layoutPriority(1)
            VStack(alignment: .leading, spacing: Space.none) {
                SkeletonBlock(width: AppsSkeletonMetrics.titleWidth, height: AppsSkeletonMetrics.titleHeight,
                              radius: AppsSkeletonMetrics.lineRadius, opacity: opacity)
                SkeletonBlock(width: AppsSkeletonMetrics.lineWidth, height: AppsSkeletonMetrics.lineHeight,
                              radius: AppsSkeletonMetrics.lineRadius, opacity: opacity)
                    .padding(.top, AppsSkeletonMetrics.titleToLine)
                SkeletonBlock(width: AppsSkeletonMetrics.shortLineWidth, height: AppsSkeletonMetrics.lineHeight,
                              radius: AppsSkeletonMetrics.lineRadius, opacity: opacity)
                    .padding(.top, AppsSkeletonMetrics.lineToLine)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(AppsSkeletonMetrics.cardPadding)
        .background(Semantic.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppsSkeletonMetrics.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: AppsSkeletonMetrics.cardRadius)
            .strokeBorder(Semantic.borderChrome, lineWidth: Stroke.hairline))
    }
}
