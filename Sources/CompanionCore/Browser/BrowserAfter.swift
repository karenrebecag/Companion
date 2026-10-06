import Foundation

/// What an action did to the page, as the extension saw it. Flags and a count only: no page text crosses
/// this type, so the sentence the model reads is always the host's own wording.
package struct BrowserAfter: Sendable, Equatable {
    package enum Opened: String, Sendable { case dialog, menu, listbox }

    package let navigated: Bool
    package let urlChanged: Bool
    package let opened: Opened?
    package let changed: Bool
    package let fieldChars: Int?

    package init(navigated: Bool, urlChanged: Bool, opened: Opened?, changed: Bool, fieldChars: Int?) {
        self.navigated = navigated
        self.urlChanged = urlChanged
        self.opened = opened
        self.changed = changed
        self.fieldChars = fieldChars
    }

    /// A field longer than this is a malformed answer, not a length worth reporting.
    private static let maxFieldChars = 10_000_000

    /// Anything that is not the expected shape is dropped, never trusted.
    init?(decoding raw: Any?) {
        guard let object = raw as? [String: Any] else { return nil }
        let count = (object["fieldChars"] as? NSNumber).flatMap { number -> Int? in
            guard CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue == Double(number.intValue),
                  (0...Self.maxFieldChars).contains(number.intValue) else { return nil }
            return number.intValue
        }
        self.init(
            navigated: object["navigated"] as? Bool ?? false, urlChanged: object["urlChanged"] as? Bool ?? false,
            opened: (object["opened"] as? String).flatMap(Opened.init(rawValue:)),
            changed: object["changed"] as? Bool ?? false, fieldChars: count)
    }
}

extension BrowserCopy {
    /// One short sentence the host writes itself from the flags, in the user's language.
    package static func afterNote(_ after: BrowserAfter, _ language: AppLanguage) -> String {
        var parts: [String] = []
        if after.navigated {
            parts.append(language == .en ? "the page navigated" : "la página navegó")
        } else if let opened = after.opened {
            parts.append(openedNote(opened, language))
        } else if after.urlChanged {
            parts.append(language == .en ? "the address changed" : "la dirección cambió")
        }
        if let chars = after.fieldChars {
            parts.append(language == .en ? "the field now holds \(chars) characters" : "el campo ahora tiene \(chars) caracteres")
        }
        if parts.isEmpty {
            parts.append(after.changed
                ? (language == .en ? "the page changed" : "la página cambió")
                : (language == .en ? "nothing on the page changed" : "nada en la página cambió"))
        }
        let joined = parts.joined(separator: "; ")
        return language == .en ? "After the action: \(joined)." : "Después de la acción: \(joined)."
    }

    private static func openedNote(_ opened: BrowserAfter.Opened, _ language: AppLanguage) -> String {
        switch (opened, language) {
        case (.dialog, .en): return "a dialog opened"
        case (.dialog, .es): return "se abrió un diálogo"
        case (.menu, .en): return "a menu opened"
        case (.menu, .es): return "se abrió un menú"
        case (.listbox, .en): return "a list of options opened"
        case (.listbox, .es): return "se abrió una lista de opciones"
        }
    }
}
