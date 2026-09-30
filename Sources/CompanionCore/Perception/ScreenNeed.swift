import Foundation

/// Wave 15b-7. Vision (13a) starts on press, but waiting for it at commit is
/// not free: most orders never touch the screen. Pure so the decision is
/// testable without a running capture pipeline.
package enum ScreenNeed {
    /// es/en cues for an order that points at what is on screen. Kept as
    /// plain substrings — folded, never exact-word matched — because the
    /// corpus of real utterances is short phrases, not sentences worth
    /// tokenizing.
    private static let screenCues: [String] = [
        "esto", "esta", "aqui", "pantalla", "lo que ves", "lo que veo",
        "this", "here", "screen", "see", "what's on",
    ]

    /// 2 s only when the order names the screen; `.zero` otherwise. An
    /// empty utterance never waits — there is nothing said to resolve
    /// against the screen. Wave 15g-5: missing AX text used to buy the 2 s
    /// too, and most orders paid it for a screen they never asked about; a
    /// late vision result now rides the next turn instead (`ScreenSight`).
    /// `hasText` stays in this signature for the tests that pin the old
    /// contract; the runtime calls `wait(utterance:)`.
    package static func wait(utterance: String, hasText: Bool) -> Duration {
        wait(utterance: utterance)
    }

    package static func wait(utterance: String) -> Duration {
        let trimmed = utterance.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .zero }
        return pointsAtScreen(trimmed) ? .seconds(2) : .zero
    }

    /// Accent- and case-insensitive: "¿qué dice esto?" and "ESTO" both hit
    /// the same cue.
    private static func pointsAtScreen(_ utterance: String) -> Bool {
        let folded = utterance.folding(
            options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        return screenCues.contains { folded.contains($0) }
    }
}
