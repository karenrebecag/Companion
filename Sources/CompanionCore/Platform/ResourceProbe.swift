import Foundation

/// The packaging probe (21c, D5/D9): with `COMPANION_RESOURCE_PROBE=1` the app
/// forces every resource load before AppKit starts, prints one line per check
/// and exits. A launch smoke that only waits for the process to stay alive
/// misses lazy loads (diagrams, mascot) that never run in its window, and on
/// the build Mac the generated accessor quietly falls back to the checkout's
/// `.build`; scripts/package-smoke.sh runs this with the checkout unreadable.
package enum ResourceProbe {
    package static let environmentKey = "COMPANION_RESOURCE_PROBE"
    /// The smoke greps for this exact line; it is printed only when every check passed.
    package static let marker = "COMPANION_RESOURCE_PROBE_OK"
    /// Below 128, so the smoke can tell "the probe reported failures" from
    /// "the process died by a signal" (a trap is SIGTRAP/SIGILL).
    package static let failureExitCode: Int32 = 3

    package struct Check: Sendable, Equatable {
        package let name: String
        /// What was observed: a path, a count, a value. Never a secret.
        package let detail: String
        package let passed: Bool

        package init(name: String, detail: String, passed: Bool) {
            self.name = name
            self.detail = detail
            self.passed = passed
        }
    }

    package struct Report: Sendable, Equatable {
        package let lines: [String]
        package let exitCode: Int32
    }

    package static func isRequested(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment[environmentKey] == "1"
    }

    /// Zero checks is a failure: a probe that checked nothing proves nothing.
    package static func report(_ checks: [Check]) -> Report {
        let lines = checks.map { "probe \($0.passed ? "ok" : "FAIL") \($0.name)=\($0.detail)" }
        let failed = checks.filter { !$0.passed }.count
        if checks.isEmpty || failed > 0 {
            return Report(lines: lines + ["probe failed: \(failed) of \(checks.count) checks"],
                          exitCode: failureExitCode)
        }
        return Report(lines: lines + [marker], exitCode: 0)
    }

    package static func run(_ checks: [Check], write: (String) -> Void = writeStandardOutput) -> Int32 {
        let report = report(checks)
        report.lines.forEach(write)
        return report.exitCode
    }

    package static func writeStandardOutput(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    /// D9: the extension is not a SwiftPM resource (bundle.sh copies it and
    /// Settings reads it from `Bundle.main.resourceURL`), but the product needs
    /// it, so its absence fails packaging. The manifest is what Chrome loads.
    package static func browserExtension(
        resourceURL: URL?,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> Check {
        guard let folder = resourceURL?.appendingPathComponent("BrowserExtension", isDirectory: true) else {
            return Check(name: "browserExtension", detail: "no resourceURL", passed: false)
        }
        let present = fileExists(folder.appendingPathComponent("manifest.json"))
        return Check(name: "browserExtension", detail: present ? folder.path : "missing \(folder.path)",
                     passed: present)
    }
}
