import Foundation
import CompanionCore

package protocol Clock: Sendable {
    func now() -> TimeInterval
}

/// Where a permission waits (Wave 10c 3B.1): `request` suspends on a
/// continuation, `resolve` resumes it, and a timer denies it on its own at
/// the deadline. No polling — ARCHITECTURE.md's rule. The session's memory
/// of remembered decisions lives here too, because this is the actor that
/// receives `remember`.
package actor Approvals: ApprovalsProvider {
    private struct Pending {
        let request: ApprovalRequest
        let continuation: CheckedContinuation<ApprovalResponse, Never>
        let timer: Task<Void, Never>
    }

    private enum Resolver: String { case user, timeout, interrupt }

    private var pending: [String: Pending] = [:]
    private var memory = ApprovalMemory()
    private let clock: Clock
    private let timeout: TimeInterval

    package init(clock: Clock, timeout: TimeInterval = ApprovalTiming.autoDeny) {
        self.clock = clock
        self.timeout = timeout
    }

    /// Suspends until `resolve`, the deadline, or the caller's cancellation:
    /// a turn that was switched away must not stay parked on the sheet.
    package func request(_ approval: ApprovalRequest) async -> ApprovalResponse {
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
                    _ = resolveNow(requestId: id, approved: false, remember: false, by: .interrupt)
                }
            }
        } onCancel: {
            Task { await self.interrupt(id) }
        }
    }

    package func resolve(requestId: String, approved: Bool) async -> Bool {
        await resolve(requestId: requestId, approved: approved, remember: false)
    }

    package func resolve(requestId: String, approved: Bool, remember: Bool) async -> Bool {
        resolveNow(requestId: requestId, approved: approved, remember: remember)
    }

    private func interrupt(_ requestId: String) {
        _ = resolveNow(requestId: requestId, approved: false, remember: false, by: .interrupt)
    }

    private func resolveNow(
        requestId: String, approved: Bool, remember: Bool, by resolver: Resolver = .user
    ) -> Bool {
        guard let entry = pending.removeValue(forKey: requestId) else { return false }
        entry.timer.cancel()
        // Only the tool name: the arguments and the summary carry what the
        // user is working on.
        Log.app("approvals: resolved tool=\(entry.request.toolName) approved=\(approved) by=\(resolver.rawValue)")
        let timedOut = resolver == .timeout
        // An MCP request has no key; the response must not claim otherwise.
        let remembers = remember && !entry.request.isMCP
        if remembers, let key = ApprovalKey.from(entry.request) {
            memory = memory.remembering(key, approved: approved)
        }
        entry.continuation.resume(returning: ApprovalResponse(
            requestId: requestId, approved: approved, remember: remembers, timedOut: timedOut))
        return true
    }

    package func remembered(_ approval: ApprovalRequest) async -> Bool? {
        guard let key = ApprovalKey.from(approval) else { return nil }
        return memory.decision(for: key)
    }

    private func autoDeny(_ requestId: String, started: TimeInterval) async {
        guard pending[requestId] != nil else { return }
        Log.app("approvals: auto-denied after \(Int(clock.now() - started))s")
        _ = resolveNow(requestId: requestId, approved: false, remember: false, by: .timeout)
    }
}

package final class RealtimeClock: Clock, Sendable {
    package init() {}

    nonisolated package func now() -> TimeInterval {
        Date().timeIntervalSince1970
    }
}
