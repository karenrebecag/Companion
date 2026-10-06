import CompanionCore
import SwiftUI

// Wave 16m-5a: the `visual` container and the chart canvas as measured in
// docs/research/incredible-isla-componentes.md (fila gráfica, fila visual).
// Pinned in Island16m5Tests: a value changes here and in the research
// together, or not at all. What the research does not measure is marked.

package enum IslandVisualMetrics {
    /// Padding 14 / 16 / 12, on the ramp: 3.5, 4, 3.
    package static let paddingTop = Space.x3_5
    package static let paddingX = Space.x4
    package static let paddingBottom = Space.x3
    /// Fill 5 %, border 7 %, radius 12: the popup's own ovx fill, line and
    /// interior radius, so the container reads as a sibling of the code well.
    package static let fill = AnswerInk.fill
    package static let border = AnswerInk.line
    package static let radius = AnswerBlockMetrics.innerRadius
    /// The canvas: 240 tall, 264 for the round kinds (their labels ring the
    /// drawing instead of sitting on an axis).
    package static let canvas: CGFloat = 240
    package static let radialCanvas: CGFloat = 264
    /// Not measured: the diagram's loading block, tall enough to hold a small flowchart's place.
    package static let diagramSkeletonHeight: CGFloat = 120
    /// Not measured: the failure alert's warning glyph, one step above the 14 pt body text.
    package static let diagramAlertIcon: CGFloat = 16

    // Not measured: values of this session.
    /// Concentric guides a radar and a polar chart read against.
    package static let radarRings = 4
    /// "Copied" on the tool, the same beat the dictation card uses.
    package static let copiedFor = IslandDictationMetrics.copiedFor
    /// WCAG 1.4.11: a mark that carries data needs 3:1 against its ground.
    package static let minSeriesContrast = 3.0
    package static let lineWidth = Stroke.medium
    package static let areaAlpha = 0.18
    /// The dark seam between two pie slices.
    package static let sectorGap = Stroke.hairline
    /// A polar wedge's fill: the outline carries the colour, the fill only weight.
    package static let wedgeAlpha = 0.35
    /// Room the axis labels of a round chart take out of the canvas.
    package static let radialLabelInset: CGFloat = 28
    package static let axisSize = AnswerBlockMetrics.eyebrowSize
    package static let legendDot: CGFloat = 8
    package static let legendColumn: CGFloat = 110
    /// A round chart's axis label: the widest a name gets before it truncates.
    package static let radialLabelWidth: CGFloat = 64

    /// The width the diagram is laid out at: the popup's 580 less its own
    /// side padding (2 x 22) and the container's (2 x 16). Narrower than that
    /// the container scrolls sideways; the picture is never shrunk.
    package static let diagramWidth = AnswerPopupMetrics.maxWidth
        - 2 * AnswerPopupMetrics.paddingX - 2 * paddingX

    // The donut ring: Arc's free donut-chart (uiarc.dev, donut-chart.tsx),
    // since Incredible defines no donut of its own. Pinned in IslandDonutTests.
    /// Diameter, before the ring scales down to a narrower canvas.
    package static let donutSize: CGFloat = 208
    package static let donutThickness: CGFloat = 24
    /// Room left outside the ring.
    package static let donutMargin: CGFloat = 7
    /// The gap between neighbours, the same pixels from the inner edge to the outer.
    package static let donutGap: CGFloat = 3
    package static let donutCorner: CGFloat = 4
    /// The smallest inner radius, so a thick ring on a tiny canvas keeps a hole.
    package static let donutMinInner: CGFloat = 8
    /// The centre readout sits this much narrower than the hole.
    package static let donutReadoutInset: CGFloat = 16
    package static let donutValueSize: CGFloat = 24
    /// Parts below this share join "Other", when at least two would.
    package static let donutGroupBelow = 0.04
    /// The most segments drawn, counting "Other".
    package static let donutMaxSegments = 6
    /// The sweep: each trailing edge leaves this long after the first, a step apart.
    package static let donutSweepLead = 0.04
    package static let donutSweepStep = 0.035
    /// Arc's springs are visualDuration + bounce; as SwiftUI numbers the
    /// response is visualDuration x 1.2 and the damping fraction 1 - bounce.
    /// reveal 0.72 s, settle 0.5 s, the count 0.4 s, none of them bounce.
    package static let donutReveal = MotionSpring(response: 0.864, damping: 1)
    package static let donutSettle = MotionSpring(response: 0.6, damping: 1)
    package static let donutCount = MotionSpring(response: 0.48, damping: 1)

    package static func canvasHeight(for kind: ChartBlock.Kind) -> CGFloat {
        switch kind {
        case .pie, .donut, .polar, .radar: radialCanvas
        case .bar, .line, .area, .scatter: canvas
        }
    }
}

/// The series' colours: Arc's dark chart series first, then the system
/// accents for longer charts. The island surface is dark in both
/// appearances, so one palette serves both.
enum IslandChartInk {
    /// Every entry is pinned to 3:1 on the surface by a test.
    static let series: [Swatch] = ArcTone.chartSeries + [Accent.pink, Accent.yellow, Accent.teal, Neutral.n400]

    static func color(at index: Int) -> Color {
        let count = series.count
        return series[((index % count) + count) % count].color
    }

    static var axis: Color { AnswerInk.white(AnswerInk.muted) }
    static var grid: Color { AnswerInk.white(AnswerInk.line) }
    static var label: Color { AnswerInk.white(AnswerInk.secondary) }
}
