import CompanionCore

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
        case .noProviders: Localized.string("voice.fail.noProviders")
        case .sessionDropped: Localized.string("voice.fail.sessionDropped")
        case .networkUnavailable:
            Localized.string("voice.fail.networkUnavailable")
        }
    }

    public static var previewFailed: String {
        Localized.string("voice.preview.failed")
    }
}
