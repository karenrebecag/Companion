import CompanionCore
import Foundation

/// Starts capture+vision on press, hands a brief at commit. One hold at a
/// time. Wave 15b-6: an AX harvest of the app in front runs alongside, on
/// its own task — vision wins the snippets when it lands in time; the AX
/// text covers the gap when it does not. `pending` reflects vision only:
/// the AX walk is bounded and always resolves inside the hold, never a
/// second "still coming".
public final class ScreenSight: ScreenSeeing, @unchecked Sendable {
    private let capture: ScreenCapture
    private let vision: ScreenVision
    /// The AX walk, behind a closure so tests never need real Accessibility
    /// (production wires `AXScreenText(...).harvest`).
    private let axHarvest: @Sendable (pid_t) -> [String]
    private let pid: @Sendable () -> pid_t?
    private let appName: @Sendable () -> String?
    /// Injectable so a carry's age can be tested without a real 30 s wait.
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var generation = 0
    private var work: Task<ScreenBrief, Never>?
    private var axWork: Task<[ScreenSnippet], Never>?
    /// The pid `work` was started for — the one a carried result must still
    /// match before another turn may use it (HIGH-2/M2).
    private var workPid: pid_t?
    /// Wave 15g-5: a vision call that lost the race keeps running for the
    /// next turn instead of being cancelled. One slot: a newer late call
    /// replaces an older one, and `finish` consumes it once.
    private var late: Task<ScreenBrief, Never>?
    private var lateBrief: ScreenBrief?
    /// HIGH-2/M2: the pid `lateBrief` was captured for, and when — a carry
    /// is only ever offered to the same app, within 30 s of landing.
    private var latePid: pid_t?
    private var lateBriefAt: Date?
    static let carryTTL: TimeInterval = 30
    /// Wave 16a-3: false in the app — every turn paid 3.3–3.7 s of vision
    /// for a picture the text-only brain cannot act on. The turn keeps the
    /// Accessibility text; pixels come from `see`, on demand.
    private let visionPerTurn: Bool
    /// Wave 16o-3: what the cursor rests on during the hold (production
    /// wires `PointerSampler`).
    private let pointerStart: @Sendable () -> Void
    private let pointerStop: @Sendable () -> [PointedElement]

    public init(
        capture: ScreenCapture,
        vision: ScreenVision,
        axHarvest: @escaping @Sendable (pid_t) -> [String] = { _ in [] },
        pid: @escaping @Sendable () -> pid_t? = { nil },
        appName: @escaping @Sendable () -> String? = { nil },
        now: @escaping @Sendable () -> Date = Date.init,
        visionPerTurn: Bool = true,
        pointerStart: @escaping @Sendable () -> Void = {},
        pointerStop: @escaping @Sendable () -> [PointedElement] = { [] }
    ) {
        self.pointerStart = pointerStart
        self.pointerStop = pointerStop
        self.visionPerTurn = visionPerTurn
        self.capture = capture
        self.vision = vision
        self.axHarvest = axHarvest
        self.pid = pid
        self.appName = appName
        self.now = now
    }

    public func begin(app: String?) {
        let name = app ?? appName()
        let target = pid()
        lock.lock()
        generation += 1
        work?.cancel()
        axWork?.cancel()
        // A carried summary is only ever for the app it was captured in:
        // fronting a different app must never let it leak into that app's
        // next turn (M2).
        if let latePid, latePid != target {
            late?.cancel()
            late = nil
            lateBrief = nil
            self.latePid = nil
            lateBriefAt = nil
        }
        workPid = target
        work = visionPerTurn ? Task { await self.run(app: name) } : nil
        // Not detached: `begin` is nonisolated, so this already runs off any
        // actor, and a detached task would drop the caller's log capture.
        axWork = Task(priority: .userInitiated) { await self.runAX(pid: target, app: name) }
        lock.unlock()
    }

    public func beginPointing() {
        pointerStart()
    }

    /// One capture and one vision call, now: the `see` tool, for a question
    /// about what the screen looks like. Nil without a capture grant or a key.
    public func see(app: String?) async -> ScreenBrief? {
        let brief = await run(app: app ?? appName())
        return brief.summary == nil && brief.snippets.isEmpty ? nil : brief
    }

    public func cancel() {
        _ = pointerStop()
        lock.lock()
        generation += 1
        work?.cancel()
        work = nil
        axWork?.cancel()
        axWork = nil
        late?.cancel()
        late = nil
        lateBrief = nil
        latePid = nil
        lateBriefAt = nil
        lock.unlock()
    }

    /// The AX harvest for the hold in flight, awaited without touching
    /// vision's own task — `ClassicRuntime` calls this before `finish` to
    /// decide `hasText` without paying vision's wait for it (spec 15b-7b).
    public func axSnippets() async -> [ScreenSnippet] {
        let task = lock.withLock { axWork }
        return await axSnippets(task)
    }

    public func finish(wait: Duration) async -> ScreenBrief {
        // Sampling ends at commit, before waiting on vision: the pointing
        // belongs to what was said, not to how long the answer took.
        let pointed = pointerStop()
        var brief = await finishBrief(wait: wait)
        brief.pointed = pointed
        return brief
    }

