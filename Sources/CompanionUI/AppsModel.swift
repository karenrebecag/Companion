import AppKit
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

    /// Wave 16k-2c: the panel's "Desconectar" flow (spec §9.2.4). Kept apart
    /// from `actionsPhase` for the same reason that one is kept apart from
    /// `phase` — a stale answer must never repaint a panel nobody has open.
    public enum DisconnectPhase: Equatable {
        case idle, confirming, disconnecting
        case failed(AppsFailure)
    }

    // nonisolated: the composition root reads it inside the app runner's
    // Sendable service closure (16k-3), off the MainActor.
    public nonisolated static let endpointDefault = "companion.apps.endpoint"
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
    public private(set) var disconnectPhase: DisconnectPhase = .idle
    /// Wave 16k-2b: the app the connecting modal is open for, or nil.
    public private(set) var connecting: CatalogApp?
    public private(set) var connectPhase: ConnectPoll.Phase = .initiating
    private var next: String?
    /// The full account, not just its state: disconnect(account:) needs the
    /// id, which the slug alone does not carry.
    private var accounts: [String: ConnectedAccount] = [:]
    private var service: (any AppsService)?
    private var connectPoll: ConnectPoll?
    private var connectURL: URL?
    private var connectTask: Task<Void, Never>?
    /// Wave 16k-2c: bumped by every `open(_:)` and `closePanel()`, mirroring
    /// `connectEpoch` — a disconnect() awaiting the function must not land on
    /// a panel that closed, or reopened for the same app, while it was gone.
    private var panelEpoch = 0
    /// Code review + security review (HIGH, 16k-2b): `stillConnecting` used
    /// to compare only the slug, so a same-app double-tap — attempt A still
    /// parked in `connectLink`/`accounts()` while attempt B (same slug)
    /// already runs — let A's late, cancelled resolution pass every guard.
    /// Bumped by every `start(_:)`, `retryConnecting()` and
    /// `finishConnecting()`; each attempt captures its own value and is
    /// stale the moment it no longer matches.
    private var connectEpoch = 0

    private let secrets: any SecretStore
    /// 20c D6: the function's key lives here, bound to the endpoint's host;
    /// `secrets` is only where an older build left it.
    private let hostSecrets: any HostSecretStore
    private let launchPin: AppsLaunchPin
    private let defaults: UserDefaults
    private let makeService: @Sendable (URL, String) -> any AppsService
    /// Wave 16k-2b: the same injected-sleep seam `SessionModel` uses, so the
    /// 3 s poll interval never makes a test wait real time.
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let now: @Sendable () -> TimeInterval
    /// Where "Abrimos el inicio de sesión…" actually happens. `NSWorkspace`
    /// directly, the same as `SourcesCard`/`GalleryCard` — the model has no
    /// SwiftUI environment to borrow `openURL` from.
    private let openBrowser: @Sendable (URL) -> Void
    /// 16k-4: the mcp.json seam, injected by the composition root because
    /// the UI layer never reads the disk itself. nil hides the section.
    private let readMCP: (@Sendable () -> MCPFileRead)?
    private let saveMCP: (@Sendable ([MCPServerConfig]) throws -> Void)?
    /// The UI layer has no logger of its own; the credential moves report
    /// their non-fatal failures through the composition root's.
    private let log: @Sendable (String) -> Void

    public init(
        secrets: any SecretStore,
        hostSecrets: any HostSecretStore,
        launchPin: AppsLaunchPin = .unobserved,
        defaults: UserDefaults = .standard,
        makeService: @escaping @Sendable (URL, String) -> any AppsService,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
            try await Task.sleep(for: .seconds($0))
        },
        now: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 },
        openBrowser: @escaping @Sendable (URL) -> Void = { NSWorkspace.shared.open($0) },
        readMCP: (@Sendable () -> MCPFileRead)? = nil,
        saveMCP: (@Sendable ([MCPServerConfig]) throws -> Void)? = nil,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.secrets = secrets
        self.hostSecrets = hostSecrets
        self.launchPin = launchPin
        self.defaults = defaults
        self.makeService = makeService
        self.sleep = sleep
        self.now = now
        self.openBrowser = openBrowser
        self.readMCP = readMCP
        self.saveMCP = saveMCP
        self.log = log
    }

    // 16k-4 "Añádelo aquí": the user's own MCP servers, shown and edited
    // from this page. The list edits are pure (OwnMCPEdit); this model
    // sequences read-fresh → edit → persist → publish. Every edit re-reads
    // the disk so a hand edit made while the sheet is open survives (M1),
    // a failed save never shows a list the disk does not hold, and a file
    // that no longer parses blocks editing instead of being wiped by the
    // next save (H1, review 16k-4).
    public private(set) var ownServers: [MCPServerConfig] = []
    public private(set) var ownError: OwnMCPEdit.EditError?
    public private(set) var ownSaveFailed = false
    public private(set) var ownFileBroken = false
    public var ownEnabled: Bool { readMCP != nil && saveMCP != nil }

    public func loadOwn() {
        clearOwnReports()
        if let fresh = freshOwn() { ownServers = fresh }
    }

    /// True when the server was added AND saved — the form clears on true.
    public func addOwn(label: String, url: String) -> Bool {
        clearOwnReports()
        guard let fresh = freshOwn() else { return false }
        switch OwnMCPEdit.add(fresh, label: label, url: url) {
        case .failure(let error):
            ownError = error
            return false
        case .success(let servers):
            return persistOwn(servers)
        }
    }

    public func removeOwn(label: String) {
        clearOwnReports()
        guard let fresh = freshOwn() else { return }
        _ = persistOwn(OwnMCPEdit.remove(fresh, label: label))
    }

    /// Each action reports only its own outcome (review 16k-4: a stale
    /// disk failure must not mask a new validation error).
    private func clearOwnReports() {
        ownError = nil
        ownSaveFailed = false
        ownFileBroken = false
    }

    /// The disk's current list, or nil when the file cannot be trusted.
    private func freshOwn() -> [MCPServerConfig]? {
        switch readMCP?() {
        case .servers(let servers): return servers
        case .absent: return []
        case .unreadable:
            ownFileBroken = true
            return nil
        case nil: return nil
        }
    }

    private func persistOwn(_ servers: [MCPServerConfig]) -> Bool {
        guard let saveMCP else { return false }
        do {
            try saveMCP(servers)
        } catch {
            ownSaveFailed = true
            return false
        }
        ownServers = servers
        return true
    }

    public var hasMore: Bool { next != nil }
    public var remaining: Int { max(0, total - apps.count) }
    public var endpoint: String { defaults.string(forKey: Self.endpointDefault) ?? "" }
    /// Audit §9.6: the "still waiting on the browser" hint, after several attempts.
    public var connectShowsHint: Bool { connectPoll?.showsStillWaitingHint ?? false }

    public func state(of slug: String) -> ConnectedAccount.State? { accounts[slug]?.state }
    public func accountName(of slug: String) -> String? { accounts[slug]?.name }

    /// "Tus apps" (spec §9.2.3): connected first, then reconnect-needed, in
    /// the order the catalog already has them — never re-sorted here.
    public var connectedSection: [CatalogApp] {
        apps.filter { accounts[$0.slug]?.state == .connected }
            + apps.filter { accounts[$0.slug]?.state == .reconnect }
    }

    /// The featured grid below "Tus apps", with those same apps removed so
    /// nothing repeats between the two sections.
    public var catalogSection: [CatalogApp] {
        apps.filter { accounts[$0.slug] == nil }
    }

    /// Saves the function's address and key; false when either is not one.
    @discardableResult
    public func configure(endpoint text: String, key: String) -> Bool {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = AppsEndpoint.validated(text), trimmedKey.count >= Self.minimumKeyLength else { return false }
        guard let host = SecretHost.of(url: url.absoluteString) else { return false }
        do {
            try AppsCredentials.save(
                trimmedKey, host: host, previousHost: SecretHost.of(url: endpoint),
                legacy: secrets, bound: hostSecrets, log: log)
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
        panelEpoch += 1
        selected = app
        actionsPhase = .idle
        disconnectPhase = .idle
    }

    public func closePanel() {
        panelEpoch += 1
        selected = nil
        actionsPhase = .idle
        disconnectPhase = .idle
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

    // MARK: - Wave 16k-2c: disconnect

    /// "Desconectar" in the panel: opens the inline confirmation, no call yet.
    public func confirmDisconnect() {
        disconnectPhase = .confirming
    }

    /// Backing out of the confirmation.
    public func cancelDisconnect() {
        disconnectPhase = .idle
    }

    /// The confirmation's own "Desconectar" (spec §9.2.4): calls
    /// `DELETE /api/accounts`, then refreshes accounts so the panel/cards
    /// flip to not-connected on the server's own word, not a local guess.
    /// The panel itself stays open (Incredible: "you can reconnect anytime").
    public func disconnect() async {
        // Security review 16k-2c (MEDIUM): a fast double-tap on the confirm
        // button spawns two Tasks; both start on the MainActor and this
        // guard runs before either awaits, so the first Task's synchronous
        // prefix (guard + phase flip, no suspension point between them)
        // always finishes before the second Task gets a turn — the second
        // sees `.disconnecting` already and bails, mirroring `more()`'s own
        // `fetchingMore` guard against a doubled "Show more" tap.
        guard disconnectPhase != .disconnecting else { return }
        guard let app = selected, let account = accounts[app.slug], let service = currentService() else { return }
        disconnectPhase = .disconnecting
        let epoch = panelEpoch
        do {
            try await service.disconnect(account: account.id)
        } catch {
            guard panelEpoch == epoch else { return }
            disconnectPhase = .failed(error as? AppsFailure ?? .unexpected)
            return
        }
        guard panelEpoch == epoch else { return }
        accounts = await accountsSnapshot(service)
        NotificationCenter.default.post(name: .companionAppsChanged, object: nil)
        guard panelEpoch == epoch else { return }
        disconnectPhase = .idle
    }

    // MARK: - Wave 16k-2b: the connecting modal

    /// "+ Conectar" (card or panel): opens the modal and starts a fresh
    /// attempt. Fire-and-forget on purpose — the view reads `connectPhase`
    /// as it moves, the same idiom `open(_:)` uses for the panel.
    public func start(_ app: CatalogApp) {
        connectTask?.cancel()
        connectEpoch += 1
        let epoch = connectEpoch
        connecting = app
        connectURL = nil
        connectPoll = ConnectPoll(startedAt: now())
        connectPhase = connectPoll?.phase ?? .initiating
        connectTask = Task { [weak self] in await self?.runAttempt(for: app, epoch: epoch) }
    }

    /// "Abrir de nuevo": the same link, not a new `connectLink` call — a
    /// fresh request would be wasted (the current one is still good for 4 h).
    public func openAgain() {
        guard let connectURL else { return }
        openBrowser(connectURL)
    }

    /// "Reintentar" (only offered once timed out or failed): the old link
    /// may be spent, so this asks the function for a new one.
    public func retryConnecting() {
        guard let app = connecting else { return }
        connectTask?.cancel()
        connectEpoch += 1
        let epoch = connectEpoch
        connectURL = nil
        apply(.retry)
        connectTask = Task { [weak self] in await self?.runAttempt(for: app, epoch: epoch) }
    }

    /// "Vamos", or the sheet's close button: structured cancellation for the
    /// loop, no leaked task. `accounts` was already updated the instant the
    /// poll saw the account (below), so the panel/cards are already correct
    /// by the time this runs — this just tears the modal down.
    public func finishConnecting() {
        connectTask?.cancel()
        connectTask = nil
        connectEpoch += 1
        connecting = nil
        connectPoll = nil
        connectPhase = .initiating
        connectURL = nil
    }

    private func runAttempt(for app: CatalogApp, epoch: Int) async {
        // The task starts on the next MainActor turn, not this one: a close,
        // a switch to another app, or a same-app double-tap — all called
        // synchronously right after start(_:)/retryConnecting() — must not
        // land a failure on an attempt that is not this one any more.
        guard stillConnecting(app, epoch: epoch) else { return }
        guard let service = currentService() else {
            apply(.failure(message: AppsCopy.failure(.unreachable)))
            return
        }
        let url: URL
        do {
            url = try await service.connectLink(app: app.slug)
        } catch {
            guard stillConnecting(app, epoch: epoch) else { return }
            apply(.failure(message: AppsCopy.failure(error as? AppsFailure ?? .unexpected)))
            return
        }
        guard stillConnecting(app, epoch: epoch) else { return }
        connectURL = url
        apply(.linkObtained)
        openBrowser(url)
        guard stillConnecting(app, epoch: epoch) else { return }
        apply(.browserOpened)
        await pollLoop(for: app, service: service, epoch: epoch)
    }

    private func pollLoop(for app: CatalogApp, service: any AppsService, epoch: Int) async {
        while !Task.isCancelled, stillConnecting(app, epoch: epoch), connectPoll?.isWaiting == true {
            do {
                try await sleep(ConnectPoll.interval)
            } catch {
                return // cancelled mid-sleep: closed or replaced by a retry.
            }
            guard stillConnecting(app, epoch: epoch) else { return }
            let match: ConnectedAccount?
            do {
                match = try await service.accounts().first { $0.app == app.slug && $0.state == .connected }
            } catch {
                // A transient hiccup fetching accounts is one more miss, not
                // an abort: Pipedream itself is still fine, only this one
                // check failed, and the next tick tries again on its own.
                guard stillConnecting(app, epoch: epoch) else { return }
                apply(.accountMissing)
                continue
            }
            // The guard runs again after the network round trip: a close, a
            // switch, or a same-app retry that landed while this was in
            // flight must discard the answer, not resurrect the modal.
            guard stillConnecting(app, epoch: epoch) else { return }
            if let match {
                accounts[app.slug] = match
                // 16k-3: the voice runner re-pulls its tool cache now, not
                // when the TTL happens to expire.
                NotificationCenter.default.post(name: .companionAppsChanged, object: nil)
            }
            apply(match != nil ? .accountSeen : .accountMissing)
        }
    }

    /// Whether `app`/`epoch` is still the attempt the modal is open for.
    /// The slug alone is not enough — a same-app double-tap (Conectar twice,
    /// or Reintentar twice) shares the same slug across two generations, so
    /// every guard needs the epoch too, not just the app.
    private func stillConnecting(_ app: CatalogApp, epoch: Int) -> Bool {
        connectEpoch == epoch && connecting?.slug == app.slug
    }

    private func apply(_ event: ConnectPoll.Event) {
        guard var poll = connectPoll else { return }
        poll.handle(event, at: now())
        connectPoll = poll
        connectPhase = poll.phase
    }

    private func catalogAttempt(_ service: any AppsService, query: String, after: String?) async -> Result<CatalogPage, AppsFailure> {
        do {
            return .success(try await service.catalog(query: query, after: after))
        } catch {
            return .failure(error as? AppsFailure ?? .unexpected)
        }
    }

    /// Without accounts the catalog still lists; only the marks are missing.
    private func accountsSnapshot(_ service: any AppsService) async -> [String: ConnectedAccount] {
        do {
            return Dictionary(
                try await service.accounts().map { ($0.app, $0) },
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
            if let slug = pendingFocus, let app = apps.first(where: { $0.slug == slug }) {
                pendingFocus = nil
                open(app)
            }
        } catch {
            phase = .failed(error as? AppsFailure ?? .unexpected)
        }
    }

    /// 16k-3: the island's connect card wants this app front and center.
    /// Before the catalog is in, the wish waits for the next fetch.
    private var pendingFocus: String?

    public func focus(_ slug: String) {
        if let app = apps.first(where: { $0.slug == slug }) {
            open(app)
        } else {
            pendingFocus = slug
        }
    }

    private func currentService() -> (any AppsService)? {
        if let service { return service }
        let found: (url: URL, key: String?)?
        do {
            found = try AppsCredentials.currentKey(
                endpoint: endpoint, legacy: secrets, bound: hostSecrets, pin: launchPin, log: log)
        } catch {
            return nil
        }
        guard let url = found?.url, let key = found?.key, key.count >= Self.minimumKeyLength else { return nil }
        let made = makeService(url, key)
        service = made
        return made
    }
}
