import CompanionCore
import Foundation

/// A plan made on the hold's stable partial, with what it was made against.
struct Speculation {
    var text: String
    var canDelegate: Bool
    var world: DecisionWorld
    var task: Task<DecisionStep, Never>
}

/// The decision planned on the hold's stable partial, so the router's answer
/// is ready when the key comes up instead of starting at the release. Only a
/// plan: `DecisionGate.routing` executes nothing, and the release reuses it
/// only for exactly the same words, against the same world.
extension VoiceSession {
    /// How long a partial must stay unchanged before it is planned on. The
    /// ear revises the last word several times a second while speech goes
    /// on; planning every revision would send each one out to be judged.
    static let speculationSettle: Duration = .milliseconds(300)
    /// A long dictation pauses every half second; with a hosted judge each
    /// plan is a request carrying words the user may still revise. Commands
    /// are short: two plans cover a revision of the first, and the release
    /// plans anything after that.
    static let speculationsPerHold = 2

    /// Two words at least, and not the last plan plus one word: a phrase
    /// that only grew by its next word is the same request, still forming.
    static func worthSpeculating(_ text: String, after previous: String?) -> Bool {
        let words = text.split(whereSeparator: \.isWhitespace)
        guard words.count >= 2 else { return false }
        guard let previous else { return true }
        let before = previous.split(whereSeparator: \.isWhitespace)
        let grewByOne = words.count == before.count + 1 && Array(words.prefix(before.count)) == before
        return !grewByOne
    }

    /// Called with each new classic partial. A new partial voids the plan
    /// made on the previous one.
    func notePartialForDecision(_ text: String) {
        speculationTimer?.cancel()
        speculationTimer = nil
        if speculation?.text != text { cancelSpeculation() }
        guard attachedDecision != nil, speculation == nil,
              speculationsThisHold < Self.speculationsPerHold,
              Self.worthSpeculating(text, after: lastSpeculatedText)
        else { return }
        speculationTimer = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.speculationSettle)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.startSpeculation(text)
        }
    }

    /// No await between the checks and the task: a release or a teardown
    /// either happened before (and the checks fail) or comes after (and
    /// cancels the task it finds).
    private func startSpeculation(_ text: String) {
        guard holdOpen, lastPartial == text, speculation == nil,
              speculationsThisHold < Self.speculationsPerHold,
              let (gate, judge) = attachedDecision
        else { return }
        let turn = judge.map { turnJudge(text, $0) }
        guard routerSkip(hosted: turn?.usesHostedJudge ?? false) == nil else { return }
        speculationsThisHold += 1
        lastSpeculatedText = text
        let canDelegate = classic.onDelegate != nil
        let world = gate.world()
        let task = Task<DecisionStep, Never> {
            // A yes/no to an open question is answered on the Mac at the
            // release; it is never sent out as a partial.
            if await gate.answersPendingConfirmation(text) { return .passThrough(.unresolved) }
            // Cancelled before it first ran: nothing goes out to the judge.
            guard !Task.isCancelled else { return .passThrough(.unresolved) }
            return await gate.routing(text, canDelegate: canDelegate, provider: turn, world: world)
        }
        speculation = Speculation(text: text, canDelegate: canDelegate, world: world, task: task)
    }

    /// The plan made on these exact words against this same world, handed
    /// over once; anything else cancels it and the release plans afresh.
    func takeSpeculation(
        matching utterance: String, canDelegate: Bool, world: DecisionWorld
    ) -> Task<DecisionStep, Never>? {
        speculationTimer?.cancel()
        speculationTimer = nil
        guard let held = speculation else { return nil }
        speculation = nil
        guard held.text == utterance, held.canDelegate == canDelegate, held.world == world else {
            held.task.cancel()
            return nil
        }
        Log.chat("decision: plan reused from the partial")
        return held.task
    }

    func cancelSpeculation() {
        speculationTimer?.cancel()
        speculationTimer = nil
        speculation?.task.cancel()
        speculation = nil
    }
}
