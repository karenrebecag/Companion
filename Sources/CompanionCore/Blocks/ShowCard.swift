import Foundation

/// Figures, rows and series as a tool call instead of a text fence.
///
/// A fence is taught in prose and the model only imitates it: the fast brain
/// left them unclosed, the speech filter read them aloud, and a reply that was
/// only a card was stored empty. A tool call is validated against a schema by
/// the provider, arrives whole, and lands on `ChatMessage.card` — the channel
/// the interface already paints — so speech and display never share a parser.
/// The specialists keep the fences: a CLI cannot call the app's tools.
package enum ShowCard: Sendable {
    package static let name = "show_card"

    package static func spec(_ language: AppLanguage) -> ToolSpec {
        ToolSpec(
            name: name,
            description: description(language),
            properties: [],
            required: ["card"],
            rawParametersJSON: parameters)
    }

    /// Nil when the arguments cannot become a card; the caller reports that
    /// to the model so it can retry instead of saying something was shown.
    package static func payload(from arguments: [String: Any]) -> CardPayload? {
        switch arguments["card"] as? String {
        case "stats": CompanionBlocks.stats(from: arguments).map(CardPayload.stats)
        case "table": CompanionBlocks.table(from: arguments).map(CardPayload.table)
        case "chart": CompanionBlocks.chart(from: arguments)
        default: nil
        }
    }

    /// What the model reads back. It already knows the numbers; what it must
    /// not do is read them aloud or claim the card went anywhere else.
    package static func shown(_ payload: CardPayload) -> String {
        let title = payload.title.map { " \"\($0)\"" } ?? ""
        return "shown\(title) on the island. Say at most one short sentence about "
            + "what it shows; do not read the numbers aloud."
    }

    private static func description(_ language: AppLanguage) -> String {
        switch language {
        case .en:
            "Show figures, a table or a chart on screen, right under the island. "
                + "Use it whenever the answer is numbers the user wants to see: "
                + "\"card\": \"stats\" for a few figures, \"table\" for rows, "
                + "\"chart\" for a series. Never create a document for this. "
                + "Only numbers you looked up or were given."
        case .es:
            "Muestra cifras, una tabla o una gráfica en pantalla, debajo de la isla. "
                + "Úsala siempre que la respuesta sean números que la usuaria quiere ver: "
                + "\"card\": \"stats\" para unas pocas cifras, \"table\" para filas, "
                + "\"chart\" para una serie. Nunca crees un documento para esto. "
                + "Solo números que consultaste o te dieron."
        }
    }

    /// One flat object rather than `oneOf`: several OpenAI-compatible
    /// providers, the fast brain's among them, reject or ignore `oneOf`.
    private static let parameters = """
        {"type":"object","properties":{\
        "card":{"type":"string","enum":["stats","table","chart"]},\
        "title":{"type":"string"},\
        "items":{"type":"array","description":"stats only",\
        "items":{"type":"object","properties":{"label":{"type":"string"},\
        "value":{"type":"string"},"delta":{"type":"string"}},"required":["label","value"]}},\
        "columns":{"type":"array","description":"table only","items":{"type":"string"}},\
        "rows":{"type":"array","description":"table only, one array of cells per row",\
        "items":{"type":"array","items":{"type":"string"}}},\
        "kind":{"type":"string","description":"chart only",\
        "enum":["bar","line","area","pie","donut","scatter","polar","radar"]},\
        "unit":{"type":"string","description":"chart only"},\
        "labels":{"type":"array","description":"chart only","items":{"type":"string"}},\
        "series":{"type":"array","description":"chart only",\
        "items":{"type":"object","properties":{"name":{"type":"string"},\
        "values":{"type":"array","items":{"type":"number"},"description":"one per label"}},\
        "required":["values"]}}},\
        "required":["card"]}
        """
}

extension CardPayload {
    package var title: String? {
        switch self {
        case .locations(let block): block.title
        case .gallery(let block): block.title
        case .stats(let block): block.title
        case .table(let block): block.title
        case .chart(let block): block.title
        }
    }
}
