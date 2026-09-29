import CompanionCore
import Foundation

/// 16k-3 (spec §2.5, §3): the connected apps' tools as parent tools, so
/// they reach the brain on every path — typed chat, the classic hold and
/// realtime — through the one seam all three already call
/// (`ParentToolExecuting`). Writes pass the approval sheet; reads run
/// silently; the wire work happens in the function (`/api/tools/call`),
/// never here.
///
/// The tool list follows the app the turn names (spec §5: a connected app
/// can carry dozens of tools, and every app's tools on every turn would
/// drown the model's context). Before any turn is noted — the realtime
/// session, whose tool list is fixed at socket open — the whole connected
/// set is offered.
public final class AppToolRunner: ParentToolExecuting, @unchecked Sendable {
    struct ConnectedTools: Sendable {
        let slug: String
        let name: String
        let actions: [AppAction]
    }

    private enum Scope {
        case allConnected
        case app(String)
        case none
    }

    /// Accounts and tools re-pull after this long, off the turn's path.
    static let refreshTTL: TimeInterval = 300

    private let lock = NSLock()
    private var cache: [ConnectedTools] = []
    private var scope: Scope = .allConnected
    /// True after the first successful refresh: before that, "not in the
    /// cache" means "not loaded yet", never "not connected" (review 16k-3
    /// M2 — a wrong card would also burn the once-per-launch suggestion).
    private var loaded = false
    /// Tool names the sheet granted, each good for ONE call: execute
    /// consumes them (review 16k-3 M1/F-B), and a new turn starts clean.
    private var grants: Set<String> = []
    /// Slugs already suggested: the connect card nudges once per launch,
    /// never on every mention.
    private var suggestedSlugs: Set<String> = []
    private var lastRefresh: TimeInterval = 0

    private let service: @Sendable () -> (any AppsService)?
    /// The catalog names a mention can match when the app is NOT connected
    /// (the seed: the live catalog needs no candidates, connected accounts
    /// carry their own names).
    private let catalog: [AppMention.Candidate]
    private let suggest: (@Sendable (String, String) -> Void)?
    private let now: @Sendable () -> TimeInterval

