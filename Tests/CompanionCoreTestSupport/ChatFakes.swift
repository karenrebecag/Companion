import CompanionCore
import CompanionTestKit
import Foundation
import Testing

package final class TestSecretStore: SecretStore, @unchecked Sendable {
    // The MainActor writes while actors and tasks read.
    private let lock = NSLock()
    private var values: [SecretKey: String]
    private var _failDeletes = false
    package var failDeletes: Bool {
        get { lock.withLock { _failDeletes } }
        set { lock.withLock { _failDeletes = newValue } }
    }

    package init(_ values: [SecretKey: String] = [:]) {
        self.values = values
    }

    package func read(_ key: SecretKey) throws -> String? { lock.withLock { values[key] } }

    package func write(_ key: SecretKey, value: String) throws {
        lock.withLock { values[key] = value }
    }

    package func delete(_ key: SecretKey) throws {
        try lock.withLock {
            if _failDeletes { throw SecretStoreError.denied }
            values.removeValue(forKey: key)
        }
    }
}

/// In-memory `HostSecretStore` with switches for the failure paths a real
/// Keychain has (denied, locked) so migration can be tested without one.
package final class TestHostSecretStore: HostSecretStore, @unchecked Sendable {
    package init() {}
    private let lock = NSLock()
    private var values: [String: String] = [:]
    package var failWrites = false
    package var failReads = false
    package var failDeletes = false

    private func name(_ kind: HostSecretKind, _ host: String) -> String { "\(kind.rawValue)@\(host)" }

    package func read(_ kind: HostSecretKind, host: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        if failReads { throw SecretStoreError.denied }
        return values[name(kind, host)]
    }

    package func write(_ kind: HostSecretKind, host: String, value: String) throws {
        lock.lock(); defer { lock.unlock() }
        if failWrites { throw SecretStoreError.denied }
        values[name(kind, host)] = value
    }

    package func delete(_ kind: HostSecretKind, host: String) throws {
        lock.lock(); defer { lock.unlock() }
        if failDeletes { throw SecretStoreError.denied }
        values.removeValue(forKey: name(kind, host))
    }

    package var count: Int { lock.lock(); defer { lock.unlock() }; return values.count }
}

package struct TestProbe: CapabilityProbe {
    package var available: Set<String>

    package init(available: Set<String>) { self.available = available }

    package func isAvailable(_ provider: ProviderDescriptor) async -> Bool {
        available.contains(provider.id)
    }
}

/// Wave 10b: registra qué se pidió abrir y no abre nada.
package final class FakeWorkspaceOpener: WorkspaceOpening, @unchecked Sendable {
    package var installed: [String]
    package var running: [String]
    package var failure: ContractError?
    private let opened = LockedBox<(apps: [String], urls: [URL])>(([], []))
    package var openedApps: [String] { opened.withLock { $0.apps } }
    package var openedURLs: [URL] { opened.withLock { $0.urls } }

    package init(installed: [String] = ["Safari"], running: [String] = []) {
        self.installed = installed
        self.running = running
    }

    package func openApplication(named name: String) async throws(ContractError) {
        if let failure { throw failure }
        opened.withLock { $0.apps.append(name) }
    }

    package func open(_ url: URL) async throws(ContractError) {
        if let failure { throw failure }
        opened.withLock { $0.urls.append(url) }
    }

    package func runningApplications() -> [String] { running }
    package func installedApplications() -> [String] { installed }
}

/// Wave 10a: un sensor que devuelve lo que se le dio y registra con qué
/// canales y presupuesto lo llamaron.
package final class FakeContextSensor: ContextSensing, @unchecked Sendable {
    package var context: TurnContext
    private let lock = NSLock()
    private var _calls: [(channels: ContextChannels, budget: Duration)] = []
    package var calls: [(channels: ContextChannels, budget: Duration)] {
        lock.lock(); defer { lock.unlock() }; return _calls
    }

    package init(_ context: TurnContext = TurnContext(source: .typed, focusedApp: "Safari")) {
        self.context = context
    }

    private func record(_ channels: ContextChannels, _ budget: Duration) {
        lock.lock(); _calls.append((channels, budget)); lock.unlock()
    }

    package func sense(_ channels: ContextChannels, budget: Duration) async -> TurnContext {
        record(channels, budget)
        var ctx = context
        ctx.timestamp = Date()
        return ctx
    }
}

