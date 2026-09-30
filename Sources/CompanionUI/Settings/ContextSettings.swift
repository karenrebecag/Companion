import CompanionCore
import Foundation
import Observation

/// Which perception channels travel with each turn (Wave 10a). Stored as
/// the option set's raw value; a missing key means the defaults — app in
/// front and open documents on, clipboard off.
package enum ContextPreference {
    nonisolated private static let key = "companion.contextChannels"
    nonisolated private static let locationKnownKey = "companion.contextChannels.locationKnown"
    /// Swappable so a test writes into its own suite, never the user's.
    nonisolated(unsafe) package static var store: UserDefaults = .standard

    nonisolated package static var channels: ContextChannels {
        get { read(from: store) }
        set { write(newValue, to: store) }
    }

    /// The "Tu ciudad" switch as the composition root reads it.
    nonisolated package static var locationChannelOn: Bool { channels.contains(.location) }

    nonisolated static func read(from store: UserDefaults) -> ContextChannels {
        guard let raw = store.object(forKey: key) as? Int else { return .default }
        var channels = ContextChannels(rawValue: raw)
        // Saved before the location channel existed: it starts on, like every
        // channel, unless she had turned every channel off (switching a sense
        // on behind that choice would be the opposite of it); from the first
        // save of her own, the switch wins.
        if !store.bool(forKey: locationKnownKey), !channels.isDisjoint(with: .all) {
            channels.insert(.location)
        }
        return channels
    }

    nonisolated static func write(_ channels: ContextChannels, to store: UserDefaults) {
        store.set(channels.rawValue, forKey: key)
        store.set(true, forKey: locationKnownKey)
    }
}

/// The Context section of Settings: three toggles and the Accessibility
/// row. Turning documents on without the permission fires the system prompt
/// — the one place it fires — and keeps the toggle on: the toggle records
/// what the user wants, the sensor degrades on its own until the grant lands.
@Observable
@MainActor
package final class ContextSettingsModel {
    package var accessibility: (any AccessibilityChecking)?
    package var screenRecording: (any ScreenRecordingChecking)?
    package private(set) var accessibilityGranted = false
    package private(set) var screenRecordingGranted = false

    package init(accessibility: (any AccessibilityChecking)? = nil) {
        self.accessibility = accessibility
        refreshTrust()
    }

    package var screen: Bool {
        get { ContextPreference.channels.contains(.screen) }
        set {
            set(.screen, newValue)
            if newValue, !screenRecordingGranted {
                screenRecording?.request()
                refreshTrust()
            }
        }
    }

    package var focusedApp: Bool {
        get { ContextPreference.channels.contains(.focusedApp) }
        set { set(.focusedApp, newValue) }
    }

    package var documents: Bool {
        get { ContextPreference.channels.contains(.openDocuments) }
        set {
            set(.openDocuments, newValue)
            if newValue, !accessibilityGranted {
                accessibility?.request()
                refreshTrust()
            }
        }
    }

    package var location: Bool {
        get { ContextPreference.channels.contains(.location) }
        set { set(.location, newValue) }
    }

    package var clipboard: Bool {
        get { ContextPreference.channels.contains(.clipboard) }
        set { set(.clipboard, newValue) }
    }

    /// Read again whenever Settings is in front: the grant is flipped in
    /// System Settings, and a re-sign can drop it silently.
    package func refreshTrust() {
        accessibilityGranted = accessibility?.isTrusted() ?? false
        screenRecordingGranted = screenRecording?.isGranted() ?? false
    }

    package var accessibilityRow: PermissionRowModel {
        PermissionRowModel(kind: .accessibility, granted: accessibilityGranted)
    }

    package var screenRecordingRow: PermissionRowModel {
        PermissionRowModel(kind: .screenRecording, granted: screenRecordingGranted)
    }

    private func set(_ channel: ContextChannels, _ on: Bool) {
        var channels = ContextPreference.channels
        if on { channels.insert(channel) } else { channels.remove(channel) }
        ContextPreference.channels = channels
    }
}
