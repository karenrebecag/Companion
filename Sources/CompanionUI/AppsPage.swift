import CompanionCore
import SwiftUI

/// Wave 16k-1: Incredible's Apps page (spec 16k §1) — a header card, the
/// search, the featured grid in two columns and "Show more". Until the
/// function is set up the page asks for it instead of showing buttons that
/// do nothing.
public enum AppsMetrics {
    public static let icon: CGFloat = 40
    public static let iconRadius: CGFloat = Radius.md
    public static let cardMinHeight: CGFloat = 132
    public static let gridGap: CGFloat = Space.x4
    public static let formWidth: CGFloat = 460
    /// Typing pause before a search goes out; not motion, a request budget.
    public static let searchPause = 0.3
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
    @Environment(\.openURL) private var openURL

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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text(Localized.string("apps.title"))
                .font(Fonts.sans(TypeSize.dialogTitle).weight(.semibold))
                .tracking(Tracking.title, at: TypeSize.dialogTitle)
                .foregroundStyle(Semantic.foreground)
            Text(Localized.string("apps.lede"))
                .font(.uiBody)
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
        if apps.phase == .setup || editing {
            AppsSetupForm(apps: apps, initialEndpoint: apps.endpoint) {
                editing = false
                Task { await apps.load() }
            }
        } else {
            AppField(placeholder: Localized.string("apps.search"), text: $searchText)
            switch apps.phase {
            case .failed(let failure):
                failed(failure)
            case .loading where apps.apps.isEmpty:
                ProgressView().controlSize(.small)
            default:
                catalog
            }
        }
    }

    private func failed(_ failure: AppsFailure) -> some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            Text(AppsCopy.failure(failure))
                .font(.uiBody)
                .foregroundStyle(Semantic.foreground)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Space.x2) {
                AppButton(Localized.string("apps.retry"), kind: .secondary) { Task { await apps.load() } }
                AppButton(Localized.string("apps.setup.change"), kind: .ghost) { editing = true }
            }
        }
    }

    private var catalog: some View {
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
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if apps.apps.isEmpty {
                Text(Localized.string("apps.none"))
                    .font(.uiBody)
                    .foregroundStyle(Semantic.mutedForeground)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: AppsMetrics.gridGap),
                                GridItem(.flexible(), spacing: AppsMetrics.gridGap)],
                      spacing: AppsMetrics.gridGap) {
                ForEach(apps.apps) { app in
                    AppCard(app: app, state: apps.state(of: app.slug)) { connect(app.slug) }
                }
            }
            if apps.hasMore {
                AppButton(String(format: Localized.string("apps.more"), apps.remaining),
                          kind: .secondary, fullWidth: true, enabled: !apps.fetchingMore) {
                    Task { await apps.more() }
                }
            }
        }
    }

    private var listTitle: String {
        Localized.string(apps.query.isEmpty ? "apps.featured" : "apps.results")
    }

    private func connect(_ slug: String) {
        Task {
            if let url = await apps.connect(slug) { openURL(url) }
        }
    }
}

struct AppCard: View {
    let app: CatalogApp
    let state: ConnectedAccount.State?
    let onConnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            HStack(spacing: Space.x3) {
                icon
                Text(app.name)
                    .font(Fonts.sans(TypeSize.rowTitle).weight(.semibold))
                    .foregroundStyle(Semantic.foreground)
                    .lineLimit(1)
                Spacer(minLength: Space.none)
            }
            if let description = app.description, !description.isEmpty {
                Text(description)
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.none)
            action
        }
        .padding(CardChrome.padding)
        .frame(maxWidth: .infinity, minHeight: AppsMetrics.cardMinHeight, alignment: .topLeading)
        .background(Semantic.surface)
        .clipShape(RoundedRectangle(cornerRadius: CardChrome.radius))
        .overlay(RoundedRectangle(cornerRadius: CardChrome.radius)
            .strokeBorder(Semantic.borderChrome, lineWidth: Stroke.hairline))
    }

    @ViewBuilder
    private var action: some View {
        switch state {
        case .connected:
            HStack(spacing: Space.x2) {
                StatusDot(IslandInk.green)
                Text(Localized.string("apps.connected")).font(.uiCaption)
                    .foregroundStyle(Semantic.foreground)
            }
        case .reconnect:
            AppButton(Localized.string("apps.reconnect"), kind: .secondary, action: onConnect)
        case nil:
            AppButton(Localized.string("apps.connect"), kind: .secondary, action: onConnect)
        }
    }

    private var icon: some View {
        // Third-party marks load from the catalog's URL; none is kept here.
        AsyncImage(url: app.icon) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Image(systemName: "square.grid.2x2").foregroundStyle(Semantic.mutedForeground)
        }
        .padding(Space.x1_5)
        .frame(width: AppsMetrics.icon, height: AppsMetrics.icon)
        .background(RoundedRectangle(cornerRadius: AppsMetrics.iconRadius).fill(Semantic.hover))
        .accessibilityHidden(true)
    }
}

/// The function's address and key. The key field never shows what is
/// stored: a save clears it.
struct AppsSetupForm: View {
    var apps: AppsModel
    @State private var endpoint: String
    @State private var key = ""
    @State private var error: String?
    let onSaved: () -> Void

    init(apps: AppsModel, initialEndpoint: String, onSaved: @escaping () -> Void) {
        self.apps = apps
        self._endpoint = State(initialValue: initialEndpoint)
        self.onSaved = onSaved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            Text(Localized.string("apps.setup.title"))
                .font(.uiLabel.weight(.semibold))
                .foregroundStyle(Semantic.foreground)
            Text(Localized.string("apps.setup.body"))
                .font(.uiBody)
                .foregroundStyle(Semantic.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            AppField(title: Localized.string("apps.setup.endpoint"),
                     placeholder: Localized.string("apps.setup.endpoint.placeholder"), text: $endpoint)
            AppField(title: Localized.string("apps.setup.key"),
                     placeholder: Localized.string("apps.setup.key.placeholder"),
                     text: $key, error: error, secure: true, onSubmit: save)
            AppButton(Localized.string("apps.setup.save"), action: save)
        }
        .frame(maxWidth: AppsMetrics.formWidth, alignment: .leading)
    }

    private func save() {
        guard apps.configure(endpoint: endpoint, key: key) else {
            error = Localized.string("apps.setup.invalid")
            return
        }
        key = ""
        error = nil
        onSaved()
    }
}