    public init(
        service: @escaping @Sendable () -> (any AppsService)?,
        catalog: [AppMention.Candidate],
        suggest: (@Sendable (String, String) -> Void)?,
        now: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }
    ) {
        self.service = service
        self.catalog = catalog
        self.suggest = suggest
        self.now = now
    }

    /// Pulls the connected accounts and each one's tools. Called off the
    /// turn's path: at launch, when the Apps page changes something, and
    /// by TTL — `specs` and `execute` only ever read the cache.
    public func refresh() async {
        guard let service = service() else { return }
        let accounts: [ConnectedAccount]
        do {
            accounts = try await service.accounts()
        } catch {
            Log.app("apps: could not list accounts for the runner")
            // The attempt still counts against the TTL: while the function
            // is down, turns must not each spawn a new try (review M3).
            stampAttempt()
            return
        }
        var fresh: [ConnectedTools] = []
        for account in accounts where account.state == .connected {
            do {
                let actions = try await service.tools(app: account.app)
                fresh.append(ConnectedTools(
                    slug: account.app, name: Self.displayName(account.app),
                    actions: actions))
            } catch {
                Log.app("apps: could not list tools of \(account.app)")
            }
        }
        store(fresh)
    }

    private func store(_ fresh: [ConnectedTools]) {
        lock.lock()
        cache = fresh
        loaded = true
        lastRefresh = now()
        lock.unlock()
    }

    private func stampAttempt() {
        lock.lock()
        lastRefresh = now()
        lock.unlock()
    }

    public func noteTurn(_ said: String) {
        lock.lock()
        grants.removeAll()
        let ready = loaded
        let connected = cache.map { AppMention.Candidate(slug: $0.slug, name: $0.name) }
        let connectedSlugs = Set(cache.map(\.slug))
        let stale = now() - lastRefresh > Self.refreshTTL
        if let slug = AppMention.match(said, in: connected) {
            scope = .app(slug)
            lock.unlock()
        } else {
            scope = .none
            // Named but not connected: the island offers the way, once —
            // and only once the cache has really loaded, or "connected"
            // and "not loaded yet" are indistinguishable (M2).
            let candidates = catalog.filter { !connectedSlugs.contains($0.slug) }
            if ready, let slug = AppMention.match(said, in: candidates),
               !suggestedSlugs.contains(slug) {
                suggestedSlugs.insert(slug)
                let name = candidates.first { $0.slug == slug }?.name ?? slug
                lock.unlock()
                suggest?(slug, name)
            } else {
                lock.unlock()
            }
        }
        if stale {
            Task.detached(priority: .utility) { [weak self] in await self?.refresh() }
        }
    }

    public func specs(_ language: AppLanguage) -> [ToolSpec] {
        lock.lock()
        defer { lock.unlock() }
        let apps: [ConnectedTools] =
            switch scope {
            case .allConnected: cache
            case .app(let slug): cache.filter { $0.slug == slug }
            case .none: []
            }
        // The narrowing a turn set applies to the request built right after
        // its noteTurn, then dies: the runner is shared by chat, classic
        // and realtime, and a leftover `.none` from a chat turn was
        // starving realtime sessions opened later (H1, review 16k-3). The
        // cost: a chat turn's LATER tool rounds see the full set again —
        // more budget, never fewer tools.
        scope = .allConnected
        return apps.flatMap { app in
            app.actions.map { action in
                ToolSpec(
                    name: action.slug,
                    description: action.description.isEmpty
                        ? action.name : action.description,
                    properties: [], required: [],
                    rawParametersJSON: action.schemaJSON)
            }
        }
    }

    /// Ownership by construction: the function's contract requires every
    /// tool name to start with its app's slug and a dash (companion-apps
    /// lib/validate.mjs), so the name alone says whose it is. Scope does
    /// not gate here: a call the model makes is executed if the tool is
    /// real — the approval gate, not the listing, is the security line.
    public func handles(_ name: String) -> Bool {
        lookup(name) != nil
    }

    public func approval(for call: ToolCallRef, said: String) -> ApprovalRequest? {
        guard let (app, action) = lookup(call.name), action.group != .leer else { return nil }
        return ApprovalRequest(
            requestId: UUID().uuidString,
            toolName: ApprovalCopy.appToolPrefix + "\(app.slug):\(call.name)",
            summary: "\(action.name) · \(app.name)",
            inputJSON: call.arguments)
    }

    public func granted(_ request: ApprovalRequest) {
        // "app:<slug>:<tool>", split once: a tool name is never re-split on
        // a ":" it might carry (F-A, security review 16k-3 — the wire also
        // rejects such names now, this is the second belt).
        guard request.toolName.hasPrefix(ApprovalCopy.appToolPrefix) else { return }
        let rest = request.toolName.dropFirst(ApprovalCopy.appToolPrefix.count)
        let parts = rest.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return }
        lock.lock()
        grants.insert(String(parts[1]))
        lock.unlock()
    }

    public func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        guard let (app, action) = lookup(name) else {
            return .failed(.notFound("unknown app tool: \(name)"))
        }
        let approved: Bool
        if action.group == .leer {
            approved = false
        } else {
            // Belt and braces: the gates always ran by now, and the
            // function refuses an unapproved write on its own too. The
            // grant is spent here — one sheet, one call (M1, like
            // ApprovalTickets for the deliverables).
            guard consumeGrant(name) else {
                return .failed(ContractError(
                    code: "approval_required",
                    message: "\(name) needs the approval sheet first"))
            }
            approved = true
        }
        guard let service = service() else {
            return .failed(ContractError(
                code: "not_configured",
                message: "the companion-apps function is not configured"))
        }
        do {
            let result = try await service.call(
                app: app.slug, tool: name, argumentsJSON: argumentsJSON, approved: approved)
            return ParentToolOutcome(
                ok: !result.isError, output: result.text, target: app.name, tool: name)
        } catch {
            let failure = error as? AppsFailure ?? .unexpected
            return .failed(
                ContractError(code: "app_unreachable", message: "\(app.name): \(failure)"),
                target: app.name, tool: name)
        }
    }

    private func consumeGrant(_ name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return grants.remove(name) != nil
    }

    private func lookup(_ name: String) -> (app: ConnectedTools, action: AppAction)? {
        lock.lock()
        defer { lock.unlock() }
        for app in cache where name.hasPrefix(app.slug + "-") {
            if let action = app.actions.first(where: { $0.slug == name }) {
                return (app, action)
            }
        }
        return nil
    }

    /// "slack_v2" → "Slack V2" is worse than "Slack": the version suffix
    /// is Pipedream's, not the brand's.
    private static func displayName(_ slug: String) -> String {
        let words = slug.split(whereSeparator: { $0 == "_" || $0 == "-" })
            .filter { $0.range(of: "^v[0-9]+$", options: .regularExpression) == nil }
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return words.isEmpty ? slug : words.joined(separator: " ")
    }
}

/// One seam, several runners: the three paths keep calling a single
/// `ParentToolExecuting`; this fans out. Routing is by `handles`, first
/// taker wins — the parent's own tools come first by construction.
public struct CompositeParentTools: ParentToolExecuting, Sendable {
    private let runners: [any ParentToolExecuting]

    public init(_ runners: [any ParentToolExecuting]) {
        self.runners = runners
    }

    public func specs(_ language: AppLanguage) -> [ToolSpec] {
        runners.flatMap { $0.specs(language) }
    }

    public func handles(_ name: String) -> Bool {
        runners.contains { $0.handles(name) }
    }

    public func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        guard let runner = runners.first(where: { $0.handles(name) }) else {
            return .failed(.notFound("unknown tool: \(name)"))
        }
        return await runner.execute(name: name, argumentsJSON: argumentsJSON)
    }

    public func approval(for call: ToolCallRef, said: String) -> ApprovalRequest? {
        guard let runner = runners.first(where: { $0.handles(call.name) }) else {
            return ParentToolGate.approval(for: call, said: said)
        }
        return runner.approval(for: call, said: said)
    }

    public func granted(_ request: ApprovalRequest) {
        for runner in runners { runner.granted(request) }
    }

    public func beginTurn() {
        for runner in runners { runner.beginTurn() }
    }

    public func noteTurn(_ said: String) {
        for runner in runners { runner.noteTurn(said) }
    }

    public func unavailability(for name: String) -> String? {
        for runner in runners {
            if let reason = runner.unavailability(for: name) { return reason }
        }
        return nil
    }
}
