import CompanionCore
import Foundation

/// Puente QA D4: waits for a turn without polling. A caller parks on a
/// continuation; the turn's end, an owner check opening or the cap wakes it.
/// The connection serves one line at a time, so the wait must hand control
/// back as soon as the person has something to do (touch the sensor) and
/// never run past the cap, which sits under the shim's own timeout.
package actor TurnWaiter {
    package enum Outcome: Sendable, Equatable {
        case finished, awaitingOwner, timedOut
    }

    /// Returns when `seconds` have passed. Injected: the default waits on the
    /// clock, tests hold or release it at will.
    package typealias Limit = @Sendable (_ seconds: Int) async throws -> Void

    private enum State { case running, awaitingOwner, finished }
    private static let remembered = 64

    private let limit: Limit
    private var states: [String: State] = [:]
    private var order: [String] = []
    private var parked: [Int: (turnId: String, continuation: CheckedContinuation<Outcome, Never>)] = [:]
    private var nextTicket = 0

    package init(limit: @escaping Limit = { try await Task.sleep(for: .seconds($0)) }) {
        self.limit = limit
    }

    /// What the chat reports. Kept even when nobody waits yet: a turn that
    /// ends between `ask` returning and `wait` parking must not hang the wait.
    package func signal(turnId: String, _ signal: TurnSignal) {
        remember(turnId)
        switch signal {
        case .ownerCheckOpened:
            guard states[turnId] != .finished else { return }
            states[turnId] = .awaitingOwner
            resume(turnId, with: .awaitingOwner)
        case .ownerCheckClosed:
            if states[turnId] == .awaitingOwner { states[turnId] = .running }
        case .finished:
            states[turnId] = .finished
            resume(turnId, with: .finished)
        }
    }

    package func wait(turnId: String, seconds: Int) async -> Outcome {
        switch states[turnId] {
        case .finished: return .finished
        case .awaitingOwner: return .awaitingOwner
        case .running, nil: break
        }
        guard seconds > 0, !Task.isCancelled else { return .timedOut }
        let ticket = nextTicket
        nextTicket += 1
        let cap = limit
        let timer = Task {
            // A cancelled sleep did not elapse; only a full wait expires the ticket.
            do { try await cap(seconds) } catch { return }
            self.expire(ticket)
        }
        defer { timer.cancel() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                parked[ticket] = (turnId, continuation)
            }
        } onCancel: {
            Task { await self.expire(ticket) }
        }
    }

    /// The connection ended: nobody is left to read what a parked wait returns.
    package func cancelAll() {
        for ticket in Array(parked.keys) { expire(ticket) }
    }

    private func expire(_ ticket: Int) {
        guard let entry = parked.removeValue(forKey: ticket) else { return }
        entry.continuation.resume(returning: .timedOut)
    }

    private func resume(_ turnId: String, with outcome: Outcome) {
        for (ticket, entry) in parked where entry.turnId == turnId {
            parked[ticket] = nil
            entry.continuation.resume(returning: outcome)
        }
    }

    private func remember(_ turnId: String) {
        guard states[turnId] == nil else { return }
        states[turnId] = .running
        order.append(turnId)
        if order.count > Self.remembered {
            states[order.removeFirst()] = nil
        }
    }
}