    private func finishBrief(wait: Duration) async -> ScreenBrief {
        let snapshot: (Task<ScreenBrief, Never>?, Task<[ScreenSnippet], Never>?, Int, pid_t?) =
            lock.withLock { (work, axWork, generation, workPid) }
        guard let task = snapshot.0 else {
            return ScreenBrief(snippets: await axSnippets(snapshot.1), pending: false)
        }
        async let ax = axSnippets(snapshot.1)
        let winner = await race(task, wait: wait)
        lock.withLock {
            if generation == snapshot.2 { work = nil; axWork = nil }
        }
        guard let winner else {
            let carried = carry(task, pid: snapshot.3)
            let fresh = await ax
            guard let carried else { return ScreenBrief(snippets: fresh, pending: true) }
            // The previous hold's vision describes an older screen: its gist
            // is still worth the model's while, but AX text read now beats
            // its snippets. Not `pending`, or the block would hide the summary.
            return ScreenBrief(
                summary: carried.summary,
                snippets: fresh.isEmpty ? carried.snippets : fresh,
                pending: false, stale: true)
        }
        // A fresh vision makes any carried one stale for good.
        lock.withLock {
            late?.cancel()
            late = nil
            lateBrief = nil
            latePid = nil
            lateBriefAt = nil
        }
        // Vision arrived: its snippets win when it has any; an AX text that
        // vision could not (no capture grant, an unreadable frame) still
        // beats silence.
        let snippets = winner.snippets.isEmpty ? await ax : winner.snippets
        return ScreenBrief(summary: winner.summary, snippets: snippets, pending: false)
    }

    /// Takes whatever an earlier late call left finished and parks this
    /// hold's still-running call in its place, cancelling an older one that
    /// never landed — at most one vision call ever outlives its hold. The
    /// handoff only fires for the same app and inside the carry's TTL
    /// (HIGH-2/M2): a summary from another app, or one too old to trust,
    /// is dropped instead of handed to this turn.
    private func carry(_ task: Task<ScreenBrief, Never>, pid: pid_t?) -> ScreenBrief? {
        let previous: (brief: ScreenBrief, at: Date)? = lock.withLock {
            defer {
                late?.cancel()
                late = task
                latePid = pid
            }
            guard let lateBrief, let lateBriefAt, let pid, latePid == pid else { return nil }
            self.lateBrief = nil
            self.lateBriefAt = nil
            return (lateBrief, lateBriefAt)
        }
        Task { [weak self] in
            let brief = await task.value
            guard let self else { return }
            self.lock.withLock {
                guard self.late == task else { return }
                self.late = nil
                if brief.summary != nil || !brief.snippets.isEmpty {
                    self.lateBrief = brief
                    self.lateBriefAt = self.now()
                }
            }
        }
        guard let previous, now().timeIntervalSince(previous.at) <= Self.carryTTL else {
            return nil
        }
        return previous.brief
    }

    private func axSnippets(_ task: Task<[ScreenSnippet], Never>?) async -> [ScreenSnippet] {
        guard let task else { return [] }
        return await task.value
    }

    private func run(app: String?) async -> ScreenBrief {
        let start = Date()
        guard let jpeg = await capture.jpeg() else {
            Log.app("screen: skipped (no grant or capture failed)")
            return ScreenBrief()
        }
        if Task.isCancelled { return ScreenBrief() }
        Log.app("screen: captured \(jpeg.count)B in \(ms(since: start)) ms")
        let visionStart = Date()
        let brief = await vision.summarize(jpeg: jpeg, app: app)
        if Task.isCancelled { return ScreenBrief() }
        if let brief {
            Log.app(
                "screen: vision \(ms(since: visionStart)) ms "
                + "\(brief.snippets.count) snippets")
            return brief
        }
        return ScreenBrief()
    }

    /// No pid (never seen an app in front yet) is not an error: an empty
    /// AX read, same as an unpermitted one.
    private func runAX(pid: pid_t?, app: String?) async -> [ScreenSnippet] {
        guard let pid else { return [] }
        let start = Date()
        let texts = axHarvest(pid)
        if Task.isCancelled { return [] }
        let snippets = ScreenTextSnippets.snippets(from: texts, app: app ?? "")
        // Counts and milliseconds only — the text itself is untrusted DATA
        // and never belongs in the log (spec 15b §8).
        Log.app("screen: ax \(snippets.count) snippets in \(ms(since: start)) ms")
        return snippets
    }

    /// Not a task group: `withTaskGroup` awaits every child before it
    /// returns, and a child that only awaits `task.value` never notices the
    /// group was cancelled — so the old race waited for vision whatever
    /// `wait` said. DecisionGate cancels the task to unblock it; here the
    /// losing call must keep running for the next turn (15g-5), so the
    /// first of the two resumes a continuation and the other is ignored.
    private func race(_ task: Task<ScreenBrief, Never>, wait: Duration) async -> ScreenBrief? {
        let gate = FirstResume()
        return await withCheckedContinuation { continuation in
            gate.arm(continuation)
            Task { gate.resume(await task.value) }
            Task {
                do {
                    try await Task.sleep(for: wait)
                } catch {
                    // Sleep only throws on cancellation; nothing cancels it.
                }
                gate.resume(nil)
            }
        }
    }

    private func ms(since start: Date) -> Int {
        Int(Date().timeIntervalSince(start) * 1000)
    }
}

/// One continuation, resumed by whichever side of the race gets there first.
private final class FirstResume: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ScreenBrief?, Never>?

    func arm(_ continuation: CheckedContinuation<ScreenBrief?, Never>) {
        lock.withLock { self.continuation = continuation }
    }

    func resume(_ value: ScreenBrief?) {
        let pending: CheckedContinuation<ScreenBrief?, Never>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
    }
}
