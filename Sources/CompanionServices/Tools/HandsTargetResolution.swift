import Foundation

extension ScreenHands {
    /// What a hands call does with the pin, the caller lineage and the front.
    /// `ready` is the only way forward; every other case is a refusal the
    /// runner words, and approval treats them all as "no sheet".
    enum TargetResolution: Sendable, Equatable {
        case noFront
        case targetLost(message: String)
        case targetChanged(message: String)
        case windowLost
        case ready(pid: Int32, frontIsCaller: Bool)
    }

    static let targetLostMessage =
        "the app to act on is not pinned; ask the user to bring it to the "
        + "front, or call open_app, then look"

    /// One text for every refusal that comes from the window: the entry
    /// check, the act-time check and a window that changed during `look`.
    static let windowLostMessage =
        "the window look returned is gone or no longer in front in its app; call look again"

    static let targetChangedMessage =
        "the app in front is not the one the user was in; "
        + "ask the user to bring that app to the front, then retry"

    static let callerFrontFocusMessage =
        "focus_window does not re-pin while the agent's own app is in front; "
        + "bring the app to act on to the front, then call look"

    /// The judgment `runHands` and the approval sheet share, so a sheet is
    /// never shown for a call execute will refuse. MCP callers wrap the call
    /// in `HandsCaller.$apps.withValue(lineage)`; voice and chat do not, so
    /// the front's word is final for them.
    ///
    /// `exemptFromWindow` is for `look` and `focus_window`: with the user's
    /// own app in front, re-latching to what they look at is their choice.
    /// With a caller in front it never applies: an agent must not loop
    /// target_lost -> look onto a window the user switched to.
    ///
    /// `commitRepin` is false for approval: a sheet only asks, and taking the
    /// pending repin there would pin before the call that owns it runs.
    func resolveTarget(exemptFromWindow: Bool = false, commitRepin: Bool = true) -> TargetResolution {
        guard let front = target(), front != ownPID else { return .noFront }
        let snapshot = turn.snapshot()
        if HandsCaller.apps.contains(front) {
            guard let pinned = snapshot.pid, callerFrontHolds(snapshot: snapshot, pid: pinned) else {
                return .targetLost(message: Self.targetLostMessage)
            }
            return windowHolds(pid: pinned)
                ? .ready(pid: pinned, frontIsCaller: true) : .windowLost
        }
        if snapshot.repin {
            // A fresh pin has no window or bundle yet, so there is nothing
            // further to compare.
            if commitRepin { _ = turn.pin(for: front) }
            return .ready(pid: front, frontIsCaller: false)
        }
        if let spoken = snapshot.pid, spoken != front {
            return .targetChanged(message: Self.targetChangedMessage)
        }
        guard bundleHolds(snapshot: snapshot, pid: front, requireStored: false) else {
            return .targetLost(message: Self.targetLostMessage)
        }
        guard exemptFromWindow || windowHolds(pid: front) else { return .windowLost }
        return .ready(pid: front, frontIsCaller: false)
    }

    /// The act-time twin of `resolveTarget`, read right before a hand acts
    /// (security review 2026-09-25 M4). It applies the same rules, so a
    /// change of any kind between the entry check and the action refuses.
    func holds(pid: Int32) -> Bool { holds(pid: pid, checkWindow: true) }

    /// `focus_window` changes the window on purpose; only the app is held.
    func holdsForExemptTool(pid: Int32) -> Bool { holds(pid: pid, checkWindow: false) }

    private func holds(pid: Int32, checkWindow: Bool) -> Bool {
        let snapshot = turn.snapshot()
        if let pinned = snapshot.pid, pinned != pid { return false }
        guard let front = target(), front != ownPID else { return false }
        if HandsCaller.apps.contains(front) {
            guard callerFrontHolds(snapshot: snapshot, pid: pid) else { return false }
        } else {
            guard front == pid, bundleHolds(snapshot: snapshot, pid: pid, requireStored: false) else {
                return false
            }
        }
        return !checkWindow || windowHolds(pid: pid)
    }

    /// The caller-fronted conditions, read from one snapshot so a torn read
    /// cannot pass: the pin is this pid, which is neither Companion nor part
    /// of the caller's own lineage (a pin on the terminal itself would let
    /// the agent type into its own prompt), a window was latched by `look`,
    /// and the bundle the pid resolves to now is the one stored when it was
    /// pinned. A missing stored bundle refuses: a call that rides on a
    /// caller's front needs a known app behind the pid.
    private func callerFrontHolds(snapshot: TurnTarget.Snapshot, pid: Int32) -> Bool {
        guard snapshot.pid == pid, pid != ownPID, !HandsCaller.apps.contains(pid),
              snapshot.window != nil
        else { return false }
        return bundleHolds(snapshot: snapshot, pid: pid, requireStored: true)
    }

    /// A pid can be recycled by a different app between the look and the
    /// call; the bundle stored at the pin catches it. Without a stored
    /// bundle nothing can be compared, which only a caller-fronted call
    /// refuses.
    private func bundleHolds(snapshot: TurnTarget.Snapshot, pid: Int32, requireStored: Bool) -> Bool {
        guard let stored = snapshot.bundle else { return !requireStored }
        return bundleID(pid) == stored
    }

    /// The latched window must still be the one in front in its app. Without
    /// a latch the pin is for the app alone (a spoken turn that never
    /// looked). With one, a front window that is gone refuses: nothing safe
    /// is left to act on.
    func windowHolds(pid: Int32) -> Bool {
        guard let latched = turn.snapshot().window else { return true }
        guard let current = frontWindow(pid) else { return false }
        return latched == current
    }

    private var ownPID: Int32 { ProcessInfo.processInfo.processIdentifier }
}
