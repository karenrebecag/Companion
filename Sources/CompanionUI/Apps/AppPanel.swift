import CompanionCore
import SwiftUI

/// Wave 16k-2a (spec §9.2.1, D1 audited layout): the app panel. Left column
/// is icon/name/description/connect state; right column is the actions,
/// grouped Leer / Crear y cambiar / Borrar, with a search field. Connecting
/// is 16k-2b; Desconectar (16k-2c) lives in `connectState` below.
package enum AppPanelMetrics {
    // Audited from Incredible's connector dialog (spec 16k §9.5 D1), not
    // from docs/research: max 1000 x 700, a 430 left column, a 44 icon.
    package static let maxWidth: CGFloat = 1000
    package static let maxHeight: CGFloat = 700
    package static let leftWidth: CGFloat = 430
    package static let icon: CGFloat = 44
}

struct AppPanel: View {
    let app: CatalogApp
    let state: ConnectedAccount.State?
    let accountName: String?
    let phase: AppsModel.ActionsPhase
    let disconnectPhase: AppsModel.DisconnectPhase
    let onConnect: () -> Void
    let onDisconnectTapped: () -> Void
    let onConfirmDisconnect: () -> Void
    let onCancelDisconnect: () -> Void
    let onClose: () -> Void

    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            header
            HStack(alignment: .top, spacing: Space.x6) {
                left.frame(width: AppPanelMetrics.leftWidth, alignment: .leading)
                right.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .padding(Space.x6)
        .background(RoundedRectangle(cornerRadius: Radius.card).fill(Semantic.background))
        .overlay(RoundedRectangle(cornerRadius: Radius.card).stroke(Semantic.border, lineWidth: Stroke.hairline))
    }

    private var header: some View {
        HStack(spacing: Space.x3) {
            Text(app.name)
                .font(.uiSubtitle)
                .foregroundStyle(Semantic.foreground)
                .lineLimit(1)
            Spacer()
            CloseButton(action: onClose)
        }
    }

