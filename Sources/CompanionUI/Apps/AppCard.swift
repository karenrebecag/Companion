import CompanionCore
import SwiftUI

/// Incredible 0.2.36's connector card (local reference, `function Ch`), the
/// one its Apps page grid renders once the catalog is in: icon, name and a
/// two-line blurb in a row, the connect state trailing.
package enum AppCardMetrics {
    package static let padding: CGFloat = 18
    package static let radius: CGFloat = Radius.card
    package static let gap: CGFloat = Space.x4
    package static let icon: CGFloat = 48
    package static let iconRadius: CGFloat = Radius.xl
    /// Incredible draws the mark at 66 % of the tile: 32 inside 48.
    package static let iconInset: CGFloat = Space.x2
    /// The two-letter fallback: max(10, 48 * .28) rounded.
    package static let initialsSize: CGFloat = 13
    package static let textGap: CGFloat = Space.x1
    package static let titleSize: CGFloat = TypeSize.rowTitle
    package static let descriptionLines = 2
    package static let badgePaddingX: CGFloat = Space.x3
    package static let badgePaddingY: CGFloat = Space.x1_5
    package static let badgeGap: CGFloat = Space.x1_5
    package static let badgeIcon: CGFloat = 12
    package static let hoverDuration = MotionTime.fast
}

package enum AppCardTrailing: Equatable {
    case connect, reconnect, connected

    package static func kind(for state: ConnectedAccount.State?) -> AppCardTrailing {
        switch state {
        case .connected: .connected
        case .reconnect: .reconnect
        case nil: .connect
        }
    }

    package var titleKey: String {
        switch self {
        case .connect: "apps.connect"
        case .reconnect: "apps.reconnect"
        case .connected: "apps.connected"
        }
    }

    /// Incredible's Connect carries a plus; Reconnect is Companion's own state.
    package var systemImage: String? { self == .connect ? "plus" : nil }

    /// The VoiceOver action beside "open": nothing to do once connected.
    package var actionKey: String? { self == .connected ? nil : titleKey }
}

/// Two flexible columns at the page's gap.
struct AppsGrid<Item: Identifiable, Card: View>: View {
    let items: [Item]
    @ViewBuilder let card: (Item) -> Card

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: AppsMetrics.gridGap),
                           count: AppsSkeletonMetrics.columns),
            spacing: AppsMetrics.gridGap
        ) {
            ForEach(items) { card($0) }
        }
    }
}

package enum AppCardChrome {
    package static func border(hovering: Bool) -> Color {
        hovering ? Semantic.cardHoverBorder : Semantic.borderChrome
    }
}

struct AppCard: View {
    let app: CatalogApp
    let state: ConnectedAccount.State?
    let onOpen: () -> Void
    let onConnect: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: AppCardMetrics.gap) {
            AppIconView(icon: app.icon, size: AppCardMetrics.icon, padding: AppCardMetrics.iconInset,
                        radius: AppCardMetrics.iconRadius, fill: Semantic.surfaceSecondary, name: app.name)
            VStack(alignment: .leading, spacing: AppCardMetrics.textGap) {
                Text(app.name)
                    .font(Fonts.sans(AppCardMetrics.titleSize).weight(.medium))
                    .foregroundStyle(Semantic.foreground)
                    .lineLimit(1)
                if let description = app.description, !description.isEmpty {
                    Text(description)
                        .typeRole(.body)
                        .foregroundStyle(Semantic.mutedForeground)
                        .lineLimit(AppCardMetrics.descriptionLines)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            action.fixedSize()
        }
        .padding(AppCardMetrics.padding)
        // CSS grid stretches every card to its row's tallest (Incredible's
        // `pr`); the row stays centred inside, as its items-center does.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Semantic.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppCardMetrics.radius))
        .overlay(RoundedRectangle(cornerRadius: AppCardMetrics.radius)
            .strokeBorder(AppCardChrome.border(hovering: hovering), lineWidth: Stroke.hairline))
        .elevation(.hover)
        .animation(MotionCurve.animation(MotionCurve.standard, AppCardMetrics.hoverDuration), value: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .pointerStyle(.link)
        // The trailing Connect/Reconnect button is its own Button and keeps
        // its own action; SwiftUI resolves a tap inside it before this one.
        .onTapGesture(perform: onOpen)
        // A tap-only Rectangle is invisible to keyboard and VoiceOver: the
        // card reads as one button whose default action opens it, with
        // Conectar kept as a named action (review 19-1c).
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default, onOpen)
        .accessibilityActions {
            if let key = trailing.actionKey {
                Button(Localized.string(key), action: onConnect)
            }
        }
    }

    private var trailing: AppCardTrailing { AppCardTrailing.kind(for: state) }

    @ViewBuilder
    private var action: some View {
        switch trailing {
        case .connected:
            HStack(spacing: AppCardMetrics.badgeGap) {
                Image(systemName: "checkmark")
                    .font(Fonts.sans(AppCardMetrics.badgeIcon, face: .system).weight(.bold))
                    .accessibilityHidden(true)
                Text(Localized.string(trailing.titleKey))
                    .font(Fonts.sans(TypeSize.caption).weight(.medium))
            }
            .padding(.horizontal, AppCardMetrics.badgePaddingX)
            .padding(.vertical, AppCardMetrics.badgePaddingY)
            .foregroundStyle(Semantic.connectedInk)
            .background(Capsule().fill(Semantic.connectedWash))
        case .connect, .reconnect:
            AppButton(Localized.string(trailing.titleKey), kind: .ghost, systemImage: trailing.systemImage,
                      action: onConnect)
        }
    }
}
