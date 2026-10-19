import CompanionCore
import Foundation

/// A judge that lives behind a key: present only while that key is saved.
package protocol HostedDecisionProviding: DecisionProvider {
    var isConfigured: Bool { get }
    /// A copy whose configuration no longer changes under it.
    func pinned() -> any HostedDecisionProviding
}

extension HostedDecisionProviding {
    package func pinned() -> any HostedDecisionProviding { self }
}

extension TypeSafeDecisionProvider: HostedDecisionProviding {
    package func pinned() -> any HostedDecisionProviding {
        let held: TypeSafeDecisionProvider = pinned()
        return held
    }
}

/// The decision judge the app actually asks: Jev while its key is saved, the
/// local judge otherwise. Picked per call, not at launch, so a key pasted in
/// Ajustes counts from the next hold and the Keychain is never read at boot.
/// Without the key nothing is ever sent to TypeSafe.
package struct DecisionJudge: DecisionProvider, Sendable {
    private let hosted: any HostedDecisionProviding
    private let local: any DecisionProvider
    private let pinnedHosted: Bool?

    package init(hosted: any HostedDecisionProviding, local: any DecisionProvider) {
        self.init(hosted: hosted, local: local, pinnedHosted: nil)
    }

    private init(hosted: any HostedDecisionProviding, local: any DecisionProvider, pinnedHosted: Bool?) {
        self.hosted = hosted
        self.local = local
        self.pinnedHosted = pinnedHosted
    }

    /// The judge for one turn: which judge, and its key, decided now and
    /// held, so a key saved or removed mid-turn waits for the next hold.
    package func pinned() -> DecisionJudge {
        let held = hosted.pinned()
        return DecisionJudge(hosted: held, local: local, pinnedHosted: held.isConfigured)
    }

    /// The hosted judge has its own key and costs no local model, so it is
    /// not bound by the local toggle or the fast-brain skip; the session
    /// reads this to decide whether the router runs at all.
    package var usesHostedJudge: Bool { pinnedHosted ?? hosted.isConfigured }

    package var answersInOneRequest: Bool { usesHostedJudge }

    package func answer(_ question: DecisionQuestion) async -> DecisionAnswer? {
        usesHostedJudge ? await hosted.answer(question) : await local.answer(question)
    }

    package func answer(_ questions: [DecisionQuestion]) async -> [DecisionAnswer?] {
        usesHostedJudge ? await hosted.answer(questions) : await local.answer(questions)
    }

    /// Hosted only: the local 4B was never measured on this head, and an
    /// unmeasured judge must not be the one taking a tool away.
    package func delegationVerdict(_ utterance: String) async -> DecisionAnswer? {
        guard usesHostedJudge else { return nil }
        return await hosted.answer(DelegationHead.question(utterance))
    }

    /// The verdict if it is in within `wait`, else nil (every tool stays).
    /// The cancel runs inside the group for the reason `DecisionGate.race`
    /// gives: a child awaiting `task.value` does not notice the group ending.
    static func verdict(
        _ task: Task<DecisionAnswer?, Never>?, within wait: Duration
    ) async -> DecisionAnswer? {
        guard let task else { return nil }
        return await withTaskGroup(of: DecisionAnswer?.self) { group in
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
