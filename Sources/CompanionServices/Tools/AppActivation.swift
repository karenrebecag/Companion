import AppKit
import ApplicationServices

/// The activation path for an app that is already running and did not come
/// forward after LaunchServices was asked. Companion is an accessory app, so
/// on macOS 14+ `NSRunningApplication.activate` is only a request the system
/// may decline; setting AXFrontmost and raising the window are the Accessibility
/// route the hands already hold trust for.
enum AppActivation {
    private static let messagingTimeout: Float = 1

    /// True when some route accepted the request. Whether the app is in
    /// front a moment later is for the caller that waits on it to check.
    static func bringToFront(_ app: NSRunningApplication) -> Bool {
        let requested = app.activate(options: [.activateAllWindows])
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        let frontmost = AXUIElementSetAttributeValue(
            element, kAXFrontmostAttribute as CFString, kCFBooleanTrue) == .success
        var windows: CFTypeRef?
        var raised = false
        if AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &windows) == .success,
           let first = (windows as? [AXUIElement])?.first {
            raised = AXUIElementPerformAction(first, kAXRaiseAction as CFString) == .success
        }
        return app.isActive || frontmost || raised || requested
    }
}
