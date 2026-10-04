import CompanionCore
import SwiftUI

/// Wave 16k-1: Incredible's Apps page (spec 16k §1) — a header card, the
/// search, the featured grid in two columns and "Show more". Until the
/// function is set up the page asks for it instead of showing buttons that
/// do nothing.
package enum AppsMetrics {
    // None of these are in docs/research: Incredible's Apps grid was read for
    // its structure, not its pixels. Own values, pinned in Pins16p3Tests so a
    // later capture overrules them on purpose.
    package static let iconRadius: CGFloat = Radius.md
    package static let gridGap: CGFloat = Space.x4
    package static let formWidth: CGFloat = 460
    /// Typing pause before a search goes out; not motion, a request budget.
    package static let searchPause = 0.3
}

enum AppsCopy {
    static func failure(_ failure: AppsFailure) -> String {
        switch failure {
        case .notConfigured(let missing):
            String(format: Localized.string("apps.error.notConfigured"), missing.joined(separator: ", "))
        case .unauthorized: Localized.string("apps.error.unauthorized")
        case .rateLimited: Localized.string("apps.error.rateLimited")
        case .unreachable: Localized.string("apps.error.unreachable")
        case .invalidInput, .notFound, .approvalRequired, .upstream, .unexpected:
            Localized.string("apps.error.generic")
        }
    }
}

struct AppsPage: View {
    var apps: AppsModel
    @State private var searchText: String
    @State private var editing = false
    @State private var showingOwn = false

