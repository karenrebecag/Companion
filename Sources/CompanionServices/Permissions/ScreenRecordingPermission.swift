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
            return !content.displays.isEmpty
        } catch {
            Log.app("screen-recording: verify failed (\(error.localizedDescription))")
            return false
        }
    }

    @discardableResult
    package func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }
}
