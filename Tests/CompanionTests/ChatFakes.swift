import CompanionCore
import CompanionServices
import Foundation
import Testing

final class TestSecretStore: SecretStore, @unchecked Sendable {
    private var values: [SecretKey: String]

    init(_ values: [SecretKey: String] = [:]) {
        self.values = values
    }

    func read(_ key: SecretKey) throws -> String? { values[key] }

    func write(_ key: SecretKey, value: String) throws {
        values[key] = value
    }

    func delete(_ key: SecretKey) throws {
        values.removeValue(forKey: key)
    }
}

struct TestProbe: CapabilityProbe {
    var available: Set<String>

    func isAvailable(_ provider: ProviderDescriptor) async -> Bool {
        available.contains(provider.id)
    }
}

struct ScriptedReply {
    var status: Int
    var lines: [String]
    var body: Data
    var error: Error?
    var hangNanoseconds: UInt64
    var lineHangNanoseconds: UInt64
    var streamError: Error?

    init(
        status: Int = 200,
        lines: [String] = [],
        body: Data = Data(),
        error: Error? = nil,
        hangNanoseconds: UInt64 = 0,
        lineHangNanoseconds: UInt64 = 0,
        streamError: Error? = nil
    ) {
        self.status = status
        self.lines = lines
        self.body = body
        self.error = error
        self.hangNanoseconds = hangNanoseconds
        self.lineHangNanoseconds = lineHangNanoseconds
        self.streamError = streamError
    }
}