    /// The model outlives the page; seeding from it keeps a revisit from
    /// throwing away the last search (code review 16k-1).
    init(apps: AppsModel) {
        self.apps = apps
        self._searchText = State(initialValue: apps.query)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x6) {
                header
                content
                if apps.ownEnabled { ownFooter }
            }
            .frame(maxWidth: HomeMetrics.maxWidth, alignment: .leading)
            .padding(.top, HomeMetrics.tasksTop)
            .padding(.horizontal, HomeMetrics.paddingX)
            .padding(.bottom, HomeMetrics.paddingBottom)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .task { await apps.load() }
        .task(id: searchText) {
            guard searchText != apps.query else { return }
            // Waits out the typing so each keystroke is not a request.
            do {
                try await Task.sleep(for: .seconds(AppsMetrics.searchPause))
            } catch {
                return
            }
            await apps.search(searchText)
        }
        .overlay { panelSheet }
        .overlay { connectingSheet }
        .overlay { ownSheet }
        .animation(.springSheet, value: apps.selected?.id)
        .animation(.springSheet, value: apps.connecting?.id)
        .animation(.springSheet, value: showingOwn)
    }

    // Mirrors TaskDetailSheet's presentation idiom (spec 16j §8): a scrim
    // plus a centered, size-capped sheet over this page's own content.
    @ViewBuilder
    private var panelSheet: some View {
        if let selected = apps.selected {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Semantic.scrim)
                    .ignoresSafeArea()
                    .onTapGesture { apps.closePanel() }
                GeometryReader { geo in
                    AppPanel(
                        app: selected, state: apps.state(of: selected.slug),
                        accountName: apps.accountName(of: selected.slug), phase: apps.actionsPhase,
                        disconnectPhase: apps.disconnectPhase,
                        onConnect: { apps.start(selected) },
                        onDisconnectTapped: { apps.confirmDisconnect() },
                        onConfirmDisconnect: { Task { await apps.disconnect() } },
                        onCancelDisconnect: { apps.cancelDisconnect() },
                        onClose: { apps.closePanel() })
                    .frame(width: min(AppPanelMetrics.maxWidth, geo.size.width - Space.x6),
                           height: min(AppPanelMetrics.maxHeight, geo.size.height - Space.x6))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
            .task(id: selected.id) { await apps.actions(of: selected) }
            .transition(.opacity)
        }
    }

    // Stacks over the app panel, same scrim idiom: the modal (16k-2b) is
    // never a navigation, just a sheet on top of whatever else is open.
    @ViewBuilder
    private var connectingSheet: some View {
        if let connecting = apps.connecting {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Semantic.scrim)
                    .ignoresSafeArea()
                GeometryReader { geo in
                    ConnectingSheet(
                        app: connecting, phase: apps.connectPhase, showsHint: apps.connectShowsHint,
                        onOpenAgain: { apps.openAgain() }, onRetry: { apps.retryConnecting() },
                        onFinish: { apps.finishConnecting() }, onClose: { apps.finishConnecting() })
                    .frame(width: min(ConnectingSheetMetrics.maxWidth, geo.size.width - Space.x6))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
            .transition(.opacity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text(Localized.string("apps.title"))
                .font(Fonts.sans(TypeSize.dialogTitle).weight(.semibold))
                .tracking(Tracking.title, at: TypeSize.dialogTitle)
                .foregroundStyle(Semantic.foreground)
            Text(Localized.string("apps.lede"))
                .typeRole(.body)
                .foregroundStyle(Semantic.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.x6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Semantic.surface)
        .clipShape(RoundedRectangle(cornerRadius: CardChrome.radius))
        .overlay(RoundedRectangle(cornerRadius: CardChrome.radius)
            .strokeBorder(Semantic.borderChrome, lineWidth: Stroke.hairline))
        .elevation(.hover)
    }

    @ViewBuilder
    private var content: some View {
        let kind = AppsContentKind.of(phase: apps.phase, hasApps: !apps.apps.isEmpty, editing: editing)
        if kind == .setup {
            // 16k-2d: the catalog is the page even before the function
            // exists — Incredible shows its featured apps from first
            // launch, and a bare form read as a broken page (Karen, en
            // vivo). The seed renders the same grid; Conectar routes here.
            if editing {
                // The form loads the catalog itself before confirming.
                AppsSetupForm(apps: apps, initialEndpoint: apps.endpoint) { editing = false }
            } else {
                AppsSetupBanner { editing = true }
            }
            AppField(placeholder: Localized.string("apps.search"), text: $searchText)
            seededFeatured
        } else {
            AppField(placeholder: Localized.string("apps.search"), text: $searchText)
            switch kind {
            case .failed(let failure):
                failed(failure)
            case .skeleton:
                AppsCatalogSkeleton()
            case .catalog, .setup:
                catalog
            }
        }
    }

    private var seededFeatured: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            HStack {
                Text(Localized.string("apps.featured"))
                    .font(.uiLabel.weight(.semibold))
                    .foregroundStyle(Semantic.foreground)
                Spacer()
                Text(Localized.string("apps.seed.total"))
                    .font(.uiCaption)
                    .monospacedDigit()
                    .foregroundStyle(Semantic.mutedForeground)
            }
            AppsGrid(items: CatalogSeed.filtered(searchText, language: Localized.language())) { app in
                AppCard(app: app, state: nil,
                        onOpen: { editing = true }, onConnect: { editing = true })
            }
        }
    }

    private func failed(_ failure: AppsFailure) -> some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            Text(AppsCopy.failure(failure))
                .typeRole(.body)
                .foregroundStyle(Semantic.foreground)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.x2) {
                AppButton(Localized.string("apps.retry"), kind: .secondary) { Task { await apps.load() } }
                AppButton(Localized.string("apps.setup.change"), kind: .ghost) { editing = true }
            }
        }
    }

    private var catalog: some View {
        VStack(alignment: .leading, spacing: Space.x6) {
            // Spec §9.2.3: "Tus apps" first, only when there is one; the
            // catalog below never repeats what is already up here.
            if !apps.connectedSection.isEmpty { yourApps }
            featured
        }
    }

    private var yourApps: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            Text(Localized.string("apps.yours"))
                .font(.uiLabel.weight(.semibold))
                .foregroundStyle(Semantic.foreground)
            grid(apps.connectedSection)
        }
    }

    private var featured: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            HStack {
                Text(listTitle)
                    .font(.uiLabel.weight(.semibold))
                    .foregroundStyle(Semantic.foreground)
                Spacer()
                Text(String(format: Localized.string("apps.total"), apps.total))
                    .font(.uiCaption)
                    .monospacedDigit()
                    .foregroundStyle(Semantic.mutedForeground)
            }
            if let connectError = apps.connectError {
                Text(AppsCopy.failure(connectError))
                    .typeRole(.micro)
                    .foregroundStyle(Semantic.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if apps.apps.isEmpty {
                Text(Localized.string("apps.none"))
                    .font(.uiBody)
                    .foregroundStyle(Semantic.mutedForeground)
            }
            grid(apps.catalogSection)
            if apps.hasMore {
                AppButton(String(format: Localized.string("apps.more"), apps.remaining),
                          kind: .secondary, fullWidth: true, enabled: !apps.fetchingMore) {
                    Task { await apps.more() }
                }
            }
        }
    }

    private func grid(_ items: [CatalogApp]) -> some View {
        AppsGrid(items: items) { app in
            AppCard(app: app, state: apps.state(of: app.slug),
                    onOpen: { apps.open(app) }, onConnect: { apps.start(app) })
        }
    }

    private var listTitle: String {
        Localized.string(apps.query.isEmpty ? "apps.featured" : "apps.results")
    }

    /// Spec 16k §2.2: the page's last line, same as Incredible's — a
    /// question and a link into the own-servers sheet.
    private var ownFooter: some View {
        HStack(spacing: Space.x2) {
            Text(Localized.string("apps.own.prompt"))
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
            AppButton(Localized.string("apps.own.add"), kind: .ghost) {
                apps.loadOwn()
                showingOwn = true
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // Same scrim idiom as the panel and the connecting modal: a sheet over
    // this page's own content, never a navigation.
    @ViewBuilder
    private var ownSheet: some View {
        if showingOwn {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Semantic.scrim)
                    .ignoresSafeArea()
                    .onTapGesture { showingOwn = false }
                GeometryReader { geo in
                    OwnMCPSheet(apps: apps, onClose: { showingOwn = false })
                        .frame(width: min(AppsMetrics.formWidth, geo.size.width - Space.x6))
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
            .transition(.opacity)
        }
    }
}

/// Third-party marks load from the catalog's URL; none is kept in the repo.
/// Shared by the card and the panel, which only differ in size.
struct AppIconView: View {
    let icon: URL?
    let size: CGFloat
    let padding: CGFloat
    var radius: CGFloat = AppsMetrics.iconRadius
    var fill: Color = Semantic.hover
    /// With a name, a missing mark shows its first two letters, as
    /// Incredible's card does; without one, the generic glyph.
    var name: String?

    var body: some View {
        AsyncImage(url: icon) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            placeholder
        }
        .padding(padding)
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: radius).fill(fill))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var placeholder: some View {
        if let name, let initials = Self.initials(of: name) {
            Text(initials)
                .font(Fonts.sans(AppCardMetrics.initialsSize).weight(.bold))
                .foregroundStyle(Semantic.textMuted)
                .fixedSize()
        } else {
            Image(systemName: "square.grid.2x2").foregroundStyle(Semantic.mutedForeground)
        }
    }

    /// Incredible's `name.slice(0,2).toUpperCase()`, bounded: trimmed, whole
    /// graphemes only (while they fit its two UTF-16 units), at most two
    /// characters after uppercasing ("ß" grows), nil when nothing is left.
    static func initials(of name: String) -> String? {
        var units = 0
        var taken = ""
        for character in name.trimmingCharacters(in: .whitespacesAndNewlines) {
            let width = character.utf16.count
            if !taken.isEmpty && units + width > 2 { break }
            taken.append(character)
            units += width
            if units >= 2 { break }
        }
        let mark = String(taken.uppercased().prefix(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        return mark.isEmpty ? nil : mark
    }
}
