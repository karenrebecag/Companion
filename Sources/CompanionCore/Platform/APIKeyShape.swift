import Foundation

/// What a pasted key has to look like before it is worth a network round
/// trip. Deliberately loose: rejecting a key that would have worked is worse
/// than letting a bad one reach the API and come back as a 401, so this only
/// catches what cannot be a key at all — a pasted URL, a truncation, a paste
/// that took a line break with it.
public enum APIKeyShape {
    /// Long enough to rule out a truncation without guessing at a length the
    /// provider is free to change.
    private static let minimumLength = 20

    public static func looksPlausible(_ raw: String) -> Bool {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-"), key.count >= minimumLength else {
            return false
        }
        return !key.contains(where: \.isWhitespace)
    }
}
