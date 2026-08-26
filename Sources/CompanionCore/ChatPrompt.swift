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
        webSearchEnabled: Bool = false,
        about: String = "",
        instructions: String = "",
        language: AppLanguage = .en,
        memory: String = ""
    ) -> String {
        let owner = ownerFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        var prompt = greeting(owner: owner, language: language)
            + style(language)
        if let block = profileBlock(
            about: about, instructions: instructions, language: language) {
            prompt += " " + block
        }
        if delegateEnabled {
            prompt += " " + delegateRule(language, web: webSearchEnabled)
        }
        // The chat layer paints cards too. It used to be the specialist's
        // privilege by accident — nobody decided it, the vocabulary simply
        // lived in the specialist's role — so a question about a place that
        // needed no delegation could not produce the map the client already
        // knew how to draw.
        prompt += " " + CardVocabulary.text(language)
        // Memory travels LAST and pre-framed as data: what earlier sessions
        // recorded must inform the answer, never override the rules above.
        if !memory.isEmpty {
            prompt += "\n\n" + memory
        }
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

    /// The web half is conditional on purpose. Promising search the product
    /// cannot do sent the model to a tool that always failed, and it reported
    /// back "I cannot search the web" instead of trying another route — the
    /// promise was what captured the intent.
    private static func delegateRule(
        _ language: AppLanguage, web: Bool
    ) -> String {
        switch language {
        case .en:
            let reach = web
                ? "this Mac's tools AND WEB SEARCH"
                : "this Mac's tools, and it can look up real places and open "
                    + "a page by URL"
            return "The specialist DOES have the files, the terminal, \(reach). "
                + "Desktop, documents, reading or editing files, code, "
                + "commands, technical work, places, reading a page: call "
                + "delegate. Never say you cannot see the disk — delegate. You "
                + "may say one short sentence before delegating. If asked how "
                + "you work: the delegate tool runs a specialist agent on this "
                + "Mac — Claude Code when installed, otherwise a built-in "
                + "executor — and you speak through OpenAI's realtime API. Be "
                + "plain about it; there is nothing to hide."
        case .es:
            let reach = web
                ? "las herramientas de esta Mac Y BÚSQUEDA EN INTERNET"
                : "las herramientas de esta Mac, y puede consultar lugares "
                    + "reales y abrir una página por su URL"
            return "El especialista SÍ tiene los archivos, la terminal, "
                + "\(reach). Escritorio, documentos, leer o editar archivos, "
                + "código, comandos, trabajo técnico, lugares, leer una "
                + "página: llama a delegate. Nunca digas que no puedes ver el "
                + "disco — delega. Puedes decir una frase corta antes de "
                + "delegar. Si te preguntan cómo funcionas: la tool delegate "
                + "corre un agente especialista en esta Mac — Claude Code si "
                + "está instalado, o un ejecutor nativo integrado — y tú "
                + "hablas a través de la API realtime de OpenAI. Dilo claro; "
                + "no hay nada que esconder."
        }
    }
}
