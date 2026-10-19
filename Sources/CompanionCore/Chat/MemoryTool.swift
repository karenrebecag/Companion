import Foundation

/// Where `remember` writes. File-backed in Services; a fake in tests.
package protocol MemoryNoting: Sendable {
    func remember(_ fact: String) throws
}

/// `remember` on the wire: a short fact the user asked to keep, written into
/// the same notes Settings › Memoria lists and the next conversation's prompt
/// loads. Forgetting stays in Settings: a `forget` tool would need the model
/// to name an id it can only guess.
package enum MemoryTool {
    package static let name = "remember"
    package static let maxFact = 300

    package static func spec(_ language: AppLanguage) -> ToolSpec {
        let (tool, fact): (String, String) = switch language {
        case .en:
            ("Save one short fact about the user so future conversations know it, when she "
                + "asks you to remember something (\"remember that I prefer short answers\"). "
                + "Never save passwords, keys, tokens or card numbers.",
             "the fact, one sentence, in her words")
        case .es:
            ("Guarda un dato corto sobre la usuaria para que las conversaciones futuras lo "
                + "sepan, cuando te pide recordar algo («recuerda que prefiero respuestas "
                + "cortas»). Nunca guardes contraseñas, claves, tokens ni números de tarjeta.",
             "el dato, una frase, en sus palabras")
        }
        return ToolSpec(
            name: name, description: tool,
            properties: [ToolProperty(name: "fact", type: "string", description: fact)],
            required: ["fact"])
    }

    /// The fact to store, or why it is refused. A fact that the redaction
    /// would change is refused whole instead of saved masked: a note that
    /// reads "my password is [redacted]" is noise that outlives the secret.
    package static func accepted(_ raw: String) -> Result<String, ContractError> {
        let flat = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !flat.isEmpty else { return .failure(.invalidArgs("missing fact")) }
        guard flat.count <= maxFact else {
            return .failure(.invalidArgs("fact is longer than \(maxFact) characters; shorten it"))
        }
        guard !TurnRedaction.holdsStrongLabel(flat), TurnRedaction.redact(flat) == flat else {
            return .failure(ContractError(
                code: "refused", message: "that looks like a secret; it was not saved"))
        }
        return .success(flat)
    }

    package static func status(_ outcome: ParentToolOutcome, _ language: AppLanguage) -> String {
        switch (outcome.ok, language) {
        case (true, .en): "Remembered."
        case (true, .es): "Lo recordaré."
        case (false, .en): "Did not save it: \(outcome.output)"
        case (false, .es): "No lo guardé: \(outcome.output)"
        }
    }
}
