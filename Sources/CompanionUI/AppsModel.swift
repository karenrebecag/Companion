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

    public func load() async {
        guard let service = currentService() else {
            phase = .setup
            return
        }
        phase = .loading
        await fetch(service, query: query, after: nil)
        guard phase == .ready else { return }
        // Without accounts the catalog still lists; only the marks are missing.
        do {
            accounts = Dictionary(
                try await service.accounts().map { ($0.app, $0.state) },
                uniquingKeysWith: { first, _ in first })
        } catch {
            accounts = [:]
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
