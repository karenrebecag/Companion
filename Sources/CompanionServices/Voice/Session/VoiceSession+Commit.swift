import CompanionCore
import Foundation

/// Dictation into the field the hold probed at press (Wave 12e): what the
/// words become when the field takes them, and the fallback to Companion
/// when it does not. Split out of VoiceSession's turn commit.
extension VoiceSession {
    /// True when the words landed in the field. On any failure they go to
    /// Companion instead: nothing the user said is lost, and never pasted
    /// anywhere but the field probed at press.
    func dictate(_ text: String, into field: FocusedField) async -> Bool {
        guard let injector else { return false }
        switch await injector.inject(text, into: field) {
        case .injected(let count, let route):
            commitTimeline()
            Log.app("dictation: pasted \(count) chars into \(field.app) via \(route.rawValue)")
            // The words ride the event for the island's result card only;
            // the log above stays at the count (dictation-never-logged).
            eventBox.yield(.dictated(app: field.app, text: DictatedText(text)))
            return true
        case .failed(let reason):
            Log.app("dictation: \(reason) in \(field.app); the words go to Companion")
            if reason == .needsAccessibility {
                eventBox.yield(.dictationFailed(.needsAccessibility))
            }
            return false
        }
    }
}
