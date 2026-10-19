import Foundation

/// What a pasted key has to look like before it is worth a network round
/// trip. Deliberately loose: rejecting a key that would have worked is worse
/// than letting a bad one reach the API and come back as a 401, so this only
/// catches what cannot be a key at all — a pasted URL, a truncation, a paste
/// that took a line break with it. No prefix is checked: providers change
/// theirs, and the Cerebras key is not the `sk-` form.
package enum APIKeyShape {
    /// Long enough to rule out a truncation without guessing at a length the
    /// provider is free to change.
    private static let minimumLength = 20

    package static func looksPlausible(_ raw: String) -> Bool {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= minimumLength, !key.contains("://") else {
            return false
        }
        return !key.contains(where: \.isWhitespace)
    }
}
