import Foundation

/// Accessibility, as a port: the sensor asks `isTrusted()` on every read and
/// never calls `request()`; only the Settings row does, on the user's tap.
package protocol AccessibilityChecking: Sendable {
    func isTrusted() -> Bool
    @discardableResult
    func request() -> Bool
}

/// Input Monitoring (Wave 12b): leftover API. FN now uses Accessibility.
package protocol InputMonitoringChecking: Sendable {
    func isGranted() -> Bool
    @discardableResult
    func request() -> Bool
}

/// Screen Recording (Wave 13a): one screenshot per hold, never a stream.
package protocol ScreenRecordingChecking: Sendable {
    func isGranted() -> Bool
    /// A real capture probe. The preflight can stay true after a revoke, so
    /// only this proves the screen is readable. Never raises a prompt.
    func verify() async -> Bool
    @discardableResult
    func request() -> Bool
}

/// Where the user goes when a permission was refused. The system prompt
/// shows once; these do not run out. Pure URLs, so the chat layer can offer
/// them without seeing Services.
package enum PermissionSettingsLink {
    package static let accessibility = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    package static let microphone = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
    package static let speechRecognition = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!
    package static let inputMonitoring = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
    package static let screenRecording = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
}
