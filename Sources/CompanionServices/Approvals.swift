import Foundation
import CompanionCore

public protocol Clock: Sendable {
    func now() -> TimeInterval
}

actor Approvals {
    private struct PendingRequest {
        let deadline: TimeInterval
        var response: ApprovalResponse?
    }

    private var pending: [String: PendingRequest] = [:]
    private let clock: Clock
    private let timeout: TimeInterval = 120

    nonisolated let _clock: Clock

    init(clock: Clock) {
        self.clock = clock
        self._clock = clock
    }

    func request(_ approval: ApprovalRequest) async -> ApprovalResponse {
        let deadline = clock.now() + timeout
        pending[approval.requestId] = PendingRequest(deadline: deadline)

        let timeoutTask = Task {
            await autoDeny(requestId: approval.requestId, deadline: deadline)
        }

        // Poll for resolution
        while pending[approval.requestId] != nil && clock.now() < deadline {
            do {
                try await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
            } catch {
                // Cancelled or other error — stop polling
                break
            }

            if let pending = pending[approval.requestId],
               let response = pending.response {
                self.pending.removeValue(forKey: approval.requestId)
                timeoutTask.cancel()
                return response
            }
        }

        // If we get here, timeout or already resolved
        timeoutTask.cancel()
        let response = pending.removeValue(forKey: approval.requestId)?.response
        return response ?? ApprovalResponse(requestId: approval.requestId, approved: false)
    }

    func resolve(requestId: String, approved: Bool) async -> Bool {
        guard pending[requestId] != nil else {
            return false
        }

        let response = ApprovalResponse(requestId: requestId, approved: approved)
        pending[requestId]?.response = response

        return true
    }

    private func autoDeny(requestId: String, deadline: TimeInterval) async {
        while clock.now() < deadline {
            do {
                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            } catch {
                // Cancelled or other error — stop waiting
                return
            }
        }

        _ = await resolve(requestId: requestId, approved: false)
    }
}

public struct ApprovalResponse: Sendable, Equatable {
    public var requestId: String
    public var approved: Bool

    public init(requestId: String, approved: Bool) {
        self.requestId = requestId
        self.approved = approved
    }
}

public final class RealtimeClock: Clock, Sendable {
    public init() {}

    nonisolated public func now() -> TimeInterval {
        Date().timeIntervalSince1970
    }
}
