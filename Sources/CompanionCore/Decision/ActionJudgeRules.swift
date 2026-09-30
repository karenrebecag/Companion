import Foundation

// 16q-3a: the pure rules around the action coverage judge. Everything that
// decides (parse, summarise, route, pair, count) lives here so it is tested
// without a network; the adapter and the shadow only carry these out.

// MARK: - Verdict parser

/// Strict and fail-closed: anything outside the contract is `failed(.invalid)`,
/// which is never covered. A fault that cannot be pinned to one action (bad
/// envelope, an id the request never had) fails the whole batch.
package enum JudgeVerdictParser {
    private static let entryKeys: Set<String> = ["id", "covered", "reason"]
    /// A batch is at most 8 verdicts of about 60 bytes each; 16 KB is generous
    /// and still stops a hostile or runaway body before it is read.
    package static let maxBodyBytes = 16 * 1024
    /// Twice the batch cap: room for a repeated id, not for a flood.
    package static let maxEntries = 16

    package static func parse(_ data: Data, ids: [String]) -> [JudgeVerdict] {
        let rejected = ids.map { _ in JudgeVerdict.failed(.invalid) }
        guard data.count <= maxBodyBytes,
              case .object(let root)? = JSONValue.parse(data),
              Set(root.keys) == ["verdicts"],
              case .array(let entries)? = root["verdicts"],
              entries.count <= maxEntries
        else { return rejected }

        var byID: [String: [[String: JSONValue]]] = [:]
        for entry in entries {
            guard case .object(let object) = entry,
                  case .string(let id)? = object["id"],
                  ids.contains(id)
            else { return rejected }
            byID[id, default: []].append(object)
        }
        return ids.map { id in
            guard let found = byID[id], found.count == 1, let entry = found.first else {
                return .failed(.invalid)
            }
            return verdict(of: entry)
        }
    }

    private static func verdict(of entry: [String: JSONValue]) -> JudgeVerdict {
        guard Set(entry.keys) == entryKeys,
              case .bool(let covered)? = entry["covered"],
              case .string(let raw)? = entry["reason"],
              let reason = JudgeReason(rawValue: raw)
        else { return .failed(.invalid) }
        if covered { return reason == .asked ? .covered : .failed(.invalid) }
        return reason == .asked ? .failed(.invalid) : .notCovered(reason)
    }
}

// MARK: - Provider route

/// Rule: no new recipient for the turn's words. Realtime already sent them to
/// OpenAI; classic uses the hold brain's own chain, in its own order. Ollama
/// takes the model `LocalCatalog` confirmed at runtime: the static default tag
/// may not be installed, and it 404s.
package enum ActionJudgeRoute {
    package static func provider(pipeline: VoicePipeline, keys: Set<SecretKey>,
                                ollamaModel: String?) -> ProviderDescriptor? {
        let openAI = ProviderDescriptor.openAI.withModel(HoldBrainCatalog.openAIModel)
        switch pipeline {
        case .realtime:
            return openAI
        case .classic:
            if keys.contains(.cerebras) { return .cerebras }
            if keys.contains(.openAI) { return openAI }
            guard let model = ollamaModel?.trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty else {
                return nil
            }
            return ProviderDescriptor.ollama.withModel(model)
        }
    }
}

// MARK: - Ledger

