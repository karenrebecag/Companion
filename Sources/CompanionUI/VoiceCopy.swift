import CompanionCore
import Foundation

public enum VoiceCopy {
    public static var fallbackClassic: String {
        Localized.string("voice.fallback.classic")
    }

    public static var functionRefusal: String {
        Localized.string("voice.function.refusal")
    }

    public static func failure(_ reason: TurnFailure) -> String {
        switch reason {
        case .micDenied: Localized.string("voice.fail.micDenied")
        case .micUnavailable: Localized.string("voice.fail.micUnavailable")
        case .micSilent: Localized.string("voice.fail.micSilent")
        case .notHeard: Localized.string("voice.fail.notHeard")
        case .speechEngine: Localized.string("voice.fail.speechEngine")
        case .speechDenied: Localized.string("voice.fail.speechDenied")
        case .accessibilityDenied: Localized.string("voice.fail.accessibilityDenied")
        case .noProviders: Localized.string("voice.fail.noProviders")
        case .quotaExceeded: Localized.string("voice.fail.quotaExceeded")
        case .sessionDropped: Localized.string("voice.fail.sessionDropped")
        case .networkUnavailable:
            Localized.string("voice.fail.networkUnavailable")
        }
    }

    /// A refused permission gets a way out, not only a sentence (Wave 10a
    /// §3.6): the failures that ARE permissions map to their Settings pane.
    public static func settingsLink(for reason: TurnFailure?) -> URL? {
        switch reason {
        case .micDenied: PermissionSettingsLink.microphone
        case .speechDenied: PermissionSettingsLink.speechRecognition
        case .accessibilityDenied: PermissionSettingsLink.accessibility
        default: nil
        }
    }

    /// The session's reason (Wave 12a): only a failure that IS a permission
    /// gets the link; a stop or a steer has nothing to open.
    public static func settingsLink(after reason: InterruptReason?) -> URL? {
        guard case .failure(let failure) = reason else { return nil }
        return settingsLink(for: failure)
    }

    public static var previewFailed: String {
        Localized.string("voice.preview.failed")
    }
}
