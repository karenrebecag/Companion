import Foundation

/// Where the user is, as a city and a country. Never coordinates: the type
/// has nowhere to keep them, so nothing downstream can leak what was never
/// stored (16h-3).
public struct UserLocation: Sendable, Equatable {
    /// A city name is a label, not a paragraph: it rides in every prompt.
    public static let maxField = 60

    public let city: String
    public let country: String?

    public init?(city: String, country: String? = nil) {
        let cleanCity = Self.clean(city)
        guard !cleanCity.isEmpty else { return nil }
        self.city = cleanCity
        let cleanCountry = country.map(Self.clean)
        self.country = cleanCountry?.isEmpty == false ? cleanCountry : nil
    }

    /// What Settings holds: "Cuernavaca" or "Cuernavaca, México".
    public init?(typed: String) {
        let parts = typed.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        self.init(city: parts.first.map(String.init) ?? "",
                  country: parts.dropFirst().first.map(String.init))
    }

    public var label: String {
        country.map { "\(city), \($0)" } ?? city
    }

    /// One field, one line, nothing invisible. Capped by Character (a flag or
    /// an accented letter is one) and then by scalars, whole Characters only:
    /// one Character can carry thousands of combining marks.
    private static func clean(_ text: String) -> String {
        let trimmed = TextHygiene.oneLine(text).trimmingCharacters(in: .whitespaces)
        var kept = ""
        var scalars = 0
        for character in trimmed.prefix(maxField) {
            scalars += character.unicodeScalars.count
            if scalars > maxField * 4 { break }
            kept.append(character)
        }
        return kept.trimmingCharacters(in: .whitespaces)
    }
}

/// The system's city, behind a port: CoreLocation lives in Services.
/// `prompting` says whether this call may put up the system's permission
/// dialog; a turn never may, a lookup the user asked for may.
public protocol UserLocating: Sendable {
    func current(prompting: Bool) async -> UserLocation?
}

/// The one answer to "where is the user": what they wrote in Settings wins
/// over what the system says, and the search provider's guess is never asked.
public struct UserLocationSource: Sendable {
    private let manualCity: @Sendable () -> String
    private let system: (any UserLocating)?

    public init(manualCity: @escaping @Sendable () -> String, system: (any UserLocating)?) {
        self.manualCity = manualCity
        self.system = system
    }

    /// What Settings holds, and nothing from the system: for callers whose
    /// "Tu ciudad" switch is off.
    public func typedCity() -> UserLocation? {
        UserLocation(typed: manualCity())
    }

    public func current(prompting: Bool) async -> UserLocation? {
        if let typed = UserLocation(typed: manualCity()) { return typed }
        return await system?.current(prompting: prompting)
    }
}

/// "Near me" without saying where: the words that mean the user's own place.
/// The search tool cannot guess it — on 2026-09-25 "Restaurantes cercanos"
/// came back from Fullerton because the provider filled the gap itself.
public enum NearMe {
    /// As the whole `near` argument: the model put a pronoun where a place goes.
    private static let placePhrases: Set<[String]> = [
        ["aqui"], ["aca"], ["here"], ["cerca"], ["nearby"], ["near", "me"], ["near", "here"],
        ["cerca", "de", "mi"], ["cerca", "de", "aqui"], ["mi", "ubicacion"], ["my", "location"],
        ["current", "location"], ["ubicacion", "actual"],
    ]
    /// In the query, matched by WORD, never by substring: "acerca", "cercado"
    /// and "cercanía" are other words.
    private static let closeForms: Set<String> = ["cerca", "cercano", "cercana", "cercanos", "cercanas"]
    private static let phraseMarkers: [[String]] = [
        ["near", "me"], ["nearby"], ["close", "by"], ["por", "aqui"], ["por", "aca"],
    ]

    /// Whether the request means "where I am". A place the user names after
    /// "cerca de/del/al ..." is an anchor and is searched as said; only the
    /// pronouns ("cerca de mí", "cerca de aquí") and a bare "cerca" are the
    /// user's own place. An explicit `near` is never overwritten.
    public static func isNearby(query: String, near: String?) -> Bool {
        let place = words(near ?? "")
        if !place.isEmpty { return placePhrases.contains(place) }
        let asked = words(query)
        for (index, word) in asked.enumerated() {
            if closeForms.contains(word) {
                let rest = Array(asked.dropFirst(index + 1))
                guard let next = rest.first, ["de", "del", "a", "al"].contains(next) else { return true }
                if next == "de", let pronoun = rest.dropFirst().first, ["mi", "aqui", "aca"].contains(pronoun) {
                    return true
                }
            }
            for marker in phraseMarkers where Array(asked.dropFirst(index).prefix(marker.count)) == marker {
                return true
            }
        }
        return false
    }

    /// The tool's answer when the user's city is unknown: an instruction to
    /// the model, so it asks instead of searching somewhere else.
    public static func needsCity(_ language: AppLanguage) -> String {
        switch language {
        case .en:
            return "Location unknown: the user's city is not available. Ask them which city "
                + "to search in, then call find_places again with near set."
        case .es:
            return "Ubicación desconocida: no tengo la ciudad de la usuaria. Pregúntale en qué "
                + "ciudad buscar y vuelve a llamar find_places con near."
        }
    }

    private static func words(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return folded.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
