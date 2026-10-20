import Foundation

/// What an action visibly did, as the extension measured it around the action (Incredible's
/// postcondition). Every field is a word from a closed set or a count: nothing the page said travels here.
package struct BrowserEffect: Sendable, Equatable {
    package enum Typed: Sendable, Equatable {
        /// The field's content was re-read; `length` is the characters it holds, never the value.
        case checked(matched: Bool, length: Int)
        /// The field was replaced by the page after the keys went in, so nothing could be read back.
        case unverified
    }

    /// nil: the extension did not measure it (older build, or the page could not be glanced at).
    package var changed: [String]?
    package var typed: Typed?

    package init(changed: [String]? = nil, typed: Typed? = nil) {
        self.changed = changed
        self.typed = typed
    }

    private static let categories: Set<String> = ["url", "title", "text"]

    /// Unknown words are dropped: a hostile extension cannot put a sentence into the model's context here.
    package static func decode(changed raw: Any?, typed rawTyped: Any?) -> BrowserEffect? {
        let changed = (raw as? [Any]).map { $0.compactMap { $0 as? String }.filter(categories.contains) }
        let typed = (rawTyped as? [String: Any]).flatMap(decodeTyped)
        guard changed != nil || typed != nil else { return nil }
        return BrowserEffect(changed: changed, typed: typed)
    }

    private static func decodeTyped(_ raw: [String: Any]) -> Typed? {
        if raw["outcome"] as? String == "applied_unverified" { return .unverified }
        guard let matched = raw["matched"] as? NSNumber, CFGetTypeID(matched) == CFBooleanGetTypeID(),
              let length = raw["length"] as? NSNumber, CFGetTypeID(length) != CFBooleanGetTypeID(),
              length.intValue >= 0
        else { return nil }
        return .checked(matched: matched.boolValue, length: length.intValue)
    }

    /// The short structured line the model reads after an action; nil when nothing was measured, so the
    /// caller keeps telling it to read the tab.
    package var line: String? {
        if let typed {
            switch typed {
            case .checked(true, _): return "typed: matched"
            case .checked(false, let length):
                return "typed: not matched; the field holds \(length) characters, not the text sent. Read the tab to see it"
            case .unverified:
                return "typed: applied_unverified; the page re-rendered the field, so it could not be read back. Read the tab to verify"
            }
        }
        guard let changed else { return nil }
        return changed.isEmpty
            ? "changed: none \u{2014} the page did not visibly change"
            : "changed: " + changed.joined(separator: ", ")
    }
}
