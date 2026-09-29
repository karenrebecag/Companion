import CompanionCore
import Foundation
import Observation

/// Where the session reducer runs (Wave 12a). The ONLY object that mutates
/// the projection: views paint it, view models send events into it, and the
/// effects reach their ports from here. A view that wrote the kind itself
/// would be the local transition the chrome contract forbids.
@Observable
@MainActor
public final class SessionModel {
    public private(set) var projection = SessionProjection()

    private var machine = SessionMachine()
    private let jobs: (any JobSubmitter)?
    private let approvals: (any ApprovalsProvider)?
    /// The voice port (Wave 12b): where the hold's effects land.
    private let voice: (any VoiceControlling)?
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let log: @Sendable (String) -> Void
    private var expiry: Task<Void, Never>?
    private var pendingExpiry: Task<Void, Never>?
    private var voiceIdle: Task<Void, Never>?
    private var noticeExpiry: Task<Void, Never>?
    private var handsGlowExpiry: Task<Void, Never>?
    /// Wave 17: "the voice wins" — `BridgeHost` pauses the bridge for any
    /// turn of Karen's own and resumes it back at rest. `send(_:)` is the
    /// only place `projection.kind` changes, so it is the only place that
    /// needs to notice.
    public var onKindChange: (@MainActor (SessionKind) -> Void)?
    /// A request left the sheet by any road (click, spoken, dropped, settled
    /// elsewhere). The voice session drops its note for it, so a later
    /// injected yes has nothing stale to answer (Wave 20c D1). The Bool is
    /// the sheet's own verdict, nil when it closed without one; the voice
    /// session needs it to answer an MCP request with the click (20c D2).
    public var onApprovalClosed: (@MainActor (String, Bool?) -> Void)?

    public init(
        jobs: (any JobSubmitter)?,
        approvals: (any ApprovalsProvider)?,
        voice: (any VoiceControlling)? = nil,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
            try await Task.sleep(for: .seconds($0))
        },
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.jobs = jobs
        self.approvals = approvals
        self.voice = voice
        self.sleep = sleep
        self.log = log
    }

    /// Returns the effects so a caller that keeps the thread (ChatViewModel)
    /// can write its record when the reducer decided to stop a job.
    @discardableResult
    public func send(_ event: SessionEvent) -> [SessionEffect] {
        let previousKind = projection.kind
        let effects = machine.handle(event)
        projection = machine.projection
        if projection.kind != previousKind {
            onKindChange?(projection.kind)
        }
        // Anything that moved the chrome off Completed owns it now; a late
        // timer must not drag a new turn back to Idle.
        if projection.kind != .processing(.completed) {
            expiry?.cancel()
            expiry = nil
        }
        if projection.kind != .processing(.pending) {
            pendingExpiry?.cancel()
            pendingExpiry = nil
        }
        // The reducer arms this only while the warm voice rests; anything
        // that leaves rest (a press, a turn, a job) disarms it here.
        if !restingChrome || projection.voice != .muted || projection.holding {
            voiceIdle?.cancel()
            voiceIdle = nil
        }
        for effect in effects { perform(effect) }
        notifyClosedApprovals(event, effects)
        return effects
    }

    private func notifyClosedApprovals(_ event: SessionEvent, _ effects: [SessionEffect]) {
        for case .resolveApproval(let id, let approved, _) in effects {
            onApprovalClosed?(id, approved)
        }
        if case .approvalSettled(let id) = event { onApprovalClosed?(id, nil) }
    }

    private func perform(_ effect: SessionEffect) {
        switch effect {
        case .cancelJob:
            guard let jobs else { return }
            Task { await jobs.cancel() }
        case .resolveApproval(let id, let approved, let remember):
            // The same actor answers a specialist's request and the parent's
            // gate; the submitter is the road when no actor was injected.
            if let approvals {
                Task { _ = await approvals.resolve(
                    requestId: id, approved: approved, remember: remember) }
            } else if let jobs {
                Task { await jobs.resolveApproval(
                    requestId: id, approved: approved, remember: remember) }
            }
        case .scheduleCompletedExpiry(let delay):
            expiry?.cancel()
            expiry = timer(delay, then: .completedTimerExpired)
        case .scheduleNoticeExpiry(let delay):
            // A second "didn't hear you" gets its own six seconds.
            noticeExpiry?.cancel()
            noticeExpiry = timer(delay, then: .noticeExpired)
        case .scheduleHandsGlowExpiry(let delay):
            // Each call restarts the four seconds: the aura ends after the last one.
            handsGlowExpiry?.cancel()
            handsGlowExpiry = timer(delay, then: .handsGlowExpired)
        case .schedulePendingExpiry(let delay):
            pendingExpiry?.cancel()
            pendingExpiry = timer(delay, then: .pendingTimedOut)
        case .scheduleVoiceIdleExpiry(let delay):
            voiceIdle?.cancel()
            voiceIdle = timer(delay, then: .voiceIdleExpired)
        case .hangUpVoice:
            guard let voice else { return }
            Task { await voice.hangUp() }
        case .startListening:
            guard let voice else { return }
            Task { await voice.hold() }
        case .startProvisionalListening:
            guard let voice else { return }
            Task { await voice.holdProvisionally() }
        case .confirmListening:
            guard let voice else { return }
            Task { await voice.confirmHold() }
        case .stopListening(let commit):
            guard let voice else { return }
            Task { commit ? await voice.release() : await voice.discard() }
        case .cancelVoiceOutput:
            guard let voice else { return }
            Task { await voice.interrupt() }
        case .logTransition(let from, let to):
            log("session: \(Self.name(from)) -> \(Self.name(to))")
        }
    }

    private var restingChrome: Bool {
        switch projection.kind {
        case .idle, .hover, .processing(.completed): true
        default: false
        }
    }

    private func timer(_ delay: TimeInterval, then event: SessionEvent) -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sleep(delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self.send(event)
        }
    }

    private static func name(_ kind: SessionKind) -> String {
        switch kind {
        case .idle: "idle"
        case .hover: "hover"
        case .listening: "listening"
        case .processing(let phase): "processing(\(phase))"
        }
    }
}
