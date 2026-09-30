import Foundation
import CompanionCore

public protocol Clock: Sendable {
    func now() -> TimeInterval
}

/// Where a permission waits (Wave 10c 3B.1): `request` suspends on a
/// continuation, `resolve` resumes it, and a timer denies it on its own at
/// the deadline. No polling — ARCHITECTURE.md's rule. The session's memory
/// of remembered decisions lives here too, because this is the actor that
/// receives `remember`.
public actor Approvals: ApprovalsProvider {
    private struct Pending {
        let request: ApprovalRequest
        let continuation: CheckedContinuation<ApprovalResponse, Never>
        let timer: Task<Void, Never>
    }

    private var pending: [String: Pending] = [:]
    private var memory = ApprovalMemory()
    private let clock: Clock
    private let timeout: TimeInterval

    public init(clock: Clock, timeout: TimeInterval = ApprovalTiming.autoDeny) {
        self.clock = clock
        self.timeout = timeout
    }

    /// Suspends until `resolve`, the deadline, or the caller's cancellation:
    /// a turn that was switched away must not stay parked on the sheet.
    public func request(_ approval: ApprovalRequest) async -> ApprovalResponse {
        let id = approval.requestId
        let started = clock.now()
        let timeout = self.timeout
        if Task.isCancelled { return ApprovalResponse(requestId: id, approved: false) }
        // A second request under an id already waiting would overwrite the
        // first and leave its caller parked for ever (and an id can come from
        // a remote server): the newcomer is refused, the original stays.
        if pending[id] != nil {
            Log.app("approvals: duplicate request id refused")
            return ApprovalResponse(requestId: id, approved: false)
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let timer = Task { [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    } catch {
                        return
                    }
                    await self?.autoDeny(id, started: started)
                }
                pending[id] = Pending(request: approval, continuation: continuation, timer: timer)
                if Task.isCancelled {
                    _ = resolveNow(requestId: id, approved: false, remember: false)
                }
            }
        } onCancel: {
            Task { await self.resolve(requestId: id, approved: false, remember: false) }
        }
    }

    public func resolve(requestId: String, approved: Bool) async -> Bool {
        await resolve(requestId: requestId, approved: approved, remember: false)
    }

    public func resolve(requestId: String, approved: Bool, remember: Bool) async -> Bool {
        resolveNow(requestId: requestId, approved: approved, remember: remember)
    }

    private func resolveNow(
        requestId: String, approved: Bool, remember: Bool, timedOut: Bool = false
    ) -> Bool {
        guard let entry = pending.removeValue(forKey: requestId) else { return false }
        entry.timer.cancel()
        // An MCP request has no key; the response must not claim otherwise.
        let remembers = remember && !entry.request.isMCP
        if remembers, let key = ApprovalKey.from(entry.request) {
            memory = memory.remembering(key, approved: approved)
        }
        entry.continuation.resume(returning: ApprovalResponse(
            requestId: requestId, approved: approved, remember: remembers, timedOut: timedOut))
        return true
    }

    public func remembered(_ approval: ApprovalRequest) async -> Bool? {
        guard let key = ApprovalKey.from(approval) else { return nil }
        return memory.decision(for: key)
    }

    private func autoDeny(_ requestId: String, started: TimeInterval) async {
        guard pending[requestId] != nil else { return }
        Log.app("approvals: auto-denied after \(Int(clock.now() - started))s")
        _ = resolveNow(requestId: requestId, approved: false, remember: false, timedOut: true)
    }
}

public final class RealtimeClock: Clock, Sendable {
    public init() {}

    nonisolated public func now() -> TimeInterval {
        Date().timeIntervalSince1970
    }
}