/// Wave 10c: an approvals actor in miniature — parks the request until the
/// test (or the view model) resolves it, and can answer from "memory".
package actor FakeApprovals: ApprovalsProvider {
    private var pending: [String: CheckedContinuation<ApprovalResponse, Never>] = [:]
    package private(set) var requested: [ApprovalRequest] = []
    package private(set) var resolutions: [(id: String, approved: Bool, remember: Bool)] = []
    package var memory: [String: Bool]

    package init(memory: [String: Bool] = [:]) { self.memory = memory }

    package func request(_ approval: ApprovalRequest) async -> ApprovalResponse {
        requested.append(approval)
        let id = approval.requestId
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                pending[id] = continuation
            }
        } onCancel: {
            Task { _ = await self.resolve(requestId: id, approved: false) }
        }
    }

    package func resolve(requestId: String, approved: Bool) async -> Bool {
        await resolve(requestId: requestId, approved: approved, remember: false)
    }

    package func resolve(requestId: String, approved: Bool, remember: Bool) async -> Bool {
        resolutions.append((requestId, approved, remember))
        guard let continuation = pending.removeValue(forKey: requestId) else { return false }
        continuation.resume(returning: ApprovalResponse(
            requestId: requestId, approved: approved, remember: remember))
        return true
    }

    package func remembered(_ approval: ApprovalRequest) async -> Bool? {
        ApprovalKey.from(approval).flatMap { memory[$0.description] }
    }

    /// The first request still waiting, if any.
    package var waiting: ApprovalRequest? { requested.first { pending[$0.requestId] != nil } }
}

/// In-memory SecretStore for the harness. Production lives in Services.
package final class MemorySecretStore: SecretStore, @unchecked Sendable {
    package init() {}
    private var values: [String: String] = [:]

    package func read(_ key: SecretKey) throws -> String? {
        values[key.rawValue]
    }

    package func write(_ key: SecretKey, value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { throw SecretStoreError.emptyValue }
        values[key.rawValue] = trimmed
    }

    package func delete(_ key: SecretKey) throws {
        values.removeValue(forKey: key.rawValue)
    }
}

package final class MemoryConversationStore: ConversationStoring, @unchecked Sendable {
    package init() {}
    private var records: [String: ConversationRecord] = [:]

    package func list() throws -> [ConversationMeta] {
        records.values.map {
            ConversationMeta(id: $0.id, title: $0.title, updatedAt: $0.updatedAt)
        }
    }

    package func save(_ record: ConversationRecord) throws {
        records[record.id] = record
    }

    package func load(_ id: String) throws -> ConversationRecord? {
        records[id]
    }
}

