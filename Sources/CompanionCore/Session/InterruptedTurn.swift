import Foundation

/// A turn the user cut by writing over it. Words it never acted on must not
/// vanish: they go into the next turn with the new ones. A turn that already
/// used a tool stays on the thread as said, because its action has happened.
package enum InterruptedTurn {
    /// The cut turn's words that carry forward; nil when it already acted.
    package static func carried(_ words: String, toolsRan: Bool) -> String? {
        let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !toolsRan, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// The next turn's text: the carried words first, in the order they were said.
    package static func merged(carried: String?, next: String) -> String {
        guard let carried else { return next }
        return carried + "\n" + next
    }
}
