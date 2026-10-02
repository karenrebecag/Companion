import CompanionCore
import Foundation

/// N2's port, narrowed to what the gate needs. `ArbiterClient`'s own type is
/// unchanged; this is the seam a fake substitutes in tests.
package protocol Arbitrating: Sendable {
    func arbitrate(
        utterance: String, shortlist: ArbitrationShortlist
    ) async -> (entry: ShortlistEntry, confidence: Double)?
}

extension ArbiterClient: Arbitrating {}

/// The executor DM1c-4 supplies for closed-set actions (volume, shortcut,
/// scroll, media, system ops) and the irreversible confirmations: `empty_
/// trash`, `quit_app`, `send_message`/`enter`, a submitted `type_text`. Nil
/// today — every one of those dispositions passes through to the model's own
/// path unchanged, exactly as wave-dm1-router.md §8 requires for DM1c-1.
package protocol SystemActing: Sendable {
    func supports(_ plan: Plan) -> Bool
    func act(_ plan: Plan) async -> Bool
}

/// A `.confirm(plan)` step, held open until the next hold turn answers it.
/// `attemptId` is the `MutationLedger` scope: every "sí" heard for THIS
/// question is one attempt, however many times it is repeated.
package struct PendingConfirmation: Sendable, Equatable {
    package var plan: Plan
    package var attemptId: String
    package var createdAt: Date
}

/// What `DecisionGate.run` produced. `declined` and the pending side of
/// `confirm` are DM1c-4 (`ApprovalMemory`-style session state); this delivery
/// only asks the question and hands back its text.
package enum DecisionOutcome: Sendable, Equatable {
    case passThrough(DecisionPassReason)
    case acted(ParentToolOutcome, ToolCallRef)
    case confirm(String)
    case declined
    case delegate(Handoff)
}

