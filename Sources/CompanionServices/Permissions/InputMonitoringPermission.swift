import CompanionCore
import CoreGraphics
import Foundation

/// Input Monitoring, probed and requested through the event-tap access API.
/// The system prompt appears once per app and signing identity; after a
/// deny the request returns false with no UI, so the Settings row always
/// offers the deep link too.
public struct InputMonitoringPermission: InputMonitoringChecking {
    public init() {}

    public func isGranted() -> Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    public func request() -> Bool {
        CGRequestListenEventAccess()
    }
}
