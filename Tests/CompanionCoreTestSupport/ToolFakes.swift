import CompanionCore
import CompanionTestKit
import Foundation
import Testing

package final class FakeScreen: ScreenActing, @unchecked Sendable {
    private let lock = NSLock()
    package var nodes: [ScanNode]
    package var generation = 0
    package var route: ClickRoute = .press
    package private(set) var clicks: [(node: Int, pid: Int32)] = []
    package private(set) var scrolls: [(node: Int?, direction: ScrollDirection)] = []
    package private(set) var menus: [[String]] = []
    package private(set) var pressedTitles: [String] = []
    /// The titles the last path step can match, resolved like the adapter
    /// does (`WindowTitles.bestMatch`); nil means the path is exact.
    package var menuTitles: [String]?
    /// Titles of menu items that are greyed out right now.
    package var disabledMenus: Set<String> = []

    package init(_ nodes: [ScanNode]) { self.nodes = nodes }

    package func walk(pid: Int32) -> ScreenWalk? {
        lock.withLock {
            generation += 1
            return ScreenWalk(nodes: nodes, partial: false, window: "Ventana", generation: generation)
        }
    }

    package func click(node: Int, generation: Int, pid: Int32, label: String) -> ClickOutcome {
        lock.withLock {
            guard generation == self.generation else { return .stale }
            clicks.append((node, pid))
            return .clicked(route)
        }
    }

    package func scroll(node: Int?, generation: Int, direction: ScrollDirection, pid: Int32) -> Bool {
        lock.withLock { scrolls.append((node, direction)) }
        return true
    }

    package func menuTitle(path: [String], pid: Int32) -> String? {
        lock.withLock {
            guard let last = path.last else { return nil }
            guard let titles = menuTitles else { return last }
            return WindowTitles.bestMatch(titles, for: last).map { titles[$0] }
        }
    }

    package func menuEnabled(path: [String], pid: Int32) -> Bool {
        guard let title = menuTitle(path: path, pid: pid) else { return true }
        return lock.withLock { !disabledMenus.contains(title) }
    }

    package func menu(path: [String], pid: Int32, expecting: String) -> String? {
        guard menuTitle(path: path, pid: pid) == expecting, menuEnabled(path: path, pid: pid) else { return nil }
        lock.withLock {
            menus.append(path)
            pressedTitles.append(expecting)
        }
        return expecting
    }
}

package final class FakeSkillReader: SkillReading, @unchecked Sendable {
    package var cards: [SkillCard]
    package var bodies: [String: String]
    package init(cards: [SkillCard], bodies: [String: String]) { self.cards = cards; self.bodies = bodies }
    package func catalog() -> [SkillCard] { cards }
    package func body(named name: String) -> String? { bodies[name] }
}

