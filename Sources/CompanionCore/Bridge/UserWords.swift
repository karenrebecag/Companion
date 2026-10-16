import Foundation

/// What the user said in the turn, from the trusted channel (the mic). A type
/// of its own so that no other string passes as "the user's words", and so
/// that printing anything that holds it never prints them.
package struct UserWords: Sendable, Equatable, CustomStringConvertible,
    CustomDebugStringConvertible, CustomReflectable
{
    package static let maxLength = 1000

    package let text: String

    /// nil when nothing is left after sanitising: there is nothing to judge.
    package init?(heard: String) {
        let clean = TextSanitizer.display(heard, maxLength: Self.maxLength)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        text = clean
    }

    package var description: String { "<user words: \(text.count) chars>" }
    package var debugDescription: String { description }
    package var customMirror: Mirror { Mirror(self, children: []) }
}
