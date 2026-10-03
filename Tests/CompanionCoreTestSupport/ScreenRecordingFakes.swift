import CompanionCore
import Foundation

/// The grant and the real-capture probe, scripted apart: they disagree on a
/// live Mac (preflight stays true after a revoke), and that gap is what the
/// gate exists for. Counts every call so a test proves nothing prompts.
package final class FakeScreenRecording: ScreenRecordingChecking, @unchecked Sendable {
    private let lock = NSLock()
    private var _granted: Bool
    private var _captures: Bool
    private var _verifies = 0
    private var _requests = 0

    package init(granted: Bool, captures: Bool) {
        _granted = granted
        _captures = captures
    }

    package var granted: Bool {
        get { lock.withLock { _granted } }
        set { lock.withLock { _granted = newValue } }
    }

    package var captures: Bool {
        get { lock.withLock { _captures } }
        set { lock.withLock { _captures = newValue } }
    }

    package var verifies: Int { lock.withLock { _verifies } }
    package var requests: Int { lock.withLock { _requests } }

    package func isGranted() -> Bool { granted }

    package func verify() async -> Bool {
        lock.withLock {
            _verifies += 1
            return _captures
        }
    }

    @discardableResult
    package func request() -> Bool {
        lock.withLock {
            _requests += 1
            return _granted
        }
    }
}