    private var left: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            AppIconView(icon: app.icon, size: AppPanelMetrics.icon, padding: Space.x2)
            if let description = app.description, !description.isEmpty {
                Text(description)
                    .typeRole(.body)
                    .foregroundStyle(Semantic.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            connectState
            Spacer(minLength: Space.x4)
            Text(Localized.string("apps.panel.poweredBy"))
                .typeRole(.micro)
                .foregroundStyle(Semantic.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            Text(Localized.string("apps.panel.privacy"))
                .typeRole(.micro)
                .foregroundStyle(Semantic.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var connectState: some View {
        switch state {
        case .connected:
            VStack(alignment: .leading, spacing: Space.x3) {
                Badge(accountName ?? Localized.string("apps.connected"),
                      variant: .secondary, dot: IslandInk.green)
                disconnectSection
            }
        case .reconnect:
            // Same copy as the card (spec §9.4).
            AppButton(Localized.string("apps.reconnect"), action: onConnect)
        case nil:
            AppButton(String(format: Localized.string("apps.panel.connect"), app.name), action: onConnect)
        }
    }

    /// Spec §9.2.4 + audit §9.6 (ghost "Disconnect X" with a
    /// "Disconnecting…" spinner): the confirmation copy also folds in
    /// Pipedream's own gap (spec §3) — disconnecting here never revokes the
    /// grant on the app's own side.
    @ViewBuilder
    private var disconnectSection: some View {
        switch disconnectPhase {
        case .idle:
            AppButton(String(format: Localized.string("apps.panel.disconnect"), app.name),
                      kind: .ghost, action: onDisconnectTapped)
        case .confirming:
            VStack(alignment: .leading, spacing: Space.x2) {
                Text(String(format: Localized.string("apps.panel.disconnect.confirm"), app.name))
                    .typeRole(.micro)
                    .foregroundStyle(Semantic.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.x2) {
                    AppButton(Localized.string("apps.panel.disconnect.confirmButton"),
                              kind: .destructive, action: onConfirmDisconnect)
                    AppButton(Localized.string("apps.panel.disconnect.cancel"),
                              kind: .ghost, action: onCancelDisconnect)
                }
            }
        case .disconnecting:
            HStack(spacing: Space.x2) {
                ProgressView().controlSize(.small)
                Text(Localized.string("apps.panel.disconnecting"))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Localized.string("apps.panel.disconnecting"))
        case .failed(let failure):
            VStack(alignment: .leading, spacing: Space.x2) {
                Text(AppsCopy.failure(failure))
                    .typeRole(.micro)
                    .foregroundStyle(Semantic.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                AppButton(String(format: Localized.string("apps.panel.disconnect"), app.name),
                          kind: .ghost, action: onDisconnectTapped)
            }
        }
    }

    /// Audit §9.6: a not-yet-connected app never lists actions — the
    /// function's `/api/tools` needs the account, and the empty state names
    /// that instead of an error.
    @ViewBuilder
    private var right: some View {
        if state == .connected {
            connectedActions
        } else {
            Text(String(format: Localized.string("apps.panel.emptyNotConnected"), app.name))
                .typeRole(.body)
                .foregroundStyle(Semantic.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var connectedActions: some View {
        switch phase {
        case .idle, .loading:
            HStack(spacing: Space.x2) {
                ProgressView().controlSize(.small)
                Text(Localized.string("apps.panel.loading"))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Localized.string("apps.panel.loading"))
        case .failed(let failure):
            Text(AppsCopy.failure(failure))
                .typeRole(.body)
                .foregroundStyle(Semantic.destructive)
                .fixedSize(horizontal: false, vertical: true)
        case .ready(let actions) where actions.isEmpty:
            Text(String(format: Localized.string("apps.panel.emptyListed"), app.name))
                .typeRole(.body)
                .foregroundStyle(Semantic.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        case .ready(let actions):
            actionsList(actions)
        }
    }

    private func actionsList(_ actions: [AppAction]) -> some View {
        let filtered = AppPanelCopy.filter(actions, matching: search)
        return VStack(alignment: .leading, spacing: Space.x3) {
            AppField(placeholder: String(format: Localized.string("apps.panel.search"), actions.count), text: $search)
            if filtered.isEmpty {
                Text(Localized.string("apps.panel.noMatches"))
                    .font(.uiBody)
                    .foregroundStyle(Semantic.mutedForeground)
            } else {
                ScrollView {
                    // Security review 16k-2a (MEDIUM): a capped list can still
                    // be long across three groups; lazy keeps an open panel
                    // from building rows it is not showing.
                    LazyVStack(alignment: .leading, spacing: Space.x4) {
                        ForEach(AppAction.Group.allCases, id: \.self) { group in
                            let items = filtered.filter { $0.group == group }
                            if !items.isEmpty { groupSection(group, items) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func groupSection(_ group: AppAction.Group, _ items: [AppAction]) -> some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text(AppPanelCopy.title(group))
                .font(.uiLabel.weight(.semibold))
                .foregroundStyle(Semantic.foreground)
            Text(AppPanelCopy.note(group))
                .typeRole(.micro)
                .foregroundStyle(Semantic.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            LazyVStack(alignment: .leading, spacing: Space.x2) {
                ForEach(items) { action in actionRow(action) }
            }
        }
    }

    private func actionRow(_ action: AppAction) -> some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(action.name).font(.uiBody).foregroundStyle(Semantic.foreground)
            if !action.description.isEmpty {
                // Security review 16k-2a (MEDIUM): this text comes from the
                // connected app, not Companion — a quote-style rule and a
                // line cap keep it from reading as Companion's own trust
                // copy (the group note right above shares the same font).
                HStack(alignment: .top, spacing: Space.x2) {
                    Rectangle().fill(Semantic.borderChrome).frame(width: Stroke.hairline)
                    Text(action.description)
                        .typeRole(.micro)
                        .foregroundStyle(Semantic.mutedForeground)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Space.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md).fill(Semantic.muted))
    }
}

enum AppPanelCopy {
    static func title(_ group: AppAction.Group) -> String {
        Localized.string("apps.group.\(group.rawValue)")
    }

    static func note(_ group: AppAction.Group) -> String {
        Localized.string("apps.group.\(group.rawValue).note")
    }

    static func filter(_ actions: [AppAction], matching text: String) -> [AppAction] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return actions }
        return actions.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query)
        }
    }
}
