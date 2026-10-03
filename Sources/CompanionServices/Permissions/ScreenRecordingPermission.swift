import CompanionCore
import CoreGraphics
import Foundation
import ScreenCaptureKit

/// Screen Recording, probed and requested through the capture-access API.
/// The system prompt appears once per identity; after a deny it returns
/// false with no UI, so Settings always offers the deep link too.
package struct ScreenRecordingPermission: ScreenRecordingChecking {
    package init() {}

    package func isGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Listing shareable content fails without a working grant, and costs
    /// no pixels. Guarded by the preflight again: without a grant this call
    /// can raise the system prompt, and only the user's tap may do that.
    package func verify() async -> Bool {
        guard isGranted() else { return false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            let ok = !content.displays.isEmpty
            if ok { Self.failures.reset() }
            return ok
        } catch {
            let line = "screen-recording: verify failed (\(error.localizedDescription))"
            if Self.failures.isNew(line) { Log.app(line) }
            return false
        }
    }

    /// Shared across instances: the welcome polls once a second while the
    /// switch is on and captures fail, and that state can last until relaunch.
    private static let failures = RepeatFilter()

    @discardableResult
    package func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}

/// Lets a line through only when it differs from the last one let through.
final class RepeatFilter: @unchecked Sendable {
    private let lock = NSLock()
    private var last: String?

    func isNew(_ line: String) -> Bool {
        lock.withLock {
            guard line != last else { return false }
            last = line
            return true
        }
    }

    func reset() {
        lock.withLock { last = nil }
    }
}
