import CompanionCore
import CoreGraphics
import Foundation

/// Input Monitoring, probed and requested through the event-tap access API.
/// The system prompt appears once per app and signing identity; after a
/// deny the request returns false with no UI, so the Settings row always
/// offers the deep link too.
package struct InputMonitoringPermission: InputMonitoringChecking {
    package init() {}

    package func isGranted() -> Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    package func request() -> Bool {
        CGRequestListenEventAccess()
    }
}
