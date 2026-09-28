import CompanionCore
import Foundation
import Observation

/// Wave 16k-1: the Apps page. The page talks to the companion-apps function
/// only; its address lives in defaults and its key in the Keychain, read on
/// the first `load()` and never before (§8: no Keychain reads at boot).
@Observable
@MainActor
public final class AppsModel {
    public enum Phase: Equatable {
        case setup, loading, ready
        case failed(AppsFailure)
    }

    /// Wave 16k-2a: the panel's own list, kept apart from `phase` — closing
    /// the panel or opening a different app must never paint over it with a
    /// stale answer (mirrors the connectError-is-per-card lesson of 16k-1).
    public enum ActionsPhase: Equatable {
        case idle, loading, ready([AppAction])
        case failed(AppsFailure)
    }

    public static let endpointDefault = "companion.apps.endpoint"
    /// `openssl rand -hex 32` gives 64; anything under 32 is not that key.
    static let minimumKeyLength = 32

    public private(set) var phase: Phase = .setup
    public private(set) var apps: [CatalogApp] = []
    public private(set) var total = 0
    public private(set) var query = ""
    /// A failed Connect belongs to one card, not to the page (code review 16k-1).
    public private(set) var connectError: AppsFailure?
    public private(set) var fetchingMore = false
    /// The app whose panel is open, or nil.
    public private(set) var selected: CatalogApp?
    public private(set) var actionsPhase: ActionsPhase = .idle
    private var next: String?
    private var accounts: [String: ConnectedAccount.State] = [:]
    private var service: (any AppsService)?

    private let secrets: any SecretStore
    private let defaults: UserDefaults
    private let makeService: @Sendable (URL, String) -> any AppsService

    public init(
        secrets: any SecretStore,
        defaults: UserDefaults = .standard,
        makeService: @escaping @Sendable (URL, String) -> any AppsService
    ) {
        self.secrets = secrets
        self.defaults = defaults
        self.makeService = makeService
    }

    public var hasMore: Bool { next != nil }
    public var remaining: Int { max(0, total - apps.count) }
    public var endpoint: String { defaults.string(forKey: Self.endpointDefault) ?? "" }

    public func state(of slug: String) -> ConnectedAccount.State? { accounts[slug] }

    /// Saves the function's address and key; false when either is not one.
    @discardableResult
    public func configure(endpoint text: String, key: String) -> Bool {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = AppsEndpoint.validated(text), trimmedKey.count >= Self.minimumKeyLength else { return false }
        do {
            try secrets.write(.companionApps, value: trimmedKey)
        } catch {
            return false
        }
        defaults.set(url.absoluteString, forKey: Self.endpointDefault)
        service = makeService(url, trimmedKey)
        return true
    }

    /// Code review 16k-2a (HIGH): catalog() and accounts() run concurrently
    /// and `phase` only reaches `.ready` once both are in, so the catalog
    /// (and its tappable cards) never appears a beat ahead of the marks —
    /// the earlier sequential await let a tap in that gap ask `actions(of:)`
    /// about an app the accounts dict did not know about yet, with nothing
    /// to retry the fetch once it did.
    public func load() async {
        guard let service = currentService() else {
            phase = .setup
            return
        }
        phase = .loading
        async let catalogResult = catalogAttempt(service, query: query, after: nil)
        async let marksResult = accountsSnapshot(service)
        let (result, marks) = await (catalogResult, marksResult)
        // A search typed while this page was in flight owns the list now.
        guard query == self.query else { return }
        switch result {
        case .success(let page):
            apps = page.apps
            total = page.total
            next = page.next
            accounts = marks
            phase = .ready
        case .failure(let failure):
            phase = .failed(failure)
        }
    }

    public func search(_ text: String) async {
        query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let service = currentService() else { return }
        await fetch(service, query: query, after: nil)
    }

    public func more() async {
        // A second tap while the page is on its way would append it twice.
        guard !fetchingMore, let service = currentService(), let next else { return }
        fetchingMore = true
        defer { fetchingMore = false }
        await fetch(service, query: query, after: next)
    }

    /// The Connect Link for the browser, or nil with the failure shown.
    public func connect(_ slug: String) async -> URL? {
        guard let service = currentService() else { return nil }
        do {
            let url = try await service.connectLink(app: slug)
            connectError = nil
            return url
        } catch {
            connectError = error as? AppsFailure ?? .unexpected
            return nil
        }
    }

    /// Opens the app's panel. Loading is the view's job (`.task(id:)`,
    /// mirroring the search debounce), not this call's — a tap must never
    /// block on the network before the sheet appears.
    public func open(_ app: CatalogApp) {
        selected = app
        actionsPhase = .idle
    }

    public func closePanel() {
        selected = nil
        actionsPhase = .idle
    }

    /// The function's `/api/tools` requires a connected account; Companion
    /// mirrors Incredible and never calls it for one that is not (audit
    /// §9.6: "Connect X to see everything it can do" is the whole panel).
    public func actions(of app: CatalogApp) async {
        guard state(of: app.slug) == .connected, let service = currentService() else { return }
        actionsPhase = .loading
        do {
            let actions = try await service.tools(app: app.slug)
            guard selected?.slug == app.slug else { return }
            actionsPhase = .ready(actions)
        } catch {
            guard selected?.slug == app.slug else { return }
            actionsPhase = .failed(error as? AppsFailure ?? .unexpected)
        }
    }

    private func catalogAttempt(_ service: any AppsService, query: String, after: String?) async -> Result<CatalogPage, AppsFailure> {
        do {
            return .success(try await service.catalog(query: query, after: after))
        } catch {
            return .failure(error as? AppsFailure ?? .unexpected)
        }
    }

    /// Without accounts the catalog still lists; only the marks are missing.
    private func accountsSnapshot(_ service: any AppsService) async -> [String: ConnectedAccount.State] {
        do {
            return Dictionary(
                try await service.accounts().map { ($0.app, $0.state) },
                uniquingKeysWith: { first, _ in first })
        } catch {
            return [:]
        }
    }

    private func fetch(_ service: any AppsService, query: String, after: String?) async {
        do {
            let page = try await service.catalog(query: query, after: after)
            // A search typed while this page was in flight owns the list now.
            guard query == self.query else { return }
            apps = after == nil ? page.apps : apps + page.apps
            total = page.total
            next = page.next
            phase = .ready
        } catch {
            phase = .failed(error as? AppsFailure ?? .unexpected)
        }
    }

    private func currentService() -> (any AppsService)? {
        if let service { return service }
        guard let url = AppsEndpoint.validated(endpoint) else { return nil }
        let key: String?
        do {
            key = try secrets.read(.companionApps)
        } catch {
            return nil
        }
        guard let key, key.count >= Self.minimumKeyLength else { return nil }
        let made = makeService(url, key)
        service = made
        return made
    }
}
