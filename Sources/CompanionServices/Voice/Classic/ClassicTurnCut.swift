import Foundation
import Synchronization

/// Why one classic turn was cut, created with the turn so the cause reaches
/// its `cutTurn` whenever that runs. A flag on the runtime could not say
/// which turn a stop meant: the next turn may already be waiting, or the
/// stopped one may have finished and never cut at all (R3,
/// interrupciones-por-causa).
final class ClassicTurnCut: Sendable {
    private let stopped = Mutex(false)

    /// Sticky: a press that lands after a stop does not undo it, the user
    /// still stopped that turn.
    func stop() {
        stopped.withLock { $0 = true }
    }

    var leavesSteerNote: Bool {
        stopped.withLock { !$0 }
    }
}
