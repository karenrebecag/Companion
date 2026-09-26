import Foundation

/// Accessibility, as a port: the sensor asks `isTrusted()` on every read and
/// never calls `request()`; only the Settings row does, on the user's tap.
public protocol AccessibilityChecking: Sendable {
    func isTrusted() -> Bool
    @discardableResult
    func request() -> Bool
}

/// Input Monitoring (Wave 12b): leftover API. FN now uses Accessibility.
public protocol InputMonitoringChecking: Sendable {
    func isGranted() -> Bool
    @discardableResult
    func request() -> Bool
}

/// Screen Recording (Wave 13a): one screenshot per hold, never a stream.
public protocol ScreenRecordingChecking: Sendable {
    func isGranted() -> Bool
    @discardableResult
    func request() -> Bool
}

/// Where the user goes when a permission was refused. The system prompt
/// shows once; these do not run out. Pure URLs, so the chat layer can offer
/// them without seeing Services.
public enum PermissionSettingsLink {
    public static let accessibility = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    public static let microphone = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
    public static let speechRecognition = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")!
    public static let inputMonitoring = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
    public static let screenRecording = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
}
