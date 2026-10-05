import CompanionCore
import Foundation
import Observation

/// Where the session reducer runs (Wave 12a). The ONLY object that mutates
/// the projection: views paint it, view models send events into it, and the
/// effects reach their ports from here. A view that wrote the kind itself
/// would be the local transition the chrome contract forbids.
@Observable
@MainActor
package final class SessionModel {
    package private(set) var projection = SessionProjection()

    private var machine = SessionMachine()
    private let jobs: (any JobSubmitter)?
    private let approvals: (any ApprovalsProvider)?
    /// The voice port (Wave 12b): where the hold's effects land.
    private let voice: (any VoiceControlling)?
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let log: @Sendable (String) -> Void
    private let now: @Sendable () -> TimeInterval
    private var expiry: Task<Void, Never>?
    private var pendingExpiry: Task<Void, Never>?
    private var voiceIdle: Task<Void, Never>?
    private var noticeExpiry: Task<Void, Never>?
    private var handsGlowExpiry: Task<Void, Never>?
    private var receiptExpiry: Task<Void, Never>?
    /// P1: the wait before passive; each interaction replaces it.
    private var passiveExpiry: Task<Void, Never>?
    /// What a paused clock still had left. A new schedule replaces it.
    private var completedArm: ClockArm?
    private var noticeArm: ClockArm?
    /// Fires the remainder when a pause has used up the ceiling. A lost
    /// hover-out must not leave the card up forever.
    private var completedCeiling: Task<Void, Never>?
    private var noticeCeiling: Task<Void, Never>?
    /// 16h-3: where the island's events wait for the next turn.
    package var islandEvents: (any IslandEventSink)?
    /// Wave 17: "the voice wins" — `BridgeHost` pauses the bridge for any
    /// turn of Karen's own and resumes it back at rest; the audio coordinator
    /// listens too. `send(_:)` is the only place `projection.kind` changes,
    /// so it is the only place that needs to notice. A list, not one slot:
    /// each consumer registers on its own and none can replace another.
    private var kindObservers: [@MainActor (SessionKind) -> Void] = []

    /// Called in registration order, once per real change of kind.
    package func addKindObserver(_ observer: @escaping @MainActor (SessionKind) -> Void) {
        kindObservers.append(observer)
    }

    /// The user pressed Undo on a receipt (Wave 20d B). The composition root
    /// wires the adapter that takes the action back.
    package var onUndo: (@MainActor (UndoReceipt) -> Void)?

    package init(
        jobs: (any JobSubmitter)?,
        approvals: (any ApprovalsProvider)?,
        voice: (any VoiceControlling)? = nil,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
            try await Task.sleep(for: .seconds($0))
        },
        log: @escaping @Sendable (String) -> Void = { _ in },
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    ) {
        self.jobs = jobs
        self.approvals = approvals
        self.voice = voice
        self.sleep = sleep
        self.log = log
        self.now = now
    }

    /// Returns the effects so a caller that keeps the thread (ChatViewModel)
    /// can write its record when the reducer decided to stop a job.
    @discardableResult
    package func send(_ event: SessionEvent) -> [SessionEffect] {
        let previousKind = projection.kind
        let effects = machine.handle(event)
        projection = machine.projection
        if projection.kind != previousKind {
            for observer in kindObservers { observer(projection.kind) }
        }
        // Anything that moved the chrome off Completed owns it now; a late
        // timer must not drag a new turn back to Idle.
        if projection.kind != .processing(.completed) {
            expiry?.cancel()
            expiry = nil
            completedCeiling?.cancel()
            completedCeiling = nil
            completedArm = nil
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
        if projection.notice == nil {
            noticeExpiry?.cancel()
            noticeExpiry = nil
            noticeCeiling?.cancel()
            noticeCeiling = nil
            noticeArm = nil
        }
        for effect in effects { perform(effect) }
        return effects
    }

    /// What only the view knows (a card the user closed, a result nobody
    /// opened) reaches the model through here.
    package func report(_ event: IslandEvent) {
        islandEvents?.record(event)
    }

    private func perform(_ effect: SessionEffect) {
        switch effect {
        case .cancelJob:
            guard let jobs else { return }
            Task { await jobs.cancel() }
        case .approvalClosed(let id):
            guard let voice else { return }
            Task { await voice.approvalClosed(requestId: id) }
        case .approvalFront(let id):
            guard let voice else { return }
            Task { await voice.approvalFront(requestId: id) }
        case .cancelJobByID(let id):
            guard let jobs else { return }
            Task { await jobs.cancel(job: id) }
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
            completedCeiling?.cancel()
            completedCeiling = nil
            completedArm = engage(delay, event: .completedTimerExpired, running: expiry)
            expiry = timer(delay, then: .completedTimerExpired)
        case .pauseCompletedExpiry:
            if let (arm, budget) = frozen(completedArm) {
                completedArm = arm
                expiry?.cancel()
                expiry = nil
                completedCeiling?.cancel()
                completedCeiling = ceilingTask(budget, release: releaseCompleted)
            }
        case .resumeCompletedExpiry:
            releaseCompleted()
        case .scheduleNoticeExpiry(let delay):
            // A second "didn't hear you" gets its own six seconds.
            // Armed for THIS notice: if another took its place, the late
            // clock finds it changed and does nothing.
            noticeCeiling?.cancel()
            noticeCeiling = nil
            let event = projection.notice.map { SessionEvent.noticeExpired($0) } ?? .noticeDismissed
            noticeArm = engage(delay, event: event, running: noticeExpiry)
            noticeExpiry = timer(delay, then: event)
        case .pauseNoticeExpiry:
            if let (arm, budget) = frozen(noticeArm) {
                noticeArm = arm
                noticeExpiry?.cancel()
                noticeExpiry = nil
                noticeCeiling?.cancel()
                noticeCeiling = ceilingTask(budget, release: releaseNotice)
            }
        case .resumeNoticeExpiry:
            releaseNotice()
        case .scheduleReceiptExpiry(let id, let delay):
            // The newest receipt owns the window: an older one's undo is gone.
            receiptExpiry?.cancel()
            receiptExpiry = timer(delay, then: .receiptExpired(id: id))
        case .undo(let receipt):
            receiptExpiry?.cancel()
            onUndo?(receipt)
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
        case .schedulePassive(let delay, let armedFor):
            passiveExpiry?.cancel()
            passiveExpiry = timer(delay, then: .passiveExpired(armedFor: armedFor))
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
        case .islandEvent(let fact):
            islandEvents?.record(fact)
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

    /// `left` set means the wait is frozen. A new `start` drops it, so the
    /// next notice or dictation does not inherit the previous remainder.
    /// `pausedTotal` is this clock's paused time so far: the ceiling is a
    /// budget for the clock, not a fresh minute on every hover.
    private struct ClockArm {
        var at: TimeInterval
        var delay: TimeInterval
        var left: TimeInterval?
        var event: SessionEvent
        var pausedTotal: TimeInterval = 0
        var pauseStarted: TimeInterval?
    }

    /// Cancels `running` before the caller stores the new task. No inout:
    /// the task and `now` are both properties of this model.
    private func engage(_ delay: TimeInterval, event: SessionEvent, running: Task<Void, Never>?) -> ClockArm {
        running?.cancel()
        return ClockArm(at: now(), delay: delay, left: nil, event: event)
    }

    /// A second pause keeps the first remainder. Past the ceiling the timer
    /// is left running: more hovering must not extend it. `now` is read
    /// before any task property is stored, so the two accesses do not overlap.
    private func frozen(_ clock: ClockArm?) -> (ClockArm, TimeInterval)? {
        guard var arm = clock, arm.left == nil else { return nil }
        guard arm.pausedTotal < SessionMachine.countdownPauseCeiling else { return nil }
        let stamp = now()
        arm.left = max(0, arm.delay - (stamp - arm.at))
        arm.pauseStarted = stamp
        return (arm, SessionMachine.countdownPauseCeiling - arm.pausedTotal)
    }

    private func ceilingTask(
        _ budget: TimeInterval, release: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            do { try await self.sleep(budget) } catch { return }
            guard !Task.isCancelled else { return }
            release()
        }
    }

    private func releaseCompleted() {
        let next = thawed(completedArm)
        completedCeiling?.cancel()
        completedCeiling = nil
        guard let (arm, left, event) = next else { return }
        expiry?.cancel()
        completedArm = arm
        expiry = timer(left, then: event)
    }

    private func releaseNotice() {
        let next = thawed(noticeArm)
        noticeCeiling?.cancel()
        noticeCeiling = nil
        guard let (arm, left, event) = next else { return }
        noticeExpiry?.cancel()
        noticeArm = arm
        noticeExpiry = timer(left, then: event)
    }

    /// What a resume would arm. Nil when nothing is paused: the running
    /// timer stays. `now` is read here, with no task held inout.
    private func thawed(_ clock: ClockArm?) -> (ClockArm, TimeInterval, SessionEvent)? {
        guard let arm = clock, let left = arm.left else { return nil }
        var spent = arm.pausedTotal
        if let started = arm.pauseStarted { spent += max(0, now() - started) }
        if spent > SessionMachine.countdownPauseCeiling { spent = SessionMachine.countdownPauseCeiling }
        let next = ClockArm(at: now(), delay: left, left: nil, event: arm.event,
                            pausedTotal: spent, pauseStarted: nil)
        return (next, left, arm.event)
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