/// Scripted `ParentToolExecuting`: two fixed specs, a configurable set of
/// handled names, a scripted per-call approval and outcome, and recorders
/// for everything `BridgeSession` calls. Lock-guarded: the actor calls it
/// off the main thread.
package final class FakeParentTools: ParentToolExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private var handledNames: Set<String>
    private var scriptedApproval: ApprovalRequest?
    private var scriptedOutcome: ParentToolOutcome
    private var _executeCalls: [(name: String, argumentsJSON: String)] = []
    private var _grantedCalls: [ApprovalRequest] = []
    private var _beginTurnCount = 0
    private var _saidSeen: [String] = []
    private var unavailable: [String: String]

    private let specNames: [String]
    private let realSpecs: [ToolSpec]

    /// `specs` are real schemas offered as-is, for a test whose calls carry
    /// arguments the bridge now checks against them.
    package init(
        handledNames: Set<String> = ["look", "click", "type_text", "open_app"],
        specNames: [String] = ["look", "click"],
        specs: [ToolSpec] = [],
        unavailable: [String: String] = [:],
        scriptedOutcome: ParentToolOutcome = ParentToolOutcome(ok: true, output: "ok", target: "Safari")
    ) {
        self.handledNames = handledNames
        self.specNames = specNames
        realSpecs = specs
        self.unavailable = unavailable
        self.scriptedOutcome = scriptedOutcome
    }

    package func specs(_ language: AppLanguage) -> [ToolSpec] {
        specNames.map { ToolSpec(name: $0, description: $0, properties: [], required: []) } + realSpecs
    }

    package func handles(_ name: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return handledNames.contains(name)
    }

    package func unavailability(for name: String) -> String? {
        lock.withLock { unavailable[name] }
    }

    package func setUnavailable(_ value: [String: String]) {
        lock.withLock { unavailable = value }
    }

    package func execute(name: String, argumentsJSON: String) async -> ParentToolOutcome {
        // `.lock()/.unlock()` are noasync; `withLock` is the async-safe form.
        lock.withLock {
            _executeCalls.append((name, argumentsJSON))
            return scriptedOutcome
        }
    }

    package func approval(for call: ToolCallRef, said: String) -> ApprovalRequest? {
        lock.lock()
        _saidSeen.append(said)
        let request = scriptedApproval
        lock.unlock()
        return request
    }

    package func granted(_ request: ApprovalRequest) {
        lock.lock(); _grantedCalls.append(request); lock.unlock()
    }

    package func beginTurn() {
        lock.lock(); _beginTurnCount += 1; lock.unlock()
    }

    package var executeCalls: [(name: String, argumentsJSON: String)] {
        lock.lock(); defer { lock.unlock() }; return _executeCalls
    }

    package var grantedCalls: [ApprovalRequest] {
        lock.lock(); defer { lock.unlock() }; return _grantedCalls
    }

    package var beginTurnCount: Int {
        lock.lock(); defer { lock.unlock() }; return _beginTurnCount
    }

    package var saidSeen: [String] {
        lock.lock(); defer { lock.unlock() }; return _saidSeen
    }

    package func setScriptedApproval(_ request: ApprovalRequest?) {
        lock.lock(); scriptedApproval = request; lock.unlock()
    }

    package func setScriptedOutcome(_ outcome: ParentToolOutcome) {
        lock.lock(); scriptedOutcome = outcome; lock.unlock()
    }
}

