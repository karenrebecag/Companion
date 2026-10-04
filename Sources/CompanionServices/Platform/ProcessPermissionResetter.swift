import AppKit
import Darwin
import CompanionCore
import Foundation

/// Runs one fixed argv and reports its exit status. A seam so tests never
/// start a real process.
package protocol CommandRunning: Sendable {
    func run(_ argv: [String]) async throws -> Int32
}

/// Quitting the current app, behind a seam so tests never quit anything.
package protocol SelfTerminating: Sendable {
    func terminate() async
}

/// No shell: an absolute executable and an argument array, so nothing the
/// arguments contain is ever interpreted.
package struct ProcessCommandRunner: CommandRunning {
    package init() {}

    package func run(_ argv: [String]) async throws -> Int32 {
        guard let executable = argv.first else { return -1 }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Array(argv.dropFirst())
        // Their output is theirs: nothing of it reaches our log.
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}

package struct SelfTerminator: SelfTerminating {
    package init() {}

    package func terminate() async {
        await MainActor.run { NSApplication.shared.terminate(nil) }
    }
}

/// ON-18. Resets each service on its own, in order, and stops at the first
/// failure: a half reset that relaunched would hide what is still granted.
/// Both inputs are validated before anything runs, so a build outside an
/// `.app` bundle never wipes grants it cannot relaunch from. The bundle id
/// and path come from `Bundle.main` only (see the App composition root),
/// never from user input.
package struct ProcessPermissionResetter: PermissionResetting {
    private let bundleID: String
    private let bundlePath: String
    private let pid: Int32
    private let runner: any CommandRunning
    private let terminator: any SelfTerminating

    package init(
        bundleID: String, bundlePath: String,
        pid: Int32 = ProcessInfo.processInfo.processIdentifier,
        runner: any CommandRunning = ProcessCommandRunner(),
        terminator: any SelfTerminating = SelfTerminator()
    ) {
        self.bundleID = bundleID
        self.bundlePath = bundlePath
        self.pid = pid
        self.runner = runner
        self.terminator = terminator
    }

    package func resetAndRelaunch() async throws {
        let resets = try PermissionReset.plan(bundleID: bundleID)
        let relaunch = try PermissionReset.relaunch(bundlePath: bundlePath, afterPID: pid)
        for (service, argv) in zip(PermissionResetService.allCases, resets) {
            try await reset(service, argv)
        }
        try await open(relaunch)
        // WHY no fallback if this does not quit: nothing in the app can
        // cancel termination (no applicationShouldTerminate, no
        // terminateLater, no sudden-termination opt-out), so NSApp.terminate
        // always ends this process and the successor's bounded wait covers
        // the gap.
        await terminator.terminate()
    }

    private func reset(_ service: PermissionResetService, _ argv: [String]) async throws {
        do {
            let status = try await runner.run(argv)
            guard status == 0 else {
                Log.app("permissions: reset of \(service.rawValue) exited \(status)")
                throw PermissionResetError.resetFailed(service)
            }
        } catch let error as PermissionResetError {
            throw error
        } catch {
            Log.app("permissions: reset of \(service.rawValue) did not run")
            throw PermissionResetError.resetFailed(service)
        }
    }

    private func open(_ argv: [String]) async throws {
        do {
            let status = try await runner.run(argv)
            guard status == 0 else {
                Log.app("permissions: relaunch exited \(status)")
                throw PermissionResetError.relaunchFailed
            }
        } catch let error as PermissionResetError {
            throw error
        } catch {
            Log.app("permissions: relaunch did not run")
            throw PermissionResetError.relaunchFailed
        }
    }
}

/// The new instance's startup side of the relaunch (see `RelaunchHandoff`).
/// A relaunch started from Settings leaves the old instance alive for a
/// moment; this holds the new one back until it is gone, so the bridge
/// socket and the hold-key tap are free when this instance asks for them.
///
/// It blocks the main thread on purpose: it runs before any service exists
/// and there is nothing to paint yet, and the wait is capped at about 3 s
/// (`maxPolls * pollInterval`). Moving it off-main would only let the
/// services start while the predecessor still holds their resources.
package enum RelaunchStartup {
    package static func awaitPredecessor(
        arguments: [String] = CommandLine.arguments,
        ownPID: Int32 = ProcessInfo.processInfo.processIdentifier,
        isAlive: (Int32) -> Bool = RelaunchStartup.processIsAlive,
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        guard let pid = RelaunchHandoff.predecessor(in: arguments, ownPID: ownPID) else { return }
        let outcome = RelaunchHandoff.wait(forExitOf: pid, isAlive: isAlive, sleep: sleep)
        if outcome == .timedOut {
            Log.app("relaunch: previous instance still running after the wait; continuing")
        }
    }

    /// Signal 0 only checks. ESRCH means the pid is gone; EPERM means it
    /// exists but is not ours to signal, which is still alive.
    package static func processIsAlive(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno != ESRCH
    }
}
