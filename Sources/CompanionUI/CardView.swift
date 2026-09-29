import CompanionCore
import SwiftUI

/// A card, with where its data came from.
///
/// The industry contract has the application supply the data and the model
/// only choose what to show. Our CLI specialists cannot honour that — they
/// return text, so a fence is their only channel — and rather than ban the
/// fence and take cards away from them, the difference is shown.
///
/// This is not decoration. A pin the model wrote from memory renders exactly
/// as confident as one that was looked up, and that equivalence IS the defect:
/// a wrong street looks as certain as a right one.
///
/// The wording is a claim about US, not about the model, and that correction
/// came from seeing it in use. The first version said "written by the
/// assistant, not looked up" — under a card whose specialist had just run
/// three web searches and said so. It was technically true about the fence and
/// false about the work, and it undercut data that was right. What Companion
/// can honestly assert is only what Companion checked.
/// Metricas de las tarjetas del modelo. Patron de `SettingsOverlayMetrics`:
/// la medida vive nombrada en un sitio, no suelta en la vista. El alto del mapa y el lado de la miniatura se re-derivan
/// cuando R-02 aterrice el tier de `Section`.
enum CardMetrics {
    static let map: CGFloat = 200
    static let thumb: CGFloat = 120
    /// Wave 20: a stat tile's narrowest column, a chart's plot, a table's cap.
    static let statMin: CGFloat = 120
    static let chart: CGFloat = 200
    static let tableMax: CGFloat = 320
    /// Columna del icono de fila: un paso de la rampa, no un numero.
    static let iconColumn: CGFloat = Space.x4
}

extension View {
    /// Chrome comun de las tarjetas. Estaba copiado tres veces, y en las tres
    /// el relleno usaba el token y el filete un literal: al cambiar `Radius`
    /// se desincronizan y nada lo avisa. Aqui comparten UNO.
    func cardSurface() -> some View {
        // 16l-3: Incredible's elevated card — white, #eee edge, radius 16.
        padding(CardChrome.padding)
            .background(
                RoundedRectangle(cornerRadius: CardChrome.radius)
                    .fill(Semantic.surface))
            .overlay(
                RoundedRectangle(cornerRadius: CardChrome.radius)
                    .stroke(Semantic.borderChrome, lineWidth: Stroke.hairline))
    }
}

struct CardView: View {
    let card: Card

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            switch card.payload {
            case .locations(let block):
                MapCard(block: block)
            case .gallery(let block):
                GalleryCard(block: block)
            case .stats(let block):
                StatsCard(block: block)
            case .table(let block):
                TableCard(block: block)
            case .chart(let block):
                ChartCard(block: block)
            }
            // Only the cards that claim something about the WORLD carry the
            // caveat: a place that may not exist, an image that may not be
            // what it says. Stats, tables and charts restate the answer's
            // own numbers — captioning those "unverified locations" (16m
            // snapshot) undercut data that was simply the reply.
            if card.source == .model, claimsWorld {
                Text(Localized.string("card.unverified"))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var claimsWorld: Bool {
        switch card.payload {
        case .locations, .gallery: true
        case .stats, .table, .chart: false
        }
    }
}
