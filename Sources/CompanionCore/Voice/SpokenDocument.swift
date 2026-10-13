import Foundation

/// The voice brain's contract for a reply with structure (Incredible's
/// pattern): one spoken sentence, and a document the island shows. The
/// model calls `show_document` with the two apart, so the runtime speaks
/// `say`, threads `markdown` and lands the document card deterministically.
///
/// Asking for free-form markdown under a sentence and guessing its shape
/// never converged: live on 2026-10-12 the same request came back as a
/// pipe table, a table without leading pipes, a ```companion:table fence,
/// semicolon prose, two sentences and a refusal. A tool call has one shape.
/// Measured live on gpt-oss-120b (Cerebras): 15/15 requests with structure
/// took the tool and a plain question never did; the whole call lands
/// 0.3-0.8 s after the request, so nothing is streamed out of it early.
package struct SpokenDocument: Sendable, Equatable {
    package static let toolName = "show_document"

    /// The only sentence the voice says.
    package var say: String
    package var title: String?
    /// The whole document, as the island renders it.
    package var markdown: String

    package init(say: String, title: String? = nil, markdown: String) {
        self.say = say
        self.title = title
        self.markdown = markdown
    }

    /// Names are wire contract; the description follows the answer language
    /// like every other voice tool. Never `strict`: Cerebras refuses a tool
    /// list with mixed strict values (live 2026-10-12), and the parent
    /// tools travel without it.
    package static func spec(_ language: AppLanguage) -> ToolSpec {
        switch language {
        case .en:
            return ToolSpec(
                name: toolName,
                description: "Show a document on screen (a table, a list, steps, several "
                    + "paragraphs) while the voice says ONE sentence. Always use it when the "
                    + "answer has structure or does not fit in two spoken sentences; never "
                    + "write that structure in the spoken text. Not a file: create_document "
                    + "is for files only.",
                properties: [
                    ToolProperty(name: "say", type: "string",
                                 description: "the one short sentence said out loud"),
                    ToolProperty(name: "title", type: "string",
                                 description: "a short title for the document"),
                    ToolProperty(name: "markdown", type: "string",
                                 description: "the whole document in markdown: the table, the "
                                     + "numbered list or the paragraphs asked for"),
                ],
                required: ["say", "title", "markdown"])
        case .es:
            return ToolSpec(
                name: toolName,
                description: "Muestra un documento en pantalla (una tabla, una lista, pasos, "
                    + "varios párrafos) mientras la voz dice UNA frase. Úsala siempre que la "
                    + "respuesta tenga estructura o no quepa en dos frases habladas; nunca "
                    + "escribas esa estructura en el texto hablado. No es un archivo: "
                    + "create_document es solo para archivos.",
                properties: [
                    ToolProperty(name: "say", type: "string",
                                 description: "la única frase, corta, que se dice en voz alta"),
                    ToolProperty(name: "title", type: "string",
                                 description: "título corto del documento"),
                    ToolProperty(name: "markdown", type: "string",
                                 description: "el documento completo en markdown: la tabla, la "
                                     + "lista numerada o los párrafos pedidos"),
                ],
                required: ["say", "title", "markdown"])
        }
    }

    /// The call as the model wrote it; nil when it carries no document.
    /// A blank `say` keeps the document: the island shows it either way,
    /// and the runtime says a line of its own so the turn still sounds.
    package static func parse(arguments: String) -> SpokenDocument? {
        guard let object = ToolArguments.parse(arguments),
              let markdown = (object["markdown"] as? String)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !markdown.isEmpty
        else { return nil }
        let say = ((object["say"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let title = (object["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return SpokenDocument(
            say: say, title: title.flatMap { $0.isEmpty ? nil : $0 }, markdown: markdown)
    }

    /// What the voice says when the model left `say` empty.
    package static func fallbackSay(_ language: AppLanguage) -> String {
        switch language {
        case .en: "Here it is."
        case .es: "Aquí lo tienes."
        }
    }

    /// The reply as the thread keeps it: the sentence, then the document, so
    /// the next turn's "that table" has a referent and the island's result
    /// card renders the document the way a typed reply's would.
    package func threaded(after said: String) -> String {
        let lead = said.trimmingCharacters(in: .whitespacesAndNewlines)
        return lead.isEmpty ? markdown : lead + "\n\n" + markdown
    }
}
