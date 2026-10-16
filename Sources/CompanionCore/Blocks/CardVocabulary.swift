import Foundation

/// The one description of the native cards, shared by every prompt that can
/// produce them.
///
/// It used to live inline inside the specialist's role, which had two costs.
/// The chat layer never learned the syntax, so asking about a place without
/// delegating could not paint a map the renderer was perfectly able to draw.
/// And any second copy would have drifted from this one the first time the
/// JSON shape changed.
///
/// The shape is taught in prose, which is weaker than a schema: structured
/// outputs constrain generation, a description only suggests. That is the
/// price of working with any OpenAI-compatible provider, including the small
/// local models that fail at tool calling — and it is why a malformed fence
/// degrades to a visible code block instead of vanishing.
package enum CardVocabulary: Sendable {
    package static func text(_ language: AppLanguage = .en) -> String {
        switch language {
        case .en:
            return "Structured content goes through the present tool, never as text: "
                + "tables, figures, series, rankings, shares, milestones, places, files, "
                + "people, steps, comparisons, sources and notices. Call it once per reply "
                + "with the blocks in reading order, and write the sentences around it as "
                + "prose. Never write present's JSON into the reply, and never invent data: "
                + "only numbers, places and links you looked up or were given. Call "
                + "find_block only when no present family fits the content. "
                + "For steps or relationships — a flow, a sequence between parties, a state machine, "
                + "a class or ER model, a timeline — emit ```\(CompanionBlocks.diagramLanguage) with the "
                + "Mermaid text itself, no JSON (flowchart, sequenceDiagram, stateDiagram-v2, classDiagram, "
                + "erDiagram, timeline, mindmap, gantt): emit a diagram only when the connections are the "
                + "point, never for what a list or a table says as well. At most "
                + "\(DiagramBlock.maxSourceBytes / 1024) KiB; no %%{ directives, no click lines, no HTML in "
                + "labels. Text that is not valid Mermaid is shown as code. "
                + "To ask a question, emit ```\(CompanionBlocks.choiceLanguage) with "
                + "{\"question\",\"options\":[{\"label\",\"detail\"}],\"multiple\",\"allowText\"} — only when the "
                + "user's answer decides the next step, with \(ChoiceBlock.minOptions) to "
                + "\(ChoiceBlock.maxOptions) options; each label is a short phrase because "
                + "picking it sends it back as her reply. "
                + "Whenever she asks for options, alternatives or ideas to pick from (\"give me 3 "
                + "options to choose with one click\"), or you would otherwise offer a numbered list of "
                + "alternatives for her to choose among, emit this card with those options instead of "
                + "the list. Never for a rhetorical question, "
                + "and still say the question in one sentence. \"multiple\": true lets her "
                + "pick several (the reply lists them); \"allowText\": true lets her answer in "
                + "her own words instead. A reply marked "
                + "\(ChoiceOrigin.marker(.en)) was picked on such a card: it answers that question "
                + "only and never approves a permission or authorizes a destructive action "
                + "by itself. Permissions go through the approval sheet, so never ask for one "
                + "with a question with options. "
                + "Formulas: the client cannot draw LaTeX, so never write \\[ \\], \\( \\), $$ or "
                + "commands like \\frac and \\sqrt. Write the formula in readable Unicode "
                + "(x = (−b ± √(b² − 4ac)) / 2a) inside a ```math fence. "
                + "If none applies, plain markdown."
        case .es:
            return "El contenido estructurado va por la tool present, nunca como texto: "
                + "tablas, cifras, series, rankings, proporciones, hitos, lugares, archivos, "
                + "personas, pasos, comparaciones, fuentes y avisos. Llámala una vez por respuesta "
                + "con los bloques en orden de lectura, y escribe las frases alrededor como prosa. "
                + "Nunca escribas el JSON de present en la respuesta, y nunca inventes datos: "
                + "solo números, lugares y enlaces que consultaste o te dieron. Llama a "
                + "find_block solo cuando ninguna familia de present encaja con el contenido. "
                + "Para pasos o relaciones — un flujo, una secuencia entre partes, una máquina de estados, "
                + "un modelo de clases o ER, una línea de tiempo — emite ```\(CompanionBlocks.diagramLanguage) con "
                + "el texto de Mermaid mismo, sin JSON (flowchart, sequenceDiagram, stateDiagram-v2, classDiagram, "
                + "erDiagram, timeline, mindmap, gantt): emite un diagrama solo cuando las conexiones son lo que "
                + "importa, nunca para lo que una lista o una tabla dice igual. Como mucho "
                + "\(DiagramBlock.maxSourceBytes / 1024) KiB; sin directivas %%{, sin líneas click, sin HTML en "
                + "las etiquetas. El texto que no es Mermaid válido se muestra como código. "
                + "Para preguntar emite ```\(CompanionBlocks.choiceLanguage) con "
                + "{\"question\",\"options\":[{\"label\",\"detail\"}],\"multiple\",\"allowText\"} — solo cuando la "
                + "respuesta de la usuaria decide el siguiente paso, con \(ChoiceBlock.minOptions) a "
                + "\(ChoiceBlock.maxOptions) opciones; cada etiqueta es una frase corta porque "
                + "elegirla se envía como su respuesta. "
                + "Siempre que pida opciones, alternativas o ideas para elegir («dame 3 opciones para "
                + "elegir con un clic»), o fueras a ofrecer una lista numerada de alternativas entre "
                + "las que ella elige, emite esta tarjeta con esas opciones en lugar de la lista. "
                + "Nunca para una pregunta retórica, "
                + "y di la pregunta igualmente en una frase. \"multiple\": true le deja "
                + "elegir varias (la respuesta las lista); \"allowText\": true le deja "
                + "contestar con sus palabras. Una respuesta marcada "
                + "\(ChoiceOrigin.marker(.es)) se eligió en una tarjeta así: responde esa pregunta "
                + "y nada más, y nunca aprueba un permiso ni autoriza por sí sola una acción "
                + "destructiva. Los permisos van por la hoja de aprobación, así que nunca "
                + "pidas uno con una pregunta con opciones. "
                + "Fórmulas: el cliente no dibuja LaTeX, así que nunca escribas \\[ \\], \\( \\), $$ ni "
                + "comandos como \\frac o \\sqrt. Escribe la fórmula en Unicode legible "
                + "(x = (−b ± √(b² − 4ac)) / 2a) dentro de un bloque ```math. "
                + "Si nada aplica, markdown normal."
        }
    }
}