/// Maps URL (exact, then contains) or call order to a canned HTTP/SSE reply.
final class ScriptedTransport: ChatTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var byURL: [String: ScriptedReply] = [:]
    private var queue: [ScriptedReply] = []
    private var _requests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return _requests
    }

    func stub(url: String, _ reply: ScriptedReply) {
        lock.lock()
        byURL[url] = reply
        lock.unlock()
    }

    func stub(_ provider: ProviderDescriptor, _ reply: ScriptedReply) {
        stub(url: provider.endpoint?.absoluteString ?? "", reply)
    }

    func stubModels(_ provider: ProviderDescriptor, status: Int, error: Error? = nil) {
        stub(
            url: provider.baseURL.absoluteString + "/models",
            ScriptedReply(status: status, error: error))
    }

    func enqueue(_ reply: ScriptedReply) {
        lock.lock()
        queue.append(reply)
        lock.unlock()
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        remember(request)
        let reply = try resolve(request)
        try await hang(reply.hangNanoseconds)
        if let error = reply.error { throw error }
        return (reply.body, http(request, status: reply.status))
    }

    func lines(for request: URLRequest) async throws -> (
        status: Int, lines: AsyncThrowingStream<String, Error>
    ) {
        remember(request)
        let reply = try resolve(request)
        try await hang(reply.hangNanoseconds)
        try Task.checkCancellation()
        if let error = reply.error { throw error }
        // Yield canned lines in the builder so returning the stream cannot
        // cancel a producer Task before the first line is buffered.
        let canned = reply.lines
        let lineHang = reply.lineHangNanoseconds
        let streamError = reply.streamError
        let stream = AsyncThrowingStream<String, Error> { continuation in
            if lineHang == 0 {
                for line in canned { continuation.yield(line) }
                if let streamError {
                    continuation.finish(throwing: streamError)
                } else {
                    continuation.finish()
                }
                return
            }
            let reader = Task {
                do {
                    for line in canned {
                        try await hang(lineHang)
                        try Task.checkCancellation()
                        continuation.yield(line)
                    }
                    if let streamError {
                        continuation.finish(throwing: streamError)
                    } else {
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in reader.cancel() }
        }
        return (status: reply.status, lines: stream)
    }

    private func remember(_ request: URLRequest) {
        lock.lock()
        _requests.append(request)
        lock.unlock()
    }

    private func resolve(_ request: URLRequest) throws -> ScriptedReply {
        let url = request.url?.absoluteString ?? ""
        lock.lock()
        defer { lock.unlock() }
        if let exact = byURL[url] { return exact }
        for (needle, reply) in byURL where !needle.isEmpty && url.contains(needle) {
            return reply
        }
        if !queue.isEmpty { return queue.removeFirst() }
        throw URLError(.badURL)
    }

    private func http(_ request: URLRequest, status: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1")!,
            statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}

private func hang(_ nanoseconds: UInt64) async throws {
    guard nanoseconds > 0 else { return }
    try await Task.sleep(nanoseconds: nanoseconds)
}

/// Wave 10b: registra qué se pidió abrir y no abre nada.
final class FakeWorkspaceOpener: WorkspaceOpening, @unchecked Sendable {
    var installed: [String]
    var running: [String]
    var failure: ContractError?
    private(set) var openedApps: [String] = []
    private(set) var openedURLs: [URL] = []

    init(installed: [String] = ["Safari"], running: [String] = []) {
        self.installed = installed
        self.running = running
    }

    func openApplication(named name: String) async throws(ContractError) {
        if let failure { throw failure }
        openedApps.append(name)
    }

    func open(_ url: URL) async throws(ContractError) {
        if let failure { throw failure }
        openedURLs.append(url)
    }

    func runningApplications() -> [String] { running }
    func installedApplications() -> [String] { installed }
}

/// Wave 10a: un sensor que devuelve lo que se le dio y registra con qué
/// canales y presupuesto lo llamaron.
final class FakeContextSensor: ContextSensing, @unchecked Sendable {
    var context: TurnContext
    private let lock = NSLock()
    private var _calls: [(channels: ContextChannels, budget: Duration)] = []
    var calls: [(channels: ContextChannels, budget: Duration)] {
        lock.lock(); defer { lock.unlock() }; return _calls
    }

    init(_ context: TurnContext = TurnContext(source: .typed, focusedApp: "Safari")) {
        self.context = context
    }

    private func record(_ channels: ContextChannels, _ budget: Duration) {
        lock.lock(); _calls.append((channels, budget)); lock.unlock()
    }

    func sense(_ channels: ContextChannels, budget: Duration) async -> TurnContext {
        record(channels, budget)
        var ctx = context
        ctx.timestamp = Date()
        return ctx
    }
}

/// Wave 10c: an approvals actor in miniature — parks the request until the
/// test (or the view model) resolves it, and can answer from "memory".
actor FakeApprovals: ApprovalsProvider {
    private var pending: [String: CheckedContinuation<ApprovalResponse, Never>] = [:]
    private(set) var requested: [ApprovalRequest] = []
    private(set) var resolutions: [(id: String, approved: Bool, remember: Bool)] = []
    var memory: [String: Bool]

    init(memory: [String: Bool] = [:]) { self.memory = memory }

    func request(_ approval: ApprovalRequest) async -> ApprovalResponse {
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

    func resolve(requestId: String, approved: Bool) async -> Bool {
        await resolve(requestId: requestId, approved: approved, remember: false)
    }

    func resolve(requestId: String, approved: Bool, remember: Bool) async -> Bool {
        resolutions.append((requestId, approved, remember))
        guard let continuation = pending.removeValue(forKey: requestId) else { return false }
        continuation.resume(returning: ApprovalResponse(
            requestId: requestId, approved: approved, remember: remember))
        return true
    }

    func remembered(_ approval: ApprovalRequest) async -> Bool? {
        ApprovalKey.from(approval).flatMap { memory[$0.description] }
    }

    /// The first request still waiting, if any.
    var waiting: ApprovalRequest? { requested.first { pending[$0.requestId] != nil } }
}

/// `pumpUntil` for a predicate that has to hop into an actor.
@MainActor func pumpUntilAsync(
    _ label: String, timeout: TimeInterval = 10, _ pred: () async -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !(await pred()), Date() < deadline {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 2_000_000)
    }
    if !(await pred()) { Issue.record("timeout: \(label)") }
}
