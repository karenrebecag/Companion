import CompanionCore
import SwiftUI

// A reply's chart, table or figures drawn inside the notch, under its words,
// instead of in a popup apart from it (Karen, 2026-10-06). Every measure is a
// share of what the notch can hold, so a chart never outgrows the shape.

enum IslandFit {
    /// AIThread pads each row by this much on both sides; the package does not export it.
    static let threadInset: CGFloat = 28
    /// The widest a reply's visual gets inside the thread.
    static let threadWidth = IslandGrid.openColumn - threadInset * 2
    /// The widest it gets under the status row, in the grid's content column.
    static let columnWidth = IslandGrid.openColumn - IslandGrid.contentInset
    /// A thread holding a visual takes this share of the notch's column cap.
    static let tallShare: CGFloat = 0.75
    /// A chart's canvas takes at most this share of the room it sits in,
    /// leaving the rest for its header, legend and the words above it.
    static let canvasShare: CGFloat = 0.4
    /// Height over width: radial charts are near-square, cartesian ones wide.
    static let cartesianAspect: CGFloat = 0.5
    static let radialAspect: CGFloat = 0.75

    static var tallRoom: CGFloat { IslandChrome.columnCap * tallShare }

    /// The popup's fixed canvas is the ceiling; the width and the room it
    /// sits in bring it down, never up.
    static func canvasHeight(for kind: ChartBlock.Kind, width: CGFloat, room: CGFloat) -> CGFloat {
        let aspect = radial(kind) ? radialAspect : cartesianAspect
        return min(IslandVisualMetrics.canvasHeight(for: kind), (width * aspect).rounded(),
                   (room * canvasShare).rounded())
    }

    private static func radial(_ kind: ChartBlock.Kind) -> Bool {
        switch kind {
        case .pie, .donut, .polar, .radar: true
        case .bar, .line, .area, .scatter: false
        }
    }
}

/// What the notch draws of a reply beyond its words: its channel card and
/// the cards and diagrams in its text.
struct IslandInlineVisuals: View {
    let card: Card?
    let blocks: [AnswerBlock]
    let width: CGFloat
    let room: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            if let card {
                if case .chart(let chart) = card.payload {
                    chartView(chart)
                } else {
                    CardView(card: card)
                }
            }
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                if case .card(.chart(let chart)) = block {
                    chartView(chart)
                } else {
                    AnswerBlockView(block: block)
                }
            }
        }
        .frame(maxWidth: width, alignment: .leading)
    }

    private func chartView(_ chart: ChartBlock) -> some View {
        IslandChartVisual(block: chart, canvasHeight: IslandFit.canvasHeight(for: chart.kind, width: width, room: room))
    }
}
