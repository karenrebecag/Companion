import CompanionCore
import Foundation

/// Wave 15b-10: the classic turn as its own cancellable unit of work. A
/// press that lands while it thinks or speaks has to reach the actor and
/// cut it without waiting for `classic.submit` to hit an await point on its
/// own — structured cancellation never reaches code that is not itself a
/// child of the cancelled task, so `classic.submit` needs a task of its own
/// to be cancellable at all. Split out of `VoiceSession.swift` (0 net lines
/// there, spec budget).
extension VoiceSession {
    /// Starts the classic turn in its own task, replacing any turn already
    /// in flight — `.cancelAgentOutput` already cancelled the previous one
    /// before this effect runs, but a stray double `.submitUtterance` must
    /// still never run two turns at once.
    func startClassicTurn(config: Config) {
        classicTurnTask?.cancel()
        let endsHold = machine.snapshot.holdArmed
        let pressed = timeline.pressed
        classicTurnTask = Task { [weak self] in
            guard let self else { return }
            await self.classic.submit(config: config, endsHold: endsHold, pressed: pressed) { event in
                await self.apply(event)
            }
        }
    }

    /// `.cancelAgentOutput` on the classic pipeline: stop the turn task, the
    /// voice already speaking, and any vision still uploading — the hold
    /// that follows must never race what this one was doing.
    func cancelClassicTurn() async {
        classicTurnTask?.cancel()
        classicTurnTask = nil
        await cutAnnouncement()
        await synthesizer.stop()
        screen?.cancel()
    }

    /// Test-only seam: with the turn now a detached task, a test that wants
    /// its outcome has to wait for it explicitly instead of relying on
    /// `hold()`/`release()` returning only once the reply is in.
    func awaitClassicTurn() async {
        await classicTurnTask?.value
    }
}
