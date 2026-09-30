import Foundation

/// The languages the app actually speaks. English is the source: every
/// string is written in it first and Spanish follows as a translation, so
/// anything the app cannot speak falls back to English rather than to a
/// half-translated screen.
package enum AppLanguage: String, Sendable, CaseIterable, Codable {
    case en
    case es

    /// The locale the system speech recogniser listens in. Regional on
    /// purpose: with a bare language code SFSpeechRecognizer loses the
    /// on-device model it has for the regional variant.
    package var speechLocaleIdentifier: String {
        switch self {
        case .en: "en-US"
        case .es: "es-MX"
        }
    }

    /// The user's choice wins; otherwise the first system language the app
    /// speaks, in the order the system prefers them. Pure on purpose: the
    /// identifiers come from the composition root, because nothing in Core
    /// reads the environment (see Config).
    package static func resolved(
        preferred: AppLanguage? = nil, system: [String]
    ) -> AppLanguage {
        if let preferred { return preferred }
        for identifier in system {
            let code = identifier.split(separator: "-").first.map(String.init)
                ?? identifier
            if let match = AppLanguage(rawValue: code.lowercased()) {
                return match
            }
        }
        return .en
    }
}
