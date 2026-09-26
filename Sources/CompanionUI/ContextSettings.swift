import CompanionCore
import Foundation
import Observation

/// Which perception channels travel with each turn (Wave 10a). Stored as
/// the option set's raw value; a missing key means the defaults — app in
/// front and open documents on, clipboard off.
public enum ContextPreference {
    nonisolated private static let key = "companion.contextChannels"
    /// Swappable so a test writes into its own suite, never the user's.
    nonisolated(unsafe) public static var store: UserDefaults = .standard

    nonisolated public static var channels: ContextChannels {
        get {
            guard let raw = store.object(forKey: key) as? Int else { return .default }
            return ContextChannels(rawValue: raw)
        }
        set { store.set(newValue.rawValue, forKey: key) }
    }
}

/// The Context section of Settings: three toggles and the Accessibility
/// row. Turning documents on without the permission fires the system prompt
/// — the one place it fires — and keeps the toggle on: the toggle records
/// what the user wants, the sensor degrades on its own until the grant lands.
@Observable
@MainActor
public final class ContextSettingsModel {
    public var accessibility: (any AccessibilityChecking)?
    public var screenRecording: (any ScreenRecordingChecking)?
    public private(set) var accessibilityGranted = false
    public private(set) var screenRecordingGranted = false

    public init(accessibility: (any AccessibilityChecking)? = nil) {
        self.accessibility = accessibility
        refreshTrust()
    }

    public var screen: Bool {
        get { ContextPreference.channels.contains(.screen) }
        set {
            set(.screen, newValue)
            if newValue, !screenRecordingGranted {
                screenRecording?.request()
                refreshTrust()
            }
        }
    }

    public var focusedApp: Bool {
        get { ContextPreference.channels.contains(.focusedApp) }
        set { set(.focusedApp, newValue) }
    }

    public var documents: Bool {
        get { ContextPreference.channels.contains(.openDocuments) }
        set {
            set(.openDocuments, newValue)
            if newValue, !accessibilityGranted {
                accessibility?.request()
                refreshTrust()
            }
        }
    }

    public var clipboard: Bool {
        get { ContextPreference.channels.contains(.clipboard) }
        set { set(.clipboard, newValue) }
    }

    /// Read again whenever Settings is in front: the grant is flipped in
    /// System Settings, and a re-sign can drop it silently.
    public func refreshTrust() {
        accessibilityGranted = accessibility?.isTrusted() ?? false
        screenRecordingGranted = screenRecording?.isGranted() ?? false
    }

    public var accessibilityRow: PermissionRowModel {
        PermissionRowModel(kind: .accessibility, granted: accessibilityGranted)
    }

    public var screenRecordingRow: PermissionRowModel {
        PermissionRowModel(kind: .screenRecording, granted: screenRecordingGranted)
    }

    private func set(_ channel: ContextChannels, _ on: Bool) {
        var channels = ContextPreference.channels
        if on { channels.insert(channel) } else { channels.remove(channel) }
        ContextPreference.channels = channels
    }
}
