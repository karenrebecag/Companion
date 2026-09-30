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

/// Pure policy for session authorization and rate limiting. The write and read
/// budgets each count towards their own sliding window.
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
        "open_file",
        "browser_click",
        "browser_type",
        "browser_navigate",
        "browser_open",
        "browser_take",
        "browser_release"
    ]

    /// Every allowlisted tool that draws from the read budget. Explicit on
    /// purpose: a bucket that is "whatever is not a write" lets a new tool
    /// slip into the looser budget unnoticed; `unbucketed` and its test make
    /// adding a tool to `BridgeScope.bridgeTools` force a choice here.
    ///
    /// `focus_window` is deliberately a read: it only raises a window
    /// Companion was already allowed to see, changes no content, and an agent
    /// calls it between reads. It stays out of `writeTools`, so it is neither
    /// counted against the action budget nor reported as an action.
    public static let readTools: Set<String> = [
        "list_apps",
        "read_skill",
        "find_places",
        "focus_window",
        "read_focused",
        "look",
        "see",
        "browser_tabs",
        "browser_read"
    ]

    /// Allowlisted tools that sit in neither bucket.
    public static func unbucketed(_ allowed: Set<String>) -> Set<String> {
        allowed.subtracting(writeTools).subtracting(readTools)
    }

    public static let budgetPerMinute = 30
    /// Wave 20c D6 (M8b): reads (`look`, `see`, `read_focused`...) draw from
    /// their own allowance. They used to be free, so a peer could hammer the
    /// screen capture and the vision model; and they must not share the
    /// action allowance, or either flood would starve the other. Looser than
    /// the actions: an agent re-reads the screen after every step.
    public static let readBudgetPerMinute = 60
    public static let window: TimeInterval = 60

    /// Wave 20c D5 (M2a): a connection with no traffic for this long loses
    /// the hands. Long enough for a slow agent step, short enough that a
    /// forgotten client does not hold them for the rest of the day.
    public static let idleTimeout: TimeInterval = 10 * 60
    /// How often the session looks at the clock; the timeout is the ceiling,
    /// this is only the resolution.
    public static let idleCheckInterval: TimeInterval = 15

    /// Wave 20c D5 (M2b): this many denied approvals inside `denialWindow`
    /// and the caller is cooled down until the oldest one ages out, so
    /// nobody can spam requests hoping for a mistaken yes.
    public static let maxDenials = 3
    public static let denialWindow: TimeInterval = 10 * 60

    /// Wave 20c D5 (review F1): approval SHEETS shown per `sheetWindow`,
    /// whatever their outcome. Withdrawn and timed-out sheets are not denials
    /// (they must not lock the hands), so without this a token-holding peer
    /// could raise fresh sheets forever by reconnecting. A real session is one
    /// session sheet plus a per-call sheet for each destructive click or
    /// `type_text`; 20 in ten minutes is far past what a person answers, and
    /// still stops a loop.
    public static let maxSheetsPerWindow = 20
    public static let sheetWindow: TimeInterval = denialWindow

    public private(set) var state: BridgeState

    /// Absolute timestamps of write operations. Pruned to keep only writes
    /// within the current window on each write-tool admit.
    private var writeTimestamps: [Date]

    /// Same, for reads, kept apart from `writeTimestamps` on purpose.
    private var readTimestamps: [Date]

    /// Denied approvals, per PROCESS like the write budget: `disconnected()`
    /// never clears it, or reconnecting would reset the count.
    private var denialTimestamps: [Date]

    public init() {
        self.state = .idle
        self.writeTimestamps = []
        self.readTimestamps = []
        self.denialTimestamps = []
    }

    public mutating func recordDenial(now: Date) {
        denialTimestamps = denialTimestamps.filter { $0 > now.addingTimeInterval(-Self.denialWindow) }
        denialTimestamps.append(now)
    }

    public func isCoolingDown(now: Date) -> Bool {
        let cutoff = now.addingTimeInterval(-Self.denialWindow)
        return denialTimestamps.filter { $0 > cutoff }.count >= Self.maxDenials
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
        if isCoolingDown(now: now) { return .reject(code: BridgeCode.coolingDown) }
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
        if isCoolingDown(now: now) { return .reject(code: BridgeCode.coolingDown) }
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

        let cutoff = now.addingTimeInterval(-Self.window)
        // Only a named read gets the looser budget; anything else is held to
        // the action one, so a tool nobody bucketed fails safe.
        if Self.readTools.contains(tool) {
            return Self.spend(&readTimestamps, limit: Self.readBudgetPerMinute, cutoff: cutoff, now: now)
        }
        return Self.spend(&writeTimestamps, limit: Self.budgetPerMinute, cutoff: cutoff, now: now)
    }

    /// One sliding window over absolute timestamps: prunes, then records
    /// `now` if there is room.
    private static func spend(
        _ timestamps: inout [Date], limit: Int, cutoff: Date, now: Date
    ) -> BridgeVerdict {
        timestamps = timestamps.filter { $0 > cutoff }
        guard timestamps.count < limit else { return .reject(code: BridgeCode.rateLimited) }
        timestamps.append(now)
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

/// Sliding window over the sheets a bridge has shown. Separate from the
/// denial cool-down on purpose: that one counts refusals only, this one
/// counts every sheet whatever became of it. Per process, never reset.
public struct BridgeSheetLimit: Sendable, Equatable {
    private var shown: [Date] = []

    public init() {}

    /// True and records the sheet when one more may be shown at `now`.
    public mutating func admit(now: Date) -> Bool {
        let cutoff = now.addingTimeInterval(-BridgePolicy.sheetWindow)
        shown = shown.filter { $0 > cutoff }
        guard shown.count < BridgePolicy.maxSheetsPerWindow else { return false }
        shown.append(now)
        return true
    }
}
