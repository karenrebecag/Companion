import CompanionCore
import Foundation

/// Puente QA: what a turn did, recorded as it runs so an agent can read it
/// back (`companion_ask` / `companion_wait_turn`). The record is memory only
/// and holds the words; `TurnResult` decides what leaves the process.
extension ChatViewModel {
    func beginRecord(origin: MessageOrigin) -> String {
        let id = UUID().uuidString
        var record = TurnRecord(turnId: id, conversationId: conversationId, origin: Self.originName(origin))
        record.mark(.started, atMs: 0)
        liveTurn = record
        turnStartedAt = now()
        return id
    }

    /// Edits the live record.
    func recording(_ change: (inout TurnRecord) -> Void) {
        guard var record = liveTurn else { return }
        change(&record)
        liveTurn = record
    }

    func markPhase(_ phase: TurnPhase) {
        let at = elapsedMs
        recording { $0.mark(phase, atMs: at) }
    }

    func finishRecord(_ status: TurnStatus) {
        guard var record = liveTurn else { return }
        record.status = status
        record.elapsedMs = elapsedMs
        record.pendingOwner = nil
        switch status {
        case .completed: record.mark(.completed, atMs: record.elapsedMs)
        case .failed: record.mark(.failed, atMs: record.elapsedMs)
        case .cancelled:
            record.mark(.cancelled, atMs: record.elapsedMs)
            // A hold, a switch of conversation or a new one cut it: say so.
            record.error = record.error ?? TurnFault(
                code: BridgeCode.interrupted, message: "the turn was cut before it finished")
        case .running, .awaitingOwner: break
        }
        turnRing = turnRing.appending(record)
        liveTurn = nil
        turnStartedAt = nil
        onTurnEvent?(record.turnId, .finished)
    }

    private var elapsedMs: Int {
        guard let start = turnStartedAt else { return 0 }
        return max(0, Int(now().timeIntervalSince(start) * 1000))
    }

    private static func originName(_ origin: MessageOrigin) -> String {
        switch origin {
        case .typed: "typed"
        case .choice: "choice"
        case .agent: "agent"
        }
    }

    /// The live turn or a finished one in the ring.
    package func turnRecord(_ id: String) -> TurnRecord? {
        if let live = liveTurn, live.turnId == id {
            var snapshot = live
            snapshot.elapsedMs = elapsedMs
            return snapshot
        }
        return turnRing.record(id)
    }

    /// The system's owner dialog opened or closed for a critical action: the
    /// island says so, and an agent waiting on this turn is woken to tell the
    /// person to touch the sensor.
    package func ownerCheckChanged(open: Bool, tool: String) {
        session.send(.ownerCheck(open: open))
        guard var record = liveTurn else { return }
        record.status = open ? .awaitingOwner : .running
        record.pendingOwner = open
            ? TurnPendingOwner(tool: tool, band: "critical", reason: ApprovalCopy.ownerReason(config.language, tool: tool))
            : nil
        if open { record.mark(.ownerCheck, atMs: elapsedMs) }
        liveTurn = record
        onTurnEvent?(record.turnId, open ? .ownerCheckOpened : .ownerCheckClosed)
    }

    /// Types a turn as the bridge's agent. A turn already running is never cut
    /// by it: only the user's own words cut a turn.
    package func askAsAgent(text: String, newConversation: Bool, asUserWords: Bool) -> QAAskStart {
        guard !needsOnboarding else { return .unavailable }
        if busy, let live = liveTurn { return .busy(turnId: live.origin == "agent" ? live.turnId : nil) }
        if newConversation { self.newConversation() }
        errorText = nil
        let id = startTurn(text, origin: .agent, asUserWords: asUserWords)
        return .started(turnId: id, conversationId: conversationId)
    }
}