package final class FakeChatProvider: ChatProvider, @unchecked Sendable {
    package var replies: [Result<[ChatDelta], Error>]
    package var verifyError: Error?
    package private(set) var toolsSeen: [ToolSpec] = []
    package private(set) var histories: [[Turn]] = []
    package private(set) var verifyKeys: [String] = []
    package private(set) var verifyProviders: [ProviderDescriptor] = []
    private var index = 0

    package init(replies: [Result<[ChatDelta], Error>] = [], verifyError: Error? = nil) {
        self.replies = replies
        self.verifyError = verifyError
    }

    package func stream(_ history: [Turn], tools: [ToolSpec])
        -> AsyncThrowingStream<ChatDelta, Error>
    {
        toolsSeen = tools
        histories.append(history)
        let reply = index < replies.count ? replies[index] : .success([])
        index += 1
        return AsyncThrowingStream { continuation in
            let work = Task.detached {
                switch reply {
                case .success(let deltas):
                    for delta in deltas { continuation.yield(delta) }
                    continuation.finish()
                case .failure(let error):
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in work.cancel() }
        }
    }

    package func verify(_ key: String, provider: ProviderDescriptor) async throws {
        verifyKeys.append(key)
        verifyProviders.append(provider)
        if let verifyError { throw verifyError }
    }
}

package final class MemoryAttachments: AttachmentStoring, @unchecked Sendable {
    package init() {}
    package func adopt(_ source: URL, conversationId: String) throws -> AttachmentRef {
        AttachmentRef(
            name: source.lastPathComponent, path: source.path,
            kind: AttachmentPolicy.kind(forExtension: source.pathExtension),
            byteCount: 4)
    }

    package func adopt(imageData: Data, name: String, conversationId: String) throws -> AttachmentRef {
        AttachmentRef(name: name, path: "/tmp/\(name)", kind: .image, byteCount: imageData.count)
    }

    package func restore(path: String) -> AttachmentRef? { nil }
    package func discard(_ ref: AttachmentRef) {}
    package func payload(for ref: AttachmentRef) -> AttachmentPayload? { nil }
}

package struct ResolvedCall: Equatable {
    package let id: String
    package let approved: Bool

    package init(id: String, approved: Bool) {
        self.id = id
        self.approved = approved
    }
}

package final class RecordingSubmitter: JobSubmitter, @unchecked Sendable {
    package init() {}
    private let lock = NSLock()
    private var calls: [ResolvedCall] = []
    package var resolved: [ResolvedCall] { lock.withLock { calls } }

    package func submit(
        _ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        JobResult(output: "ok", isError: false)
    }
    package func cancel() async {}
    package func cancel(job id: JobID) async { await cancel() }
    package func submit(
        _ handoff: Handoff, as id: JobID, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try await submit(handoff, events: events)
    }
    package func resolveApproval(requestId: String, approved: Bool) async {
        lock.withLock { calls.append(ResolvedCall(id: requestId, approved: approved)) }
    }
    package var isBusy: Bool { get async { false } }
}

package final class WatchfulSubmitter: JobSubmitter, @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    private var _released: (() -> Void)?
    package let output: String

    package init(output: String = "informe") { self.output = output }

    package var cancelled: Bool {
        lock.lock(); defer { lock.unlock() }; return _cancelled
    }

    package func submit(
        _ handoff: Handoff, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        events.yield(.stepStarted(tool: "run_shell", summary: "df -h"))
        // Espera como un encargo de verdad, pero ACOTADA: un test que no lo
        // cancela dejaba esta tarea girando el resto de la suite y volvia
        // intermitentes a los tests que dependen de temporizadores.
        for _ in 0 ..< 200 where !cancelled {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw CancellationError()
    }

    package func cancel() async { markCancelled() }

    private func markCancelled() {
        lock.lock(); defer { lock.unlock() }
        _cancelled = true
    }
    package func cancel(job id: JobID) async { await cancel() }
    package func submit(
        _ handoff: Handoff, as id: JobID, events: AsyncStream<JobEvent>.Continuation
    ) async throws -> JobResult {
        try await submit(handoff, events: events)
    }
    package func resolveApproval(requestId: String, approved: Bool) async {}
    private var _remembered: [Bool] = []
    /// Wave 10c: what the sheet asked to remember, per answer.
    package var remembered: [Bool] { lock.lock(); defer { lock.unlock() }; return _remembered }
    private var _resolved: [(requestId: String, approved: Bool)] = []
    /// Which request each answer reached, so a test can tell A's answer from B's.
    package var resolved: [(requestId: String, approved: Bool)] {
        lock.lock(); defer { lock.unlock() }; return _resolved
    }
    package func resolveApproval(requestId: String, approved: Bool, remember: Bool) async {
        record(remember, requestId: requestId, approved: approved)
    }
    private func record(_ remember: Bool, requestId: String, approved: Bool) {
        lock.lock(); defer { lock.unlock() }
        _remembered.append(remember)
        _resolved.append((requestId, approved))
    }
    package var isBusy: Bool { get async { false } }
}

/// Every port call arrives on a Task of its own; the counters sit behind a
/// lock so two calls in a row never lose one (a lost `+= 1` read as a flake).
package final class RecordingVoice: VoiceControlling, @unchecked Sendable {
    package init() {}
    private let lock = NSLock()
    private var _speeds: [Double] = []
    package var speeds: [Double] { lock.withLock { _speeds } }
    package func setSpeed(_ speed: Double) async { lock.withLock { _speeds.append(speed) } }
    package func setVolume(_ volume: Double) async {}

    private var counts = (started: 0, advanced: 0, hungUp: 0, muteToggles: 0)
    private var _muted = false
    package var started: Int { lock.withLock { counts.started } }
    package var advanced: Int { lock.withLock { counts.advanced } }
    package var hungUp: Int { lock.withLock { counts.hungUp } }
    package var muteToggles: Int { lock.withLock { counts.muteToggles } }
    package var muted: Bool { lock.withLock { _muted } }
    private let snapBox = StreamBox<TurnSnapshot>()
    private let levelBox = StreamBox<VoiceLevels>()
    package var snapshots: AsyncStream<TurnSnapshot> { snapBox.stream }
    package var levels: AsyncStream<VoiceLevels> { levelBox.stream }

    package func start() async { lock.withLock { counts.started += 1 } }
    package func advance() async { lock.withLock { counts.advanced += 1 } }
    package func hangUp() async { lock.withLock { counts.hungUp += 1 } }
    private var _closed: [String] = []
    package var closedRequests: [String] { lock.withLock { _closed } }
    package func approvalClosed(requestId: String) async { lock.withLock { _closed.append(requestId) } }
    private var _fronts: [String?] = []
    package var fronts: [String?] { lock.withLock { _fronts } }
    package func approvalFront(requestId: String?) async { lock.withLock { _fronts.append(requestId) } }
    package func toggleMute() async { lock.withLock { counts.muteToggles += 1; _muted.toggle() } }
    private var _pushed: [AttachmentRef] = []
    package var pushed: [AttachmentRef] { lock.withLock { _pushed } }
    package func push(attachment: AttachmentRef) async { lock.withLock { _pushed.append(attachment) } }
    /// Wave 12b: the hold port, in call order.
    private var _calls: [String] = []
    package var calls: [String] { lock.withLock { _calls } }
    private func record(_ call: String) { lock.withLock { _calls.append(call) } }
    package func hold() async { record("hold") }
    package func holdProvisionally() async { record("holdProvisionally") }
    package func confirmHold() async { record("confirmHold") }
    package func release() async { record("release") }
    package func discard() async { record("discard") }
    package func interrupt() async { record("interrupt") }
    package func yieldSnapshot(_ snapshot: TurnSnapshot) { snapBox.yield(snapshot) }
    package func yieldLevels(_ value: VoiceLevels) { levelBox.yield(value) }
    package func finish() { snapBox.finish(); levelBox.finish() }
}

package struct ScriptedDecision: DecisionProvider {
    package var body: @Sendable (DecisionQuestion) -> DecisionAnswer?

    package init(body: @escaping @Sendable (DecisionQuestion) -> DecisionAnswer?) { self.body = body }

    package func answer(_ question: DecisionQuestion) async -> DecisionAnswer? {
        body(question)
    }
}
