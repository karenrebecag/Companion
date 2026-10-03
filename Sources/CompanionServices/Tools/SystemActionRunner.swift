import AppKit
import CompanionCore
import Foundation

/// The one thing DM1c-4 can end: `NSRunningApplication.terminate()` behind a
/// seam narrow enough for a fake (`bundleIdentifier`, `terminate()`) so a
/// test never has to conjure a real running process.
package protocol AppTerminating: Sendable {
    var bundleIdentifier: String? { get }
    @discardableResult func terminate() -> Bool
}

extension NSRunningApplication: AppTerminating {}

/// DM1c-4's `SystemActing`: the executor for the two irreversible ops
/// `DecisionRoute` already routes to `.confirm` — `empty_trash` and
/// `quit_app`. Nothing else (volume, shortcuts, scroll…) has an executor
/// yet (DM1d); `supports` says so, and `DecisionGate` falls back to today's
/// path for those.
package final class SystemActionRunner: SystemActing, Sendable {
    private let selfBundleID: String
    private let selfPID: pid_t
    private let frontmostOtherPID: @Sendable () -> pid_t?
    private let emptyTrashScript: @Sendable () -> SystemActResult
    private let runningApplication: @Sendable (pid_t) -> (any AppTerminating)?

    package init(
        selfBundleID: String,
        selfPID: pid_t = ProcessInfo.processInfo.processIdentifier,
        frontmostOtherPID: @escaping @Sendable () -> pid_t?,
        emptyTrashScript: @escaping @Sendable () -> SystemActResult = SystemActionRunner.runEmptyTrashScript,
        runningApplication: @escaping @Sendable (pid_t) -> (any AppTerminating)? = {
            NSRunningApplication(processIdentifier: $0)
        }
    ) {
        self.selfBundleID = selfBundleID
        self.selfPID = selfPID
        self.frontmostOtherPID = frontmostOtherPID
        self.emptyTrashScript = emptyTrashScript
        self.runningApplication = runningApplication
    }

    /// Re-checks `DecisionRoute.validClosedSet` on top of the op/shortcut
    /// match: a plan built by hand (a test, N2's own output) cannot name an
    /// id `Candidates` never offered and still get an executor.
    package func supports(_ plan: Plan) -> Bool {
        guard DecisionRoute.validClosedSet(plan) else { return false }
        switch plan.action {
        case .system: return plan.args["op"] == .text("empty_trash")
        case .shortcut: return plan.args["shortcut"] == .text("quit_app")
        default: return false
        }
    }

    package func act(_ plan: Plan) async -> SystemActResult {
        switch plan.action {
        case .system where plan.args["op"] == .text("empty_trash"):
            return emptyTrashScript()
        case .shortcut where plan.args["shortcut"] == .text("quit_app"):
            return quitFrontmostOtherApp() ? .done : .failed
        default:
            return .failed
        }
    }

    /// `frontmostOtherPID` already excludes Companion's own bundle id
    /// (`FrontmostAppSensor.noteActivation`); the pid and bundle checks here
    /// are the second lock on the one call in this file that can end a
    /// process — belt and suspenders, never Companion.
    private func quitFrontmostOtherApp() -> Bool {
        guard let pid = frontmostOtherPID(), pid != selfPID,
              let app = runningApplication(pid), app.bundleIdentifier != selfBundleID
        else { return false }
        return app.terminate()
    }

    /// Automation permission is prompted the first time this runs; a denial
    /// names the switch to flip, and any other AppleScript error is a
    /// failure, never retried (DecisionGate's ledger) nor silently swallowed.
    package static func runEmptyTrashScript() -> SystemActResult {
        guard let script = NSAppleScript(
            source: "tell application \"Finder\" to empty trash")
        else { return .failed }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return emptyTrashResult(error)
    }

    package static func emptyTrashResult(_ error: NSDictionary?) -> SystemActResult {
        guard let error else { return .done }
        let number = (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue
        if number == AppleEventSheets.notPermitted {
            Log.app("system: empty_trash refused by Automation")
            return .permissionRequired(app: "Finder")
        }
        Log.app("system: empty_trash failed code=\(number.map(String.init) ?? "none")")
        return .failed
    }
}
