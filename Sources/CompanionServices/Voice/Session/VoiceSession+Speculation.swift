import CompanionCore
import Foundation

/// The decision planned on the hold's stable partial, so the router's answer
/// is ready when the key comes up instead of starting at the release. Only a
/// plan: `DecisionGate.prepare` executes nothing, and the release reuses it
/// only for exactly the same words.
extension VoiceSession {
    /// How long a partial must stay unchanged before it is planned on. The
    /// ear revises the last word several times a second while speech goes
    /// on; planning every revision would send each one out to be judged.
    static let speculationSettle: Duration = .milliseconds(300)

    /// Called with each new classic partial. A new partial voids the plan
    /// made on the previous one.
    func notePartialForDecision(_ text: String) {
        speculationTimer?.cancel()
        speculationTimer = nil
        if speculation?.text != text { cancelSpeculation() }
        guard attachedDecision != nil, !text.isEmpty, speculation == nil else { return }
        speculationTimer = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.speculationSettle)
            } catch {
                return
            }
            await self?.startSpeculation(text)
        }
    }

    private func startSpeculation(_ text: String) async {
        guard holdOpen, lastPartial == text, speculation == nil,
              let (gate, judge) = attachedDecision
        else { return }
        let turn = judge.map { turnJudge(text, $0) }
        guard routerSkip(hosted: turn?.usesHostedJudge ?? false) == nil else { return }
        // A yes/no to an open question is answered on the Mac at the release.
        guard await !gate.answersPendingConfirmation(text) else { return }
        // The partial may have moved on while the gate was asked.
        guard lastPartial == text, speculation == nil else { return }
        let task = await gate.prepare(text, canDelegate: classic.onDelegate != nil, provider: turn)
        speculation = (text, task)
    }

    /// The plan made on these exact words, handed over once; any other words
    /// cancel it.
    func takeSpeculation(matching utterance: String) -> Task<DecisionStep, Never>? {
        speculationTimer?.cancel()
        speculationTimer = nil
        guard let held = speculation else { return nil }
        speculation = nil
        guard held.text == utterance else {
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
