import Foundation

package enum EchoGuard: Sendable {
    package static func words(_ s: String) -> [String] {
        s.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
    }

    package static func isEcho(heard: String, agentSaying: String) -> Bool {
        let heardWords = words(heard)
        // No tokens means nothing to barge in with — treat as echo, not speech.
        guard !heardWords.isEmpty else { return true }
        let spoken = Set(words(agentSaying))
        guard !spoken.isEmpty else { return false }
        let hits = heardWords.filter { spoken.contains($0) }.count
        return Double(hits) / Double(heardWords.count) >= 0.6
    }

    package static func isRealInterruption(heard: String, agentSaying: String) -> Bool {
        words(heard).count >= 2 && !isEcho(heard: heard, agentSaying: agentSaying)
    }

    /// On speakers a VAD segment can SPAN the agent's echo and the user's real
    /// words — the mic heard the reply's tail, then the user. Strip the
    /// leading run of words that belong to the agent's utterance (three or
    /// more, so a user who also opens with "hola" is not robbed) and return
    /// what the user actually said. Everything echoed → empty → drop it.
    package static func scrub(heard: String, agentSaying: String) -> String {
        let agentWords = Set(words(agentSaying))
        guard !agentWords.isEmpty else { return heard }
        let heardWords = words(heard)
        var cut = 0
        for word in heardWords {
            guard agentWords.contains(word) else { break }
            cut += 1
        }
        guard cut >= 3 else { return heard }
        return heardWords.dropFirst(cut).joined(separator: " ")
    }
}
