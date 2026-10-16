import CompanionUIPro
import Foundation

/// The words CompanionUIPro speaks by default are English; the chat speaks
/// the user's language, so every string the data components show comes from
/// the catalog.
enum PresentStrings {
    /// The plural and parameter closures run off the main actor, so the format
    /// strings are read first and the closures only fill them in.
    @MainActor static var datos: DatosStrings {
        let sortBy = Localized.string("present.sort.by")
        let removeFilter = Localized.string("present.filter.remove")
        let showAll = Localized.string("present.code.showAll")
        return DatosStrings(
            sortBy: { String(format: sortBy, $0) },
            ascending: Localized.string("present.sort.ascending"),
            descending: Localized.string("present.sort.descending"),
            removeFilter: { String(format: removeFilter, $0) },
            addFilter: Localized.string("present.filter.add"),
            clearAll: Localized.string("present.filter.clear"),
            copied: Localized.string("present.copied"),
            copyFailed: Localized.string("present.copyFailed"),
            showAll: { String(format: showAll, $0) },
            showLess: Localized.string("present.code.showLess"),
            reviewChanges: Localized.string("present.code.review"),
            hideChanges: Localized.string("present.code.hide"),
            noChanges: Localized.string("present.code.none"),
            expanded: Localized.string("present.expanded"),
            collapsed: Localized.string("present.collapsed"),
            copyCode: Localized.string("present.code.copy"),
            addedLine: Localized.string("present.diff.added"),
            removedLine: Localized.string("present.diff.removed"),
            today: Localized.string("present.day.today"),
            yesterday: Localized.string("present.day.yesterday"))
    }

    static func unit(_ unit: CountdownUnit) -> String {
        switch unit {
        case .days: Localized.string("present.unit.days")
        case .hours: Localized.string("present.unit.hours")
        case .minutes: Localized.string("present.unit.minutes")
        case .seconds: Localized.string("present.unit.seconds")
        }
    }

    /// A chart needs a name for VoiceOver even when the model gave no title.
    static func label(_ title: String?, fallback key: String) -> String {
        if let title, !title.isEmpty { return title }
        return Localized.string(key)
    }
}
