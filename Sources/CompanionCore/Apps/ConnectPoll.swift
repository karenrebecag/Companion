import Foundation

/// Wave 16k-2b (spec §9.5 D2, audited against Incredible's real binary
/// §9.6): the connect attempt's own state machine. Pure — no I/O, no Task,
/// no `Date()` — the same reducer shape `TurnMachine` uses: the caller
/// (`AppsModel`'s async loop) supplies every event and `now`.
package struct ConnectPoll: Sendable, Equatable {
    package enum Phase: Sendable, Equatable {
        case initiating
        case waiting(attempts: Int)
        case complete
        case timedOut
        case failed(message: String)
    }

    package enum Event: Sendable, Equatable {
        /// The function returned the Pipedream Connect Link. Polling has not
        /// started yet — the browser has not shown the page (audit §9.6:
        /// `initiating` shows "Opening your browser…" up to this point).
        case linkObtained
        /// The system browser is now showing the link: attempts begin.
        case browserOpened
        case accountSeen
        /// One `/api/accounts` check that did not find the account yet.
        case accountMissing
        case failure(message: String)
        /// "Reintentar": a fresh `connectLink` is coming, so the clock and
        /// the attempt count both start over.
        case retry
    }

    /// Audited constants (spec §9.5 D2): 3 s between checks, 40 attempts
    /// (~2 min), and a global timeout that runs from `initiating`, not from
    /// the first `waiting` tick.
    package static let interval: TimeInterval = 3
    package static let maxAttempts = 40
    package static let overallTimeout: TimeInterval = 150
    /// Audit §9.6: the "still waiting on the browser" hint shows after
    /// several attempts, not on the first one.
    package static let hintThreshold = 5

    package private(set) var phase: Phase = .initiating
    private var startedAt: TimeInterval

    package init(startedAt: TimeInterval) {
        self.startedAt = startedAt
    }

    /// Whether the driving loop should still be scheduling `/api/accounts`
    /// checks — true only in `waiting`, never in `initiating` (that leg is
    /// one awaited call, not a timer) nor any terminal phase.
    package var isWaiting: Bool {
        if case .waiting = phase { return true }
        return false
    }

    package var showsStillWaitingHint: Bool {
        if case .waiting(let attempts) = phase { return attempts >= Self.hintThreshold }
        return false
    }

    @discardableResult
    package mutating func handle(_ event: Event, at now: TimeInterval) -> Phase {
        if case .retry = event {
            phase = .initiating
            startedAt = now
            return phase
        }
        // Terminal phases ignore every event but retry: a stray tick landing
        // after complete/timedOut/failed must change nothing.
        guard isOngoing else { return phase }
        // The global cap outranks the event itself and runs from the very
        // start (D2: "corre desde initiating") — a tick arriving late is not
        // what timed the attempt out, the clock did.
        if now - startedAt >= Self.overallTimeout {
            phase = .timedOut
            return phase
        }
        switch event {
        case .linkObtained:
            break
        case .browserOpened:
            if case .initiating = phase { phase = .waiting(attempts: 0) }
        case .accountSeen:
            phase = .complete
        case .accountMissing:
            if case .waiting(let attempts) = phase {
                let next = attempts + 1
                phase = next >= Self.maxAttempts ? .timedOut : .waiting(attempts: next)
            }
        case .failure(let message):
            phase = .failed(message: message)
        case .retry:
            break // handled above
        }
        return phase
    }

    private var isOngoing: Bool {
        switch phase {
        case .initiating, .waiting: true
        case .complete, .timedOut, .failed: false
        }
    }
}