/// Remembers verdicts and decisions until both sides of a version are known.
/// Immutable: every write returns the next ledger, so the shadow actor holds
/// the only mutable reference. Time is a parameter, which is the injected
/// clock: the ledger never reads one.
package struct JudgeLedger: Sendable, Equatable {
    package static let capacity = 32
    package static let ttl: TimeInterval = 120

    package struct Pair: Sendable, Equatable {
        package let verdict: JudgeVerdict
        package let decision: ApprovalDecision
        package let verdictFirst: Bool
        /// From the moment the version was first seen to the decision.
        package let msDecision: Int

        package init(verdict: JudgeVerdict, decision: ApprovalDecision, verdictFirst: Bool, msDecision: Int) {
            self.verdict = verdict
            self.decision = decision
            self.verdictFirst = verdictFirst
            self.msDecision = msDecision
        }
    }

    private struct Entry: Sendable, Equatable {
        let version: ActionVersion
        let openedAt: TimeInterval
        var verdict: JudgeVerdict?
        var verdictAt: TimeInterval?
        var decision: ApprovalDecision?
        var decisionAt: TimeInterval?
    }

    private let entries: [Entry]

    package init() {
        entries = []
    }

    private init(entries: [Entry]) {
        self.entries = entries
    }

    package var count: Int { entries.count }

    /// The action is proposed before the judge answers or the sheet resolves.
    /// Opening its entry at that moment is what lets `msDecision` measure the
    /// user's whole wait, and not start at whichever side happened to land first.
    package func opening(_ version: ActionVersion, at time: TimeInterval) -> JudgeLedger {
        apply(to: version, at: time) { _ in }.ledger
    }

    package func recording(verdict: JudgeVerdict, for version: ActionVersion,
                          at time: TimeInterval) -> (ledger: JudgeLedger, pair: Pair?) {
        apply(to: version, at: time) { entry in
            // One truth per version: a second verdict (the classic batch and
            // the guard can both judge the same action) does not rewrite the
            // first, or `verdictFirst` would move with every repeat.
            guard entry.verdict == nil else { return }
            entry.verdict = verdict
            entry.verdictAt = time
        }
    }

    /// Only approved and denied are comparable with a verdict; an expiry, a
    /// cancel or a spoken resolution says nothing about the judge, so it frees
    /// the entry and stays out of the metric.
    ///
    /// When that decision beats its verdict, the late verdict finds no entry
    /// and opens a verdict-only one. It is left to age out by TTL (or LRU
    /// eviction) rather than tombstoning the version: a tombstone would be one
    /// more entry to bound, and a verdict alone never pairs, so it cannot
    /// reach the metric.
    package func recording(decision: ApprovalDecision, for version: ActionVersion,
                          at time: TimeInterval) -> (ledger: JudgeLedger, pair: Pair?) {
        apply(to: version, at: time) { entry in
            entry.decision = decision
            entry.decisionAt = time
        }
    }

    private func apply(to version: ActionVersion, at time: TimeInterval,
                       _ change: (inout Entry) -> Void) -> (ledger: JudgeLedger, pair: Pair?) {
        // The TTL runs from `openedAt` and a touch does not renew it. That is
        // safe: `ApprovalTiming.autoDeny` is 60 s, under the 120 s TTL, so a
        // sheet that is still live always resolves inside it, and an entry
        // older than that belongs to a sheet that is gone.
        var live = entries.filter { time - $0.openedAt < Self.ttl }
        var entry: Entry
        if let index = live.firstIndex(where: { $0.version == version }) {
            entry = live.remove(at: index)
        } else {
            entry = Entry(version: version, openedAt: time)
        }
        change(&entry)

        if let decision = entry.decision, ![.approved, .denied].contains(decision) {
            return (JudgeLedger(entries: live), nil)
        }
        if let verdict = entry.verdict, let decision = entry.decision,
           let verdictAt = entry.verdictAt, let decisionAt = entry.decisionAt {
            let pair = Pair(verdict: verdict, decision: decision, verdictFirst: verdictAt <= decisionAt,
                            msDecision: Int(((decisionAt - entry.openedAt) * 1000).rounded()))
            return (JudgeLedger(entries: live), pair)
        }
        live.append(entry)
        return (JudgeLedger(entries: Array(live.suffix(Self.capacity))), nil)
    }
}

// MARK: - Agreement