/// Scripted `ApprovalsProvider`: a default answer, an optional per-tool
/// override (the session-open sheet and a per-call gate ask different
/// tool names, so they can be scripted independently), a scripted
/// `remembered` decision, every request it saw, and every resolution
/// (including one `stop()`'s withdrawal triggers, not just an in-test
/// script). `park: true` makes `request` suspend until `resolve` is called
/// from outside — the shape `BridgeSession.stop()` withdraws.
package final class ScriptedApprovals: ApprovalsProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var defaultAnswer: Bool
    private var answersByTool: [String: Bool] = [:]
    private var rememberedAnswer: Bool?
    private var park: Bool
    private var parkedTools: Set<String> = []
    private var timedOutIds: Set<String> = []
    private var pending: [String: CheckedContinuation<Bool, Never>] = [:]
    private var _requests: [ApprovalRequest] = []
    private var _resolutions: [(requestId: String, approved: Bool)] = []

    package init(answer: Bool = true, remembered: Bool? = nil, park: Bool = false) {
        self.defaultAnswer = answer
        self.rememberedAnswer = remembered
        self.park = park
    }

    package func request(_ approval: ApprovalRequest) async -> ApprovalResponse {
        lock.withLock { _requests.append(approval) }
        let approved: Bool
        if park || lock.withLock({ parkedTools.contains(approval.toolName) }) {
            approved = await withCheckedContinuation { continuation in
                lock.withLock { pending[approval.requestId] = continuation }
            }
        } else {
            approved = lock.withLock { answersByTool[approval.toolName] ?? defaultAnswer }
        }
        let timedOut = lock.withLock { timedOutIds.contains(approval.requestId) }
        return ApprovalResponse(requestId: approval.requestId, approved: approved, timedOut: timedOut)
    }

    /// The real `Approvals` deadline: a denial nobody typed.
    package func timeOut(requestId: String) async -> Bool {
        lock.withLock { _ = timedOutIds.insert(requestId) }
        return await resolve(requestId: requestId, approved: false)
    }

    package func setPark(forTool tool: String) {
        lock.withLock { _ = parkedTools.insert(tool) }
    }

    package func resolve(requestId: String, approved: Bool) async -> Bool {
        let continuation = lock.withLock { pending.removeValue(forKey: requestId) }
        lock.withLock { _resolutions.append((requestId, approved)) }
        guard let continuation else { return false }
        continuation.resume(returning: approved)
        return true
    }

    /// Mirrors the real `Approvals` actor: no key, no memory. After the
    /// H2 fix, `bridge_session` never has a key (`ApprovalKey.from` returns
    /// nil for it), so this returns nil for it regardless of the scripted
    /// `rememberedAnswer` — the fake would lie about a security fix if it
    /// answered a tool the real actor can never answer.
    package func remembered(_ approval: ApprovalRequest) async -> Bool? {
        guard ApprovalKey.from(approval) != nil else { return nil }
        return lock.withLock { rememberedAnswer }
    }

    package var requests: [ApprovalRequest] {
        lock.lock(); defer { lock.unlock() }; return _requests
    }

    package var resolutions: [(requestId: String, approved: Bool)] {
        lock.lock(); defer { lock.unlock() }; return _resolutions
    }

    package func setAnswer(_ value: Bool, forTool tool: String) {
        lock.lock(); answersByTool[tool] = value; lock.unlock()
    }
}

package final class FakeAccessibility: AccessibilityChecking, @unchecked Sendable {
    package var trusted: Bool
    package private(set) var requests = 0
    package init(trusted: Bool) { self.trusted = trusted }
    package func isTrusted() -> Bool { trusted }
    package func request() -> Bool { requests += 1; return trusted }
}

/// `<root>/real/home` como HOME de prueba. `root` vive en el temp del
/// sistema, que en macOS ya es un symlink (`/var` → `/private/var`), así que
/// hasta el caso feliz ejercita la canonicalización.
package struct HomeFixture {
    package let root: URL
    package let home: URL
    /// realpath(3), like the policy: Foundation's resolver drops `/private`.
    package var canonical: URL {
        guard let real = realpath(home.path, nil) else { return home }
        defer { free(real) }
        return URL(fileURLWithPath: String(cString: real))
    }

    package init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("parent-home-\(UUID().uuidString)")
        home = root.appendingPathComponent("real/home")
        try FileManager.default.createDirectory(
            at: home, withIntermediateDirectories: true)
    }

    package func mkdir(_ rel: String) throws {
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(rel), withIntermediateDirectories: true)
    }

    package func touch(_ rel: String) throws {
        try Data("x".utf8).write(to: home.appendingPathComponent(rel))
    }
}

package actor DenyingApprovals: ApprovalsProvider {
    package init() {}
    package func request(_ approval: ApprovalRequest) async -> ApprovalResponse {
        ApprovalResponse(requestId: approval.requestId, approved: false)
    }

    package func resolve(requestId: String, approved: Bool) async -> Bool {
        true
    }
}

package actor ApprovingApprovals: ApprovalsProvider {
    package init() {}
    package func request(_ approval: ApprovalRequest) async -> ApprovalResponse {
        ApprovalResponse(requestId: approval.requestId, approved: true)
    }

    package func resolve(requestId: String, approved: Bool) async -> Bool {
        true
    }
}

extension AsyncStream where Element == JobEvent {
    /// Drains without observing: some tests only care about the result.
    package func ignore() {
        let stream = self
        Task { for await _ in stream {} }
    }
}
