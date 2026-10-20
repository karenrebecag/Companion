import CompanionCore
import Foundation

/// Typed words through the router a hold uses (`TurnDeciding`): what it
/// answers never reaches the brain, and a pass-through reaches it with the
/// delegation head's verdict applied. Only her own typed words: a card pick
/// or the QA bridge's text are not hers to act on.
extension ChatViewModel {
    /// True when the router answered the turn and the turn is over.
    func answeredByRouter(_ text: String, conversationId id: String) async -> Bool {
        guard let decider else { return false }
        if openQuestionStale {
            openQuestionStale = false
            await decider.dropOpenQuestion()
        }
        let decided = await decider.decide(text, canDelegate: jobSubmitter != nil)
        // Something already moved: a cut turn must not carry these words into
        // the next one and act on them twice.
        if case .acted = decided.outcome { turnToolsRan = true }
        // A switch or a clear took the turn meanwhile: nothing is shown in a
        // thread that is gone, the brain is not asked, and a question asked
        // there is never left open for a later yes.
        guard conversationId == id, !Task.isCancelled else {
            if case .confirm = decided.outcome { await decider.dropOpenQuestion() }
            return true
        }
        let language = config.language
        switch decided.outcome {
        case .passThrough:
            delegateWithdrawn = decided.withdrawsDelegate
            return false
        case .acted(let outcome, let call):
            reply(DecisionCopy.acted(outcome, tool: call.name, language), failed: !outcome.ok)
        case .confirm(let question), .said(let question):
            reply(question)
        case .declined:
            reply(DecisionCopy.declined(language))
        case .delegate(let handoff):
            if let submitter = jobSubmitter {
                await runJob(preface: "", handoff: handoff, submitter: submitter)
            } else {
                messages.append(ChatMessage(isStatus: true, text: ChatCopy.handoffUnavailable(handoff)))
            }
        }
        guard conversationId == id else { return true }
        run = run?.finishing(at: now())
        persist()
        endTurn()
        return true
    }

    /// The chat moved on from the router's open question. Dropped now, not at
    /// the next typed turn: the hold shares the gate, and a spoken "sí" must
    /// not answer a question the thread left behind. The flag still makes the
    /// next typed turn wait for the drop, which this unordered task cannot.
    func dropOpenQuestion() {
        openQuestionStale = true
        guard let decider else { return }
        Task { await decider.dropOpenQuestion() }
    }

    /// The brain is told why it cannot hand off, so a prompt that describes
    /// delegation never has it promise one this turn cannot make.
    func noteWithdrawnDelegate(_ history: [Turn]) -> [Turn] {
        guard delegateWithdrawn, let last = history.indices.last, history[last].role == .user
        else { return history }
        var noted = history
        noted[last].content = DelegationHead.withdrawnNote + "\n" + noted[last].content
        return noted
    }

    private func reply(_ text: String, failed: Bool = false) {
        messages.append(ChatMessage(role: .assistant, text: text))
        recording { $0.reply = TurnReply(text: text, isFailure: failed) }
    }
}
