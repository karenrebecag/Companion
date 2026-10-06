import Foundation

/// Dictation and speaking stay off the UI language. Nothing picked means
/// the ear is not biased toward one language; speaking follows the first
/// picked dictation language, or the app's interface language when that list
/// is empty (local reference; Incredible language pickers).
package enum SpokenLanguagePreference {
    package static let dictationKey = "companion.spoken.dictation"
    package static let speechKey = "companion.spoken.speech"
    /// Five, so a sixth pick never reaches the ear
    /// (local reference; Incredible language pickers).
    package static let maxDictation = 5
    package static let automatic = "auto"
    package static let fallbackCode = "en"

    package struct Entry: Sendable, Equatable {
        package let code: String
        /// The name a speech instruction can say. The screen uses the catalogs.
        package let englishName: String
        package let nativeName: String
    }

    package static let catalog: [Entry] = [
        Entry(code: "en", englishName: "English", nativeName: ""),
        Entry(code: "es", englishName: "Spanish", nativeName: "Español"),
        Entry(code: "fr", englishName: "French", nativeName: "Français"),
        Entry(code: "de", englishName: "German", nativeName: "Deutsch"),
        Entry(code: "it", englishName: "Italian", nativeName: "Italiano"),
        Entry(code: "pt", englishName: "Portuguese", nativeName: "Português"),
        Entry(code: "nl", englishName: "Dutch", nativeName: "Nederlands"),
        Entry(code: "sv", englishName: "Swedish", nativeName: "Svenska"),
        Entry(code: "no", englishName: "Norwegian", nativeName: "Norsk"),
        Entry(code: "da", englishName: "Danish", nativeName: "Dansk"),
        Entry(code: "fi", englishName: "Finnish", nativeName: "Suomi"),
        Entry(code: "pl", englishName: "Polish", nativeName: "Polski"),
        Entry(code: "ru", englishName: "Russian", nativeName: "Русский"),
        Entry(code: "uk", englishName: "Ukrainian", nativeName: "Українська"),
        Entry(code: "tr", englishName: "Turkish", nativeName: "Türkçe"),
        Entry(code: "ar", englishName: "Arabic", nativeName: "العربية"),
        Entry(code: "he", englishName: "Hebrew", nativeName: "עברית"),
        Entry(code: "ja", englishName: "Japanese", nativeName: "日本語"),
        Entry(code: "ko", englishName: "Korean", nativeName: "한국어"),
        Entry(code: "zh", englishName: "Chinese", nativeName: "中文"),
        Entry(code: "hi", englishName: "Hindi", nativeName: "हिन्दी"),
        Entry(code: "id", englishName: "Indonesian", nativeName: "Bahasa Indonesia"),
        Entry(code: "th", englishName: "Thai", nativeName: "ไทย"),
        Entry(code: "vi", englishName: "Vietnamese", nativeName: "Tiếng Việt"),
        Entry(code: "cs", englishName: "Czech", nativeName: "Čeština"),
        Entry(code: "el", englishName: "Greek", nativeName: "Ελληνικά"),
        Entry(code: "hu", englishName: "Hungarian", nativeName: "Magyar"),
        Entry(code: "ro", englishName: "Romanian", nativeName: "Română"),
        Entry(code: "bg", englishName: "Bulgarian", nativeName: "Български"),
        Entry(code: "is", englishName: "Icelandic", nativeName: "Íslenska"),
    ]

    private static let catalogCodes = Set(catalog.map(\.code))

    /// Missing keys stay missing: a read must not invent a saved choice.
    package static func dictationCodes(in defaults: UserDefaults = .standard) -> [String] {
        guard let raw = defaults.array(forKey: dictationKey) as? [String] else { return [] }
        return normalizeDictation(raw)
    }

    package static func setDictation(_ codes: [String], in defaults: UserDefaults = .standard) {
        defaults.set(normalizeDictation(codes), forKey: dictationKey)
    }

    package static func speechCode(in defaults: UserDefaults = .standard) -> String {
        guard let raw = defaults.string(forKey: speechKey) else { return automatic }
        if raw == automatic || catalogCodes.contains(raw) { return raw }
        return automatic
    }

    package static func setSpeech(_ code: String, in defaults: UserDefaults = .standard) {
        let stored = (code == automatic || catalogCodes.contains(code)) ? code : automatic
        defaults.set(stored, forKey: speechKey)
    }

    package static func normalizeDictation(_ codes: [String]) -> [String] {
        var seen = Set<String>()
        var kept: [String] = []
        for raw in codes {
            let code = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard catalogCodes.contains(code), seen.insert(code).inserted else { continue }
            kept.append(code)
            if kept.count == maxDictation { break }
        }
        return kept
    }

    package static func transcriptionLanguages(in defaults: UserDefaults = .standard) -> [String] {
        dictationCodes(in: defaults)
    }

    package static func resolvedSpeechCode(
        in defaults: UserDefaults = .standard, interface: AppLanguage
    ) -> String {
        resolvedSpeechCode(
            dictation: dictationCodes(in: defaults), speech: speechCode(in: defaults),
            interface: interface)
    }

    /// A code outside the catalog is automatic. Automatic is the first
    /// dictation language, then the interface language: Incredible falls back
    /// to its own UI language, and a Spanish app that fell back to English
    /// would answer a Spanish user in English until they found this setting.
    /// Never an empty string: a mouth that sends one goes silent or speaks
    /// the wrong language.
    package static func resolvedSpeechCode(
        dictation: [String], speech: String, interface: AppLanguage
    ) -> String {
        let picked = normalizeDictation(dictation)
        if speech != automatic, catalogCodes.contains(speech) { return speech }
        return picked.first ?? interface.rawValue
    }

    /// The one language the on-device hold ear can listen in: the first
    /// dictation language, or the interface's own while nothing is picked.
    /// Read per start, never captured at launch.
    package static func onDeviceLocale(
        interface: AppLanguage, defaults: UserDefaults = .standard
    ) -> String {
        guard let first = dictationCodes(in: defaults).first else {
            return interface.speechLocaleIdentifier
        }
        return regionalIdentifier(for: first)
    }

    /// Read per call, never captured: the mouths are built once at launch
    /// and a change in Settings must reach the next sentence.
    package static func speechCodeProvider(
        interface: AppLanguage, defaults: UserDefaults = .standard
    ) -> @Sendable () -> String {
        // UserDefaults is documented thread-safe but not marked Sendable.
        nonisolated(unsafe) let store = defaults
        return { resolvedSpeechCode(in: store, interface: interface) }
    }

    /// The name a model-facing instruction says, only when the spoken
    /// language is a catalog language other than the interface's own. Nil
    /// keeps every prompt byte-for-byte what it was for the app language.
    package static func name(
        speaking code: String?, differingFrom interface: AppLanguage
    ) -> String? {
        guard let code, code != interface.rawValue else { return nil }
        return catalog.first { $0.code == code }?.englishName
    }

    package static func wireLanguageCode(_ code: String) -> String {
        catalogCodes.contains(code) ? code : fallbackCode
    }

    /// A bare code drops the regional voice. Unknown codes use en-US
    /// rather than a locale nothing installed can speak.
    package static func regionalIdentifier(for code: String) -> String {
        switch code {
        case "en": "en-US"
        case "es": "es-MX"
        case "fr": "fr-FR"
        case "de": "de-DE"
        case "it": "it-IT"
        case "pt": "pt-BR"
        case "nl": "nl-NL"
        case "sv": "sv-SE"
        case "no": "nb-NO"
        case "da": "da-DK"
        case "fi": "fi-FI"
        case "pl": "pl-PL"
        case "ru": "ru-RU"
        case "uk": "uk-UA"
        case "tr": "tr-TR"
        case "ar": "ar-SA"
        case "he": "he-IL"
        case "ja": "ja-JP"
        case "ko": "ko-KR"
        case "zh": "zh-CN"
        case "hi": "hi-IN"
        case "id": "id-ID"
        case "th": "th-TH"
        case "vi": "vi-VN"
        case "cs": "cs-CZ"
        case "el": "el-GR"
        case "hu": "hu-HU"
        case "ro": "ro-RO"
        case "bg": "bg-BG"
        case "is": "is-IS"
        default: "en-US"
        }
    }

    package static func instructions(for code: String) -> String {
        switch code {
        case "es":
            return "Habla en español de México, conversacional, ágil y natural, sin pausas teatrales."
        case "en":
            return "Speak in American English, conversational, brisk and natural, with no theatrical pauses."
        default:
            guard let name = catalog.first(where: { $0.code == code })?.englishName else {
                return instructions(for: fallbackCode)
            }
            return "Speak in \(name), conversational, brisk and natural, with no theatrical pauses."
        }
    }
}
