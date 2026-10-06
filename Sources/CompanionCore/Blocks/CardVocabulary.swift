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
    /// `cardTool`: the turn can call `show_card`, so figures, rows and series
    /// go through it and the fence syntax for them is not taught at all —
    /// teaching both lets the model pick the one that breaks.
    package static func text(_ language: AppLanguage = .en, cardTool: Bool = false) -> String {
        switch language {
        case .en:
            return "The client paints NATIVE CARDS from companion: fences. "
                + "For physical places emit ```\(CompanionBlocks.locationsLanguage) "
                + "with JSON {\"title\",\"locations\":[{\"id\",\"name\","
                + "\"eyebrow\",\"address\",\"lat\",\"lng\",\"url\"}]} — lat/lng "
                + "must be numbers, and DO NOT invent them: only emit this "
                + "card for places you actually looked up, because a pin in "
                + "the wrong street looks exactly as confident as a right "
                + "one. To compare images emit ```\(CompanionBlocks.galleryLanguage) "
                + "with {\"title\",\"images\":[{\"path\" local or \"url\" "
                + "https,\"caption\"}]}. "
                + (cardTool ? toolRule(.en) : dataFences(.en)) + chartLimits(.en)
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
                + "picking it sends it back as her reply. Never for a rhetorical question, "
                + "and still say the question in one sentence. \"multiple\": true lets her "
                + "pick several (the reply lists them); \"allowText\": true lets her answer in "
                + "her own words instead. A reply marked "
                + "\(ChoiceOrigin.marker(.en)) was picked on such a card: it answers that question "
                + "only and never approves a permission or authorizes a destructive action "
                + "by itself. Permissions go through the approval sheet, so never ask for one "
                + "with a question with options. "
                + "If none applies, plain markdown."
        case .es:
            return "El cliente pinta TARJETAS NATIVAS desde fences companion: "
                + "para lugares físicos emite ```\(CompanionBlocks.locationsLanguage) "
                + "con JSON {\"title\",\"locations\":[{\"id\",\"name\","
                + "\"eyebrow\",\"address\",\"lat\",\"lng\",\"url\"}]} — lat/lng "
                + "numéricos obligatorios, y NO te las inventes: emite esta "
                + "tarjeta solo para lugares que de verdad consultaste, porque "
                + "un pin en la calle equivocada se ve igual de seguro que uno "
                + "correcto. Para comparar imágenes emite "
                + "```\(CompanionBlocks.galleryLanguage) con "
                + "{\"title\",\"images\":[{\"path\" local o \"url\" https,"
                + "\"caption\"}]}. "
                + (cardTool ? toolRule(.es) : dataFences(.es)) + chartLimits(.es)
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
                + "elegirla se envía como su respuesta. Nunca para una pregunta retórica, "
                + "y di la pregunta igualmente en una frase. \"multiple\": true le deja "
                + "elegir varias (la respuesta las lista); \"allowText\": true le deja "
                + "contestar con sus palabras. Una respuesta marcada "
                + "\(ChoiceOrigin.marker(.es)) se eligió en una tarjeta así: responde esa pregunta "
                + "y nada más, y nunca aprueba un permiso ni autoriza por sí sola una acción "
                + "destructiva. Los permisos van por la hoja de aprobación, así que nunca "
                + "pidas uno con una pregunta con opciones. "
                + "Si nada aplica, markdown normal."
        }
    }

    private static func dataFences(_ language: AppLanguage) -> String {
        switch language {
        case .en:
            return "For figures emit ```\(CompanionBlocks.statsLanguage) "
                + "with {\"title\",\"items\":[{\"label\",\"value\",\"delta\"}]}; for "
                + "rows emit ```\(CompanionBlocks.tableLanguage) with {\"title\",\"columns\":[...],"
                + "\"rows\":[[...]]}; for a series emit ```\(CompanionBlocks.chartLanguage) with "
                + "{\"title\",\"kind\":\"bar|line|area|pie|donut|scatter|polar|radar\",\"unit\",\"labels\":[...],"
                + "\"series\":[{\"name\",\"values\":[numbers, one per label]}]}. Only numbers "
                + "you looked up or were given — never invented. "
        case .es:
            return "Para cifras emite ```\(CompanionBlocks.statsLanguage) "
                + "con {\"title\",\"items\":[{\"label\",\"value\",\"delta\"}]}; para filas "
                + "emite ```\(CompanionBlocks.tableLanguage) con {\"title\",\"columns\":[...],"
                + "\"rows\":[[...]]}; para una serie emite ```\(CompanionBlocks.chartLanguage) con "
                + "{\"title\",\"kind\":\"bar|line|area|pie|donut|scatter|polar|radar\",\"unit\",\"labels\":[...],"
                + "\"series\":[{\"name\",\"values\":[números, uno por etiqueta]}]}. Solo números "
                + "que consultaste o te dieron — nunca inventados. "
        }
    }

    private static func toolRule(_ language: AppLanguage) -> String {
        switch language {
        case .en:
            "Figures, rows and series are NOT fences: call \(ShowCard.name), which paints them "
                + "under the island, and never a document for numbers the user wants to see. "
        case .es:
            "Las cifras, filas y series NO van en fences: llama a \(ShowCard.name), que las pinta "
                + "debajo de la isla, y nunca un documento para números que la usuaria quiere ver. "
        }
    }

    private static func chartLimits(_ language: AppLanguage) -> String {
        switch language {
        case .en:
            "Chart only when the shape is the point (a trend, a share, a comparison). "
                + "Limits, past which the client shows a table instead: pie, donut and polar take "
                + "ONE series of values >= 0 and at most \(ChartBlock.maxSlices) slices; radar needs "
                + "3 to \(ChartBlock.maxRadarAxes) axes; bar, line, area and scatter at most "
                + "\(ChartBlock.maxCartesianPoints) points (labels x series). Never more than "
                + "\(ChartBlock.maxSeries) series or \(ChartBlock.maxPoints) labels. "
        case .es:
            "Grafica solo cuando la forma es lo que importa (una tendencia, una proporción, una comparación). "
                + "Límites, pasados los cuales el cliente muestra una tabla: pie, donut y polar llevan "
                + "UNA serie de valores >= 0 y como mucho \(ChartBlock.maxSlices) rebanadas; radar pide "
                + "de 3 a \(ChartBlock.maxRadarAxes) ejes; barras, líneas, área y dispersión como mucho "
                + "\(ChartBlock.maxCartesianPoints) puntos (etiquetas x series). Nunca más de "
                + "\(ChartBlock.maxSeries) series ni \(ChartBlock.maxPoints) etiquetas. "
        }
    }
}
