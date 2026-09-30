import Foundation

/// Wave 16h-1 (H1): what makes a `type_text` a success line. Injecting text
/// proves nothing; the field read back holding it does.
public enum TypedProof: Sendable {
    /// What the runner appends to a `type_text` result nobody read back, so
    /// the model does not report a success it has not checked.
    public static let unverifiedNote = " (not read back)"
    public static let verifiedNote = " (read back, matches)"

    /// The text is in the field more times than it was before typing. A field
    /// that already held it, or a short word ("sí") already there, proves
    /// nothing; without a readable baseline there is nothing to compare.
    public static func verifies(typed: String, read: String, before: Int?) -> Bool {
        guard let before else { return false }
        return occurrences(of: typed, in: read) > before
    }

    /// Non-overlapping, without case or accents.
    public static func occurrences(of typed: String, in text: String) -> Int {
        let wanted = fold(typed)
        guard !wanted.isEmpty else { return 0 }
        return fold(text).components(separatedBy: wanted).count - 1
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
