import Foundation

/// Wave 17. Pure session state machine for the bridge: no I/O, no clocks.
/// Every method takes `now: Date` so tests can advance time programmatically.
///
/// Flow: idle (no one asking) → listed (hello received; tools published)
/// → awaitingApproval (first call; user sees sheet) → open (approved)
/// → paused (voice turn; Karen is speaking) → open (voice turn done).
/// The approval sheet moves to the first call, not hello, because Claude Code
/// launches MCP servers at startup and would pop a sheet on every launch.
public enum BridgeState: Sendable, Equatable {
    case idle
    case listed
    case awaitingApproval
    case open(until: Date?)
    case paused(until: Date?)
    case closed
}

public enum BridgeVerdict: Sendable, Equatable {
    case proceed
    case needsApproval
    case reject(code: String)
}

/// Pure policy for session authorization and rate limiting. The write budget
/// counts towards a sliding window; read tools bypass it entirely.
public struct BridgePolicy: Sendable, Equatable {
    /// The tool name the session-grant approval carries. Not an executable
    /// tool: it exists so the reducer and the sheet can tell the bridge's
    /// ask apart from a job's (`ApprovalKey.from` refuses to remember it).
    public static let sessionApprovalTool = "bridge_session"

    public static let writeTools: Set<String> = [
        "click",
        "type_text",
        "press_key",
        "scroll",
        "menu",
        "open_app",
        "open_url",
        "open_file"
    ]

    public static let budgetPerMinute = 30
    public static let window: TimeInterval = 60

    public private(set) var state: BridgeState

    /// Absolute timestamps of write operations. Pruned to keep only writes
    /// within the current window on each write-tool admit.
    private var writeTimestamps: [Date]

    public init() {
        self.state = .idle
        self.writeTimestamps = []
    }

    /// Called when hello is received. Transitions from idle or closed to listed
    /// (tools published), or from listed to listed (client listing again),
    /// or rejects if already in an active session (awaitingApproval, open, paused).
    ///
    /// Security review 2026-09-28 (HIGH): never resets `writeTimestamps`
    /// here. The budget is per PROCESS, not per connection — `admit`'s own
    /// sliding-window prune is the only thing allowed to shrink it, or
    /// `hello → 30 writes → bye → hello → …` would launder the 30/min cap
    /// on every reconnect.
    public mutating func helloReceived(now: Date) -> BridgeVerdict {
        switch state {
        case .idle, .closed:
            state = .listed
            return .proceed
        case .listed:
            // Another hello while listing tools is fine; stay listed
            return .proceed
        default:
            return .reject(code: BridgeCode.busy)
        }
    }

    /// Called when the user approves on the sheet. `until` is the grant's
    /// expiry; since §9-5 retired the "1 hour" choice the session always
    /// passes `nil`, so the expiry branches in `admit` and `resume` are
    /// inert until a wave brings expiring grants back. Kept, not removed:
    /// the state carries `until` and the tests pin the expiry semantics.
    public mutating func approved(until: Date?, now: Date) {
        state = .open(until: until)
    }

    /// Called when the user denies on the sheet. Closes the session.
    public mutating func denied() {
        state = .closed
    }

    /// Called when a tool call arrives. Checks if the session is valid and
    /// if the write budget allows it. Records the timestamp if approved.
    public mutating func admit(tool: String, now: Date) -> BridgeVerdict {
        // Check session state
        switch state {
        case .idle:
            return .reject(code: BridgeCode.noSession)
        case .listed:
            // First call from listed state: need approval before proceeding
            state = .awaitingApproval
            return .needsApproval
        case .awaitingApproval:
            // Sheet is pending; only approved/denied can change state
            return .reject(code: BridgeCode.busy)
        case .closed:
            return .reject(code: BridgeCode.sessionClosed)
        case .paused:
            return .reject(code: BridgeCode.busy)
        case .open(let until):
            // Check expiration
            if let expiry = until, expiry < now {
                state = .closed
                return .reject(code: BridgeCode.sessionClosed)
            }
        }

        // Read tools bypass the budget entirely
        if !Self.writeTools.contains(tool) {
            return .proceed
        }

        // Write tool: check and update budget with sliding window (absolute timestamps)
        let cutoff = now.addingTimeInterval(-Self.window)
        writeTimestamps = writeTimestamps.filter { $0 > cutoff }

        if writeTimestamps.count >= Self.budgetPerMinute {
            return .reject(code: BridgeCode.rateLimited)
        }

        // Record this write
        writeTimestamps.append(now)

        return .proceed
    }

    /// Pause the session (voice turn started). The open session transitions to
    /// paused until resume or stop is called. Preserves the expiration time.
    /// In-flight calls are not interrupted.
    public mutating func pause() {
        if case .open(let until) = state {
            state = .paused(until: until)
        }
    }

    /// Resume from paused. Transitions back to open, or to closed if the
    /// session had an expiration and it passed while paused.
    public mutating func resume(now: Date) {
        if case .paused(let until) = state {
            if let expiry = until, expiry < now {
                state = .closed
            } else {
                state = .open(until: until)
            }
        }
    }

    /// Stop the session. Closes it from any state.
    public mutating func stop() {
        state = .closed
    }

    /// Called when the connection drops without a bye. Resets to idle so a
    /// new connection can attempt hello again.
    public mutating func disconnected() {
        state = .idle
    }

    public var isOpen: Bool {
        if case .open = state { return true }
        return false
    }

    public var isListed: Bool {
        if case .listed = state { return true }
        return false
    }
}
