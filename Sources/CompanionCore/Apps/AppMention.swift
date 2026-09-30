import Foundation

/// 16k-3: does this turn name a connected (or connectable) app? The match
/// decides which app's tools travel to the model — the spec's context
/// budget rule (§5: never every app's tools, only the named one's) — and
/// when the "Conectar X" card shows for one that is not connected.
package enum AppMention {
    package struct Candidate: Sendable, Equatable {
        package let slug: String
        package let name: String

        package init(slug: String, name: String) {
            self.slug = slug
            self.name = name
        }
    }

    /// The first candidate whose full name appears in the words, on word
    /// boundaries: "slack" in "manda un slack", never in "slackline".
    /// Containment, not fuzzy scoring: a wrong fuzzy match would ship the
    /// wrong app's tools, and saying the app's name is how Incredible's
    /// own flow works.
    package static func match(_ said: String, in candidates: [Candidate]) -> String? {
        let words = fold(said)
        guard !words.isEmpty else { return nil }
        return candidates.first { candidate in
            let name = fold(candidate.name)
            guard !name.isEmpty else { return false }
            return words.range(of: "\\b\(NSRegularExpression.escapedPattern(for: name))\\b",
                               options: .regularExpression) != nil
        }?.slug
    }

    /// Lowercased, diacritics folded: "Búscalo en slÁck" still says Slack.
    private static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
    }
}
