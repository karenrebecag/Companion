import CompanionCore
import Foundation

/// The user's own MCP servers as parent tools (Apps > "Tus servidores MCP"),
/// on every lane that carries the connected apps: typed chat and both voice
/// modes. Listing runs off the turn's path; a call is one round trip after its
/// sheet. A server that does not answer is skipped and logged, and never holds
/// up a turn.
package final class OwnMCPToolRunner: ParentToolExecuting, @unchecked Sendable {
    /// A server that was down at launch comes back without a restart.
    static let refreshTTL: TimeInterval = 300

    private let lock = NSLock()
    private var entries: [OwnMCPTools.Entry] = []
    /// Tool names the sheet granted, each good for one call (execute spends it).
    private var grants: Set<String> = []
    private var tainted = false
    private var lastRefresh: TimeInterval = 0

    private let servers: @Sendable () -> [MCPServerConfig]
    private let client: OwnMCPClient
    private let now: @Sendable () -> TimeInterval

    /// `servers` is read at each refresh, so an edit on the Apps page takes
    /// effect at the refresh that the page's change triggers.
    package init(
        servers: @escaping @Sendable () -> [MCPServerConfig],
        client: OwnMCPClient = OwnMCPClient(),
        now: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 }
    ) {
        self.servers = servers
        self.client = client
        self.now = now
    }

    /// Lists every configured server again. Off the turn's path: at launch,
    /// when the Apps page changes, and by TTL from a turn.
    package func refresh() async {
        var listed: [OwnMCPTools.Listed] = []
        for server in servers() {
            do {
                let tools = try await client.listTools(server)
                listed.append(OwnMCPTools.Listed(server: server, tools: tools))
            } catch {
                Log.app("mcp: server «\(server.label)» did not connect; skipped")
            }
        }
        let count = store(OwnMCPTools.catalog(listed))
        Log.app("mcp: \(count) own tool(s) from \(listed.count) server(s)")
    }

    private func store(_ fresh: [OwnMCPTools.Entry]) -> Int {
        lock.lock()
        defer { lock.unlock() }
        entries = fresh
        lastRefresh = now()
        return fresh.count
    }

    package func specs(_ language: AppLanguage) -> [ToolSpec] {
        lock.lock()
        defer { lock.unlock() }
        return entries.map { entry in
            ToolSpec(
                name: entry.name, description: entry.description,
                properties: [], required: [],
                rawParametersJSON: entry.schemaJSON,
                isConnectedApp: true)
        }
    }

    package func handles(_ name: String) -> Bool {
        lookup(name) != nil
    }

    /// Every call asks. A server's own word that a tool only reads
    /// (readOnlyHint) is not a reason to skip the sheet: the file cannot relax
    /// it (20c D2), and the server is not the one judging its tools.
    package func approval(for call: ToolCallRef, said: String) -> ApprovalRequest? {
        guard let entry = lookup(call.name) else { return nil }
        return ApprovalRequest(
            requestId: UUID().uuidString,
            toolName: entry.name,
            summary: "\(entry.remoteName) · \(entry.server.label)",
            inputJSON: call.arguments,
            isMCP: true)
    }

    package func granted(_ request: ApprovalRequest) {
        guard request.isMCP else { return }
        lock.lock()
        defer { lock.unlock() }
        if entries.contains(where: { $0.name == request.toolName }) {
            grants.insert(request.toolName)
        }
    }

    package func withdraw(_ call: ToolCallRef) {
        lock.lock()
        defer { lock.unlock() }
        grants.remove(call.name)
    }

    package func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        guard let entry = lookup(name) else {
            return .failed(.notFound("unknown MCP tool: \(name)"))
        }
        let label = entry.server.label
        guard consumeGrant(name) else {
            return .failed(
                ContractError(code: "approval_required", message: "\(name) needs the approval sheet first"),
                target: label, tool: name)
        }
        do {
            let result = try await client.callTool(
                entry.server, name: entry.remoteName, argumentsJSON: argumentsJSON)
            markTainted()
            return ParentToolOutcome(
                ok: !result.isError,
                output: OwnMCPTools.result(server: label, text: result.text),
                target: label, tool: name)
        } catch {
            return .failed(
                ContractError(code: "mcp_unreachable", message: "\(label): no answer"),
                target: label, tool: name)
        }
    }

    /// A server's answer is text from outside the Mac: once a turn has read
    /// one, a standing "siempre" never settles a sheet in that turn.
    package func turnIsTainted() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return tainted
    }

    /// Grants are left alone here: a parked sheet may still be answered after
    /// a new turn begins, and withdraw or execute is what retires a grant.
    package func beginTurn() {
        lock.lock()
        defer { lock.unlock() }
        tainted = false
    }

    package func noteTurn(_ said: String) {
        refreshIfStale()
    }

    package func noteChoiceTurn() {
        refreshIfStale()
    }

    private func refreshIfStale() {
        lock.lock()
        let stale = now() - lastRefresh > Self.refreshTTL
        lock.unlock()
        guard stale else { return }
        Task.detached(priority: .utility) { [weak self] in await self?.refresh() }
    }

    private func lookup(_ name: String) -> OwnMCPTools.Entry? {
        lock.lock()
        defer { lock.unlock() }
        return entries.first { $0.name == name }
    }

    private func consumeGrant(_ name: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return grants.remove(name) != nil
    }

    private func markTainted() {
        lock.lock()
        defer { lock.unlock() }
        tainted = true
    }
}
