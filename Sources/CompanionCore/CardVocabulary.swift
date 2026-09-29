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
public enum CardVocabulary: Sendable {
    public static func text(_ language: AppLanguage = .en) -> String {
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
                + "https,\"caption\"}]}. For figures emit ```\(CompanionBlocks.statsLanguage) "
                + "with {\"title\",\"items\":[{\"label\",\"value\",\"delta\"}]}; for "
                + "rows emit ```\(CompanionBlocks.tableLanguage) with {\"title\",\"columns\":[...],"
                + "\"rows\":[[...]]}; for a series emit ```\(CompanionBlocks.chartLanguage) with "
                + "{\"title\",\"kind\":\"bar|line|area|pie|donut|scatter|polar|radar\",\"unit\",\"labels\":[...],"
                + "\"series\":[{\"name\",\"values\":[numbers, one per label]}]}. Only numbers "
                + "you looked up or were given — never invented. "
                + "Chart only when the shape is the point (a trend, a share, a comparison). "
                + "Limits, past which the client shows a table instead: pie, donut and polar take "
                + "ONE series of values >= 0 and at most \(ChartBlock.maxSlices) slices; radar needs "
                + "3 to \(ChartBlock.maxRadarAxes) axes; bar, line, area and scatter at most "
                + "\(ChartBlock.maxCartesianPoints) points (labels x series). Never more than "
                + "\(ChartBlock.maxSeries) series or \(ChartBlock.maxPoints) labels. "
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
                + "\"caption\"}]}. Para cifras emite ```\(CompanionBlocks.statsLanguage) "
                + "con {\"title\",\"items\":[{\"label\",\"value\",\"delta\"}]}; para filas "
                + "emite ```\(CompanionBlocks.tableLanguage) con {\"title\",\"columns\":[...],"
                + "\"rows\":[[...]]}; para una serie emite ```\(CompanionBlocks.chartLanguage) con "
                + "{\"title\",\"kind\":\"bar|line|area|pie|donut|scatter|polar|radar\",\"unit\",\"labels\":[...],"
                + "\"series\":[{\"name\",\"values\":[números, uno por etiqueta]}]}. Solo números "
                + "que consultaste o te dieron — nunca inventados. "
                + "Grafica solo cuando la forma es lo que importa (una tendencia, una proporción, una comparación). "
                + "Límites, pasados los cuales el cliente muestra una tabla: pie, donut y polar llevan "
                + "UNA serie de valores >= 0 y como mucho \(ChartBlock.maxSlices) rebanadas; radar pide "
                + "de 3 a \(ChartBlock.maxRadarAxes) ejes; barras, líneas, área y dispersión como mucho "
                + "\(ChartBlock.maxCartesianPoints) puntos (etiquetas x series). Nunca más de "
                + "\(ChartBlock.maxSeries) series ni \(ChartBlock.maxPoints) etiquetas. "
                + "Si nada aplica, markdown normal."
        }
    }
}
