import Foundation

/// The TCC services Companion actually asks for, spelled the way `tccutil`
/// takes them: the tool prefixes `kTCCService` (read from /usr/bin/tccutil)
/// and each name below is a `kTCCService*` constant present in tccd. Location
/// is absent on purpose: it is not a TCC service, so `tccutil` cannot reset it.
package enum PermissionResetService: String, Sendable, CaseIterable {
    case microphone = "Microphone"
    case speechRecognition = "SpeechRecognition"
    case screenCapture = "ScreenCapture"
    case accessibility = "Accessibility"
    /// Input Monitoring (`CGRequestListenEventAccess`).
    case listenEvent = "ListenEvent"
    /// Contacts (`CNContactStore`); tccutil's own man page uses this name.
    case addressBook = "AddressBook"
    /// Automation: the Apple Events the Sheets and system tools send.
    case appleEvents = "AppleEvents"
}

package enum PermissionResetError: Error, Equatable, Sendable {
    case invalidBundleID
    case invalidBundlePath
    case invalidPID
    /// Only the service name: nothing about the machine or the account.
    case resetFailed(PermissionResetService)
    case relaunchFailed
    /// Anything a port throws that is not one of the above.
    case unexpected
}

/// Port: forget what the user granted and start over. The real one runs
/// tccutil; the Settings row only ever sees this.
package protocol PermissionResetting: Sendable {
    func resetAndRelaunch() async throws
}

/// Pure planning for "reset Companion's permissions and relaunch" (ON-18).
/// It builds fixed argv arrays and runs nothing, so it cannot touch the
/// privacy database by itself.
package enum PermissionReset {
    package static let tccutil = "/usr/bin/tccutil"
    package static let open = "/usr/bin/open"

    /// One argv per service, never `reset All`: the reset must not reach
    /// anything Companion did not ask for.
    package static func plan(bundleID: String) throws -> [[String]] {
        guard isReverseDNS(bundleID) else { throw PermissionResetError.invalidBundleID }
        return PermissionResetService.allCases.map {
            [tccutil, "reset", $0.rawValue, bundleID]
        }
    }

    /// What a reset that failed at `service` already cleared: everything
    /// before it in plan order. The run stops at the first failure, so
    /// nothing after it was touched.
    package static func cleared(before service: PermissionResetService) -> [PermissionResetService] {
        let all = PermissionResetService.allCases
        guard let index = all.firstIndex(of: service) else { return [] }
        return Array(all[..<index])
    }

    /// `open -n` starts a second instance while this one is still alive, so
    /// the pid rides along: the new instance waits for it to exit before it
    /// takes the single-instance resources (see `RelaunchHandoff`). An
    /// absolute `.app` path cannot be read as a flag.
    package static func relaunch(bundlePath: String, afterPID pid: Int32) throws -> [String] {
        guard bundlePath.hasPrefix("/"), bundlePath.hasSuffix(".app"),
              !bundlePath.contains("\0"), !bundlePath.contains("/../")
        else { throw PermissionResetError.invalidBundlePath }
        guard pid > 0 else { throw PermissionResetError.invalidPID }
        return [open, "-n", bundlePath, "--args", RelaunchHandoff.flag, String(pid)]
    }

    /// The word the user types to unlock the destructive button.
    package static func confirmationWord(for language: AppLanguage) -> String {
        switch language {
        case .es: "RESTABLECER"
        case .en: "RESET"
        }
    }

    /// Ignores case and outer whitespace: the friction is typing the word,
    /// not holding shift, and a caps-lock mismatch should not lock anyone out.
    package static func isConfirmed(_ input: String, language: AppLanguage) -> Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            == confirmationWord(for: language)
    }

    private static let maxBundleIDLength = 155

    /// Dot-separated, non-empty segments of ASCII letters, digits and
    /// hyphens, at least two, never starting with a hyphen (it would read as
    /// a flag to tccutil).
    private static func isReverseDNS(_ id: String) -> Bool {
        guard !id.isEmpty, id.utf8.count <= maxBundleIDLength, !id.hasPrefix("-") else {
            return false
        }
        let segments = id.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else { return false }
        return segments.allSatisfy { segment in
            !segment.isEmpty && segment.unicodeScalars.allSatisfy { scalar in
                scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-")
            }
        }
    }
}

/// The new instance's side of the relaunch. Anything can launch the app with
/// this flag, so the worst case is a short bounded delay, never a hang.
package enum RelaunchHandoff {
    package static let flag = "--relaunch-after"
    package static let pollInterval: TimeInterval = 0.05
    package static let maxPolls = 60

    package enum Outcome: Equatable, Sendable { case exited, timedOut }

    /// A plain positive integer that is not ours. Anything else (signs,
    /// junk, overflow, our own pid) is ignored, so a malformed flag costs
    /// nothing. The first flag wins.
    package static func predecessor(in arguments: [String], ownPID: Int32) -> Int32? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        let raw = arguments[index + 1]
        guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }),
              let pid = Int32(raw), pid > 0, pid != ownPID else { return nil }
        return pid
    }

    /// Polls until the pid is gone or `maxPolls` is spent. Probe and sleep
    /// are injected so tests neither wait nor signal anything.
    package static func wait(
        forExitOf pid: Int32,
        isAlive: (Int32) -> Bool,
        sleep: (TimeInterval) -> Void
    ) -> Outcome {
        for _ in 0..<maxPolls {
            if !isAlive(pid) { return .exited }
            sleep(pollInterval)
        }
        return isAlive(pid) ? .timedOut : .exited
    }
}
