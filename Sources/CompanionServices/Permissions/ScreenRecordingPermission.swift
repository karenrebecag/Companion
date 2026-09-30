import CompanionCore
import CoreGraphics
import Foundation

/// Screen Recording, probed and requested through the capture-access API.
/// The system prompt appears once per identity; after a deny it returns
/// false with no UI, so Settings always offers the deep link too.
public struct ScreenRecordingPermission: ScreenRecordingChecking {
    public init() {}

    public func isGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    public func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}
