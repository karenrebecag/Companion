import Foundation

public enum ChatPrompt: Sendable {
    /// Personality always applies. The original concatenated it only on the
    /// named-owner branch because `+` binds tighter than `?:`.
    public static func profileBlock(
        about: String, instructions: String, language: AppLanguage = .en
    ) -> String? {
        let about = about.trimmingCharacters(in: .whitespacesAndNewlines)
        let instructions = instructions.trimmingCharacters(
            in: .whitespacesAndNewlines)
        var out = ""
        if !about.isEmpty {
            switch language {
            case .en: out += "About the user — \(about). "
            case .es: out += "Sobre la usuaria — \(about). "
            }
        }
        if !instructions.isEmpty {
            switch language {
            case .en: out += "The user's own instructions: \(instructions)"
            case .es:
                out += "Instrucciones personalizadas de la usuaria: "
                    + instructions
            }
        }
        return out.isEmpty ? nil : out
    }

    public static func system(
        ownerFirstName: String,
        delegateEnabled: Bool,
        about: String = "",
        instructions: String = "",
        language: AppLanguage = .en
    ) -> String {
        let owner = ownerFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        var prompt = greeting(owner: owner, language: language)
            + style(language)
        if let block = profileBlock(
            about: about, instructions: instructions, language: language) {
            prompt += " " + block
        }
        if delegateEnabled { prompt += " " + delegateRule(language) }
        return prompt
    }

    private static func greeting(owner: String, language: AppLanguage) -> String {
        switch language {
        case .en:
            return owner.isEmpty
                ? "You are Companion, the voice assistant on this Mac. "
                : "You are Companion, the voice assistant on \(owner)'s Mac. "
        case .es:
            return owner.isEmpty
                ? "Eres Companion, asistente de voz en esta Mac. "
                : "Eres Companion, asistente de voz en la Mac de \(owner). "
        }
    }

    /// The language belongs in the prompt, not only in the UI: the model
    /// answers in whatever this says, whatever the buttons look like.
    private static func style(_ language: AppLanguage) -> String {
        switch language {
        case .en:
            return "Answer in English, warm, direct, 2 to 4 sentences. "
                + "You are not Hermes, not a TUI, not in a terminal. "
                + "Do not invent backends or internal paths. "
                + "If you do not know something, say so. Talk, do not report."
        case .es:
            return "Español, cálido, directo, 2 a 4 frases. "
                + "No eres Hermes, no eres un TUI, no estás en una terminal. "
                + "No inventes backends ni rutas internas. "
                + "Si no sabes algo, dilo. Charla, no un informe."
        }
    }

    private static func delegateRule(_ language: AppLanguage) -> String {
        switch language {
        case .en:
            return "The specialist DOES have the files, the terminal, this "
                + "Mac's tools AND WEB SEARCH. Desktop, documents, reading or "
                + "editing files, code, commands, technical work, searching "
                + "the web or reading a page: call delegate. Never say you "
                + "cannot see the disk or have no internet — delegate. You "
                + "may say one short sentence before delegating."
        case .es:
            return "El especialista SÍ tiene los archivos, la "
                + "terminal, las herramientas de esta Mac Y BÚSQUEDA EN "
                + "INTERNET. Escritorio, documentos, leer o editar archivos, "
                + "código, comandos, trabajo técnico, buscar en la web o leer "
                + "una página: llama a delegate. Nunca digas que no puedes "
                + "ver el disco ni que no tienes internet — delega. Puedes "
                + "decir una frase corta antes de delegar."
        }
    }
}
