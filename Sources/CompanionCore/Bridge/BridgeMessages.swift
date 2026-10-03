/// What the bridge tells an agent when it refuses: one line that
/// names the next action, because the agent cannot see the Mac and a bare
/// "try again later" leaves it guessing or retrying in a loop.
package enum BridgeMessages {
    package static func rateLimited(waitSeconds: Int) -> String {
        "Too many calls this minute (\(BridgePolicy.budgetPerMinute) actions, "
            + "\(BridgePolicy.readBudgetPerMinute) reads). Wait \(duration(waitSeconds)), then retry."
    }

    package static func coolingDown(waitSeconds: Int) -> String {
        "The user turned down too many requests. Wait \(duration(waitSeconds)) before asking again; "
            + "a sooner request is refused without asking."
    }

    /// The sheets-per-window limit, which counts every sheet shown, answered or
    /// not: blaming the user's denials would be false.
    package static func sheetLimit(waitSeconds: Int) -> String {
        "Too many approval requests in the last ten minutes. Wait \(duration(waitSeconds)) before asking again; "
            + "a sooner request is refused without asking."
    }

    package static let paused =
        "The user is talking to Companion right now. Wait a few seconds, then retry."

    package static let sheetOpen =
        "An approval sheet is open on the Mac. Wait for the user to answer it, then retry."

    package static let anotherAgent =
        "Another agent is using Companion's hands. Wait for it to finish, then send hello again."

    package static let needsAccessibility =
        "Companion does not have Accessibility permission. Ask the user to turn it on in "
            + "System Settings > Privacy & Security > Accessibility, then retry."

    /// Seconds under a minute, whole minutes (rounded up) past it; never 0,
    /// so the agent is not told to retry at once.
    static func duration(_ seconds: Int) -> String {
        let seconds = max(1, seconds)
        return seconds < 60 ? "\(seconds) s" : "\((seconds + 59) / 60) min"
    }
}