/// Sits in front of `ParentToolRunner.execute` (wave-dm1-router.md §8): N1
/// decides, `run` acts through the SAME runner the model would have used, so
/// `ParentToolPolicy` and the `open_url` said-it gate never see a shortcut.
/// DM1c-1 only: nothing here is called from `VoiceSession` yet.
package actor DecisionGate {
    private let provider: any DecisionProvider
    private let arbiter: any Arbitrating
    private let tools: any ParentToolExecuting
    private let system: (any SystemActing)?
    private let worldProvider: @Sendable () -> DecisionWorld
    private let budget: Duration
    private let now: @Sendable () -> Date
    /// wave-dm1-router.md §8: a still-open question from `run`'s `.confirm`
    /// case, answered by the classic hold's NEXT turn. One at a time — a
    /// second `.confirm` (a new irreversible plan) simply replaces it.
    private var pending: PendingConfirmation?
    /// "Registrar antes de observar" (§2): checked and recorded before
    /// `system.act` ever runs, so a doubled "sí" the ear delivers as two
    /// turns still mutates once — never in `ApprovalMemory` (§8: irreversible
    /// always confirms fresh, this ledger only dedupes ONE attempt).
    private var ledger = MutationLedger()
    /// What the first "sí" produced, replayed verbatim for a repeat one —
    /// the ledger says not to run `system.act` again, not what to say
    /// instead.
    private var confirmedOutcome: DecisionOutcome?
    private static let confirmationTTL: TimeInterval = 60

    package init(
        provider: any DecisionProvider,
        arbiter: any Arbitrating,
        tools: any ParentToolExecuting,
        system: (any SystemActing)? = nil,
        world: @escaping @Sendable () -> DecisionWorld,
        budget: Duration,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.arbiter = arbiter
        self.tools = tools
        self.system = system
        self.worldProvider = world
        self.budget = budget
        self.now = now
    }

    /// N1, and N2 when N1 could not pick alone. Races the whole cascade
    /// against `budget`; a slower provider loses the race and today's path
    /// takes over. `race` still waits for the cancelled loser to return, so
    /// this only holds for providers that honor cancellation (URLSession
    /// does). No side effects: nothing is executed here.
    package func plan(_ utterance: String, canDelegate: Bool) async -> DecisionStep {
        let world = worldProvider()
        let supports = systemSupports
        let provider = self.provider
        let arbiter = self.arbiter
        let work = Task<DecisionStep, Never> {
            await Self.route(
                utterance: utterance, world: world, canDelegate: canDelegate,
                supports: supports, provider: provider, arbiter: arbiter)
        }
        return await race(work, wait: budget) ?? .passThrough(.timedOut)
    }

    /// Runs a step already chosen by `plan`. `execute` goes through
    /// `ParentToolRunner` exactly as the model's own tool call would, and
    /// `open_url` still asks whether the user actually said the host before
    /// anything opens. A forged closed-set id or `type_text` span is refused
    /// at the door (`DecisionRoute.validClosedSet`), same as a forged path is
    /// refused by `ParentToolPolicy`.
    package func run(
        _ step: DecisionStep, utterance: String, language: AppLanguage
    ) async -> DecisionOutcome {
        log(step)
        switch step {
        case .passThrough(let reason):
            return .passThrough(reason)
        case .execute(let call, _):
            return await execute(call, utterance: utterance)
        case .system(let plan):
            guard let system, DecisionRoute.validClosedSet(plan) else {
                return .passThrough(.noExecutor)
            }
            guard await system.act(plan) else { return .passThrough(.failed) }
            let call = ToolCallRef(id: UUID().uuidString, name: plan.action.rawValue, arguments: "")
            return .acted(ParentToolOutcome(ok: true, output: "done"), call)
        case .confirm(let plan):
            guard DecisionRoute.validClosedSet(plan) else { return .passThrough(.noExecutor) }
            pending = PendingConfirmation(plan: plan, attemptId: UUID().uuidString, createdAt: now())
            confirmedOutcome = nil
            return .confirm(DecisionCopy.question(for: plan, language))
        case .delegate(let handoff):
            return .delegate(handoff)
        case .arbitrate:
            // `plan` always resolves N2 before returning; a raw `.arbitrate`
            // here means a caller skipped that step, not a real decision.
            return .passThrough(.unresolved)
        }
    }

    /// The classic hold's very next turn (wave-dm1-router.md §8), asked
    /// BEFORE `plan` sees `utterance`. `nil` means there was nothing to
    /// answer — no question was open, it aged past `confirmationTTL`, or the
    /// words heard were not a yes/no to it — and the caller routes
    /// `utterance` through `plan`/`run` exactly as any other turn, the same
    /// one that was just heard.
    package func answerConfirmation(_ utterance: String) async -> DecisionOutcome? {
        guard let confirmation = pending else { return nil }
        guard now().timeIntervalSince(confirmation.createdAt) < Self.confirmationTTL else {
            Log.chat("decision: confirmation expired")
            clearPending()
            return nil
        }
        guard let said = SpokenConfirmation.reading(utterance) else {
            // Unclear, or a fresh order (§8 "unrelated turn"): never guessed
            // — the question is gone and `utterance` falls through unchanged.
            Log.chat("decision: confirmation superseded")
            clearPending()
            return nil
        }
        guard said else {
            Log.chat("decision: confirmation declined")
            clearPending()
            return .declined
        }
        return await runConfirmed(confirmation)
    }

    /// `system.act` runs at most once per `attemptId`: the ledger is
    /// recorded before it runs, not after, so a "sí" heard twice for the
    /// same question replays the first result instead of mutating twice.
    /// Pending clears right after this confirmed run — a confirmation is
    /// answered by the very NEXT turn only (§8): the ledger entry above,
    /// not `pending`, is what stops the same attempt from mutating twice,
    /// so an unrelated later "sí" is free to fall through to `plan`/`run`
    /// like any other turn instead of replaying this outcome.
    private func runConfirmed(_ confirmation: PendingConfirmation) async -> DecisionOutcome {
        guard let system, let key = confirmation.plan.retryKey else {
            clearPending()
            return .passThrough(.noExecutor)
        }
        let (nextLedger, already) = ledger.recording(key, attempt: confirmation.attemptId)
        ledger = nextLedger
        if !already {
            let ok = await system.act(confirmation.plan)
            let call = ToolCallRef(
                id: UUID().uuidString, name: confirmation.plan.action.rawValue, arguments: "")
            confirmedOutcome = ok
                ? .acted(ParentToolOutcome(ok: true, output: "done"), call)
                : .passThrough(.failed)
        }
        let outcome = confirmedOutcome ?? .passThrough(.failed)
        clearPending()
        return outcome
    }

    private func clearPending() {
        pending = nil
        confirmedOutcome = nil
    }

    // MARK: - N1 → (N2 once) → route

    /// `Plan.compose`, routed; a `.arbitrate` result goes to N2 exactly once
    /// — the arbitrated entry becomes a `Plan` and is routed again, and if
    /// THAT is still `.arbitrate` (N2 itself unsure) this gives up rather
    /// than loop.
    private static func route(
        utterance: String, world: DecisionWorld, canDelegate: Bool,
        supports: @escaping @Sendable (Plan) -> Bool,
        provider: any DecisionProvider, arbiter: any Arbitrating
    ) async -> DecisionStep {
        let plan = await Plan.compose(utterance: utterance, world: world, provider: provider)
        let step = DecisionRoute.step(
            for: plan, world: world, canDelegate: canDelegate, systemSupports: supports)
        guard case .arbitrate(let shortlist, _) = step else { return step }
        guard let picked = await arbiter.arbitrate(utterance: utterance, shortlist: shortlist)
        else { return .passThrough(.failed) }
        let arbitrated = picked.entry.plan(
            utterance: utterance, confidence: picked.confidence, trust: nil)
        let second = DecisionRoute.step(
            for: arbitrated, world: world, canDelegate: canDelegate, systemSupports: supports)
        if case .arbitrate = second { return .passThrough(.unresolved) }
        return second
    }

    private var systemSupports: @Sendable (Plan) -> Bool {
        let system = self.system
        return { plan in system?.supports(plan) ?? false }
    }

    private func execute(_ call: ToolCallRef, utterance: String) async -> DecisionOutcome {
        if tools.approval(for: call, said: utterance) != nil {
            // A call that needs the sheet (a host the user did not say,
            // 10c 3D; Return in a terminal, 15g) takes today's path: this
            // gate cannot grant it on its own — abstain rather than deny.
            return .passThrough(.noExecutor)
        }
        let outcome = await tools.execute(name: call.name, argumentsJSON: call.arguments)
        return .acted(outcome, call)
    }

    /// Never the utterance text: only the shape of the decision.
    private func log(_ step: DecisionStep) {
        switch step {
        case .passThrough(let reason):
            Log.chat("decision: pass reason=\(reason.rawValue)")
        case .execute(_, let plan):
            Log.chat("decision: execute \(planLog(plan))")
        case .system(let plan):
            Log.chat("decision: system \(planLog(plan))")
        case .confirm(let plan):
            Log.chat("decision: confirm \(planLog(plan))")
        case .arbitrate(_, let plan):
            Log.chat("decision: arbitrate \(planLog(plan))")
        case .delegate:
            Log.chat("decision: delegate")
        }
    }

    private func planLog(_ plan: Plan) -> String {
        "action=\(plan.action.rawValue) confidence=\(plan.confidence) "
            + "disposition=\(plan.disposition.rawValue)"
    }

    /// Same shape as `JobQueue.race`: `task.cancel()` has to run INSIDE the
    /// group closure, before it returns — `withTaskGroup` otherwise awaits
    /// every child before handing control back, and a child that is only
    /// `await task.value` does not notice the group was cancelled; it just
    /// keeps waiting for `task` to finish on its own.
    private func race(_ task: Task<DecisionStep, Never>, wait: Duration) async -> DecisionStep? {
        await withTaskGroup(of: DecisionStep?.self) { group in
            group.addTask { await task.value }
            group.addTask {
                do {
                    try await Task.sleep(for: wait)
                } catch {
                    return nil
                }
                return nil
            }
            defer {
                group.cancelAll()
                task.cancel()
            }
            for await value in group {
                return value
            }
            return nil
        }
    }
}