/// The counters spec 12 reads to decide whether to propose 16q-4. `failed`
/// is a cell of its own: it never feeds a covered or an agreement counter.
package struct JudgeAgreement: Sendable, Equatable, CustomStringConvertible {
    package private(set) var judged = 0
    package private(set) var failed = 0
    package private(set) var paired = 0
    package private(set) var approved = 0
    package private(set) var denied = 0
    package private(set) var falseCover = 0
    package private(set) var coveredApproved = 0
    package private(set) var notCoveredDenied = 0
    package private(set) var onTime = 0
    /// The shadow lives as long as the app, so an unbounded sample list grows
    /// for weeks. A thousand recent samples keep p95 meaningful (50 above it)
    /// and follow the provider as it is now, not as it was at launch.
    static let maxLatencySamples = 1000
    private(set) var latencies: [Int] = []

    package init() {}

    package func recording(_ verdict: JudgeVerdict, ms: Int) -> JudgeAgreement {
        var next = self
        next.judged += 1
        next.latencies = Array((latencies + [ms]).suffix(Self.maxLatencySamples))
        if case .failed = verdict { next.failed += 1 }
        return next
    }

    package func recording(_ pair: JudgeLedger.Pair) -> JudgeAgreement {
        var next = self
        next.paired += 1
        if pair.verdictFirst { next.onTime += 1 }
        let approvedByUser = pair.decision == .approved
        if approvedByUser { next.approved += 1 } else { next.denied += 1 }
        switch (pair.verdict, approvedByUser) {
        case (.covered, true): next.coveredApproved += 1
        case (.covered, false): next.falseCover += 1
        case (.notCovered, false): next.notCoveredDenied += 1
        case (.notCovered, true), (.failed, _): break
        }
        return next
    }

    package var agreementRate: Double? { ratio(coveredApproved + notCoveredDenied, paired) }
    package var utilityRate: Double? { ratio(coveredApproved, approved) }
    package var failRate: Double? { ratio(failed, judged) }
    package var onTimeRate: Double? { ratio(onTime, paired) }

    /// Nearest rank, so p95 of a hundred samples is the 95th, not an average.
    package func latency(percentile: Double) -> Int? {
        guard !latencies.isEmpty else { return nil }
        let rank = Int((percentile * Double(latencies.count)).rounded(.up))
        return latencies.sorted()[min(max(rank, 1), latencies.count) - 1]
    }

    private func ratio(_ part: Int, _ whole: Int) -> Double? {
        whole == 0 ? nil : Double(part) / Double(whole)
    }

    package var description: String {
        "paired=\(paired) false_cover=\(falseCover) covered_approved=\(coveredApproved) "
            + "approved=\(approved) not_covered_denied=\(notCoveredDenied) failed=\(failed) on_time=\(onTime)"
    }
}

// MARK: - Local rules

/// What is decided without asking the model. The adapter (3b) sends the model
/// only `askable(in:)` and puts the answer back with `combine`.
package enum ActionJudgeLocalRules {
    /// nil means the model may be asked. An action whose summary is incomplete
    /// fails closed: the judge would be deciding on a destination it was not
    /// fully shown.
    package static func verdict(for action: ProposedAction) -> JudgeVerdict? {
        action.isComplete ? nil : .failed(.invalid)
    }

    package static func askable(in request: ActionJudgeRequest) -> [ProposedAction] {
        request.actions.filter { verdict(for: $0) == nil }
    }

    /// One verdict per action, in order. If the model did not answer exactly
    /// the actions it was asked about, none of its answers is believed.
    package static func combine(_ request: ActionJudgeRequest, modelVerdicts: [JudgeVerdict]) -> [JudgeVerdict] {
        // An unbelieved batch leaves no answers to hand out, so every asked
        // action reaches the fallback and fails closed.
        var answers = modelVerdicts.count == askable(in: request).count ? modelVerdicts[...] : []
        return request.actions.map { action in
            verdict(for: action) ?? answers.popFirst() ?? .failed(.invalid)
        }
    }
}
