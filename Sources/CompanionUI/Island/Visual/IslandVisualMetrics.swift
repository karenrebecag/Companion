import CompanionCore
import SwiftUI

// Wave 16m-5a: the `visual` container and the chart canvas as measured in
// docs/research/incredible-isla-componentes.md (fila gráfica, fila visual).
// Pinned in Island16m5Tests: a value changes here and in the research
// together, or not at all. What the research does not measure is marked.

public enum IslandVisualMetrics {
    /// Padding 14 / 16 / 12, on the ramp: 3.5, 4, 3.
    public static let paddingTop = Space.x3_5
    public static let paddingX = Space.x4
    public static let paddingBottom = Space.x3
    /// Fill 5 %, border 7 %, radius 12: the popup's own ovx fill, line and
    /// interior radius, so the container reads as a sibling of the code well.
    public static let fill = AnswerInk.fill
    public static let border = AnswerInk.line
    public static let radius = AnswerBlockMetrics.innerRadius
    /// The canvas: 240 tall, 264 for the round kinds (their labels ring the
    /// drawing instead of sitting on an axis).
    public static let canvas: CGFloat = 240
    public static let radialCanvas: CGFloat = 264

    // Not measured: values of this session.
    /// Concentric guides a radar and a polar chart read against.
    public static let radarRings = 4
    /// "Copied" on the tool, the same beat the dictation card uses.
    public static let copiedFor = IslandDictationMetrics.copiedFor
    /// WCAG 1.4.11: a mark that carries data needs 3:1 against its ground.
    public static let minSeriesContrast = 3.0
    public static let lineWidth = Stroke.medium
    public static let areaAlpha = 0.18
    public static let donutInner = 0.6
    /// The dark seam between two pie slices.
    public static let sectorGap = Stroke.hairline
    /// A polar wedge's fill: the outline carries the colour, the fill only weight.
    public static let wedgeAlpha = 0.35
    /// Room the axis labels of a round chart take out of the canvas.
    public static let radialLabelInset: CGFloat = 28
    public static let axisSize = AnswerBlockMetrics.eyebrowSize
    public static let legendDot: CGFloat = 8
    public static let legendColumn: CGFloat = 110
    /// A round chart's axis label: the widest a name gets before it truncates.
    public static let radialLabelWidth: CGFloat = 64

    public static func canvasHeight(for kind: ChartBlock.Kind) -> CGFloat {
        switch kind {
        case .pie, .donut, .polar, .radar: radialCanvas
        case .bar, .line, .area, .scatter: canvas
        }
    }
}

/// The series' colours, built from the tokens already on the island: the
/// popup accent first, then the system accents. The island surface is dark
/// in both appearances, so one palette serves both.
enum IslandChartInk {
    /// Every entry is pinned to 3:1 on the surface by a test.
    static let series: [Swatch] = [
        AnswerInk.accent, Palette.signalGreen, Accent.orange, Accent.purple,
        Accent.pink, Accent.yellow, Accent.teal, Neutral.n400,
    ]

    static func color(at index: Int) -> Color {
        let count = series.count
        return series[((index % count) + count) % count].color
    }

    static var axis: Color { AnswerInk.white(AnswerInk.muted) }
    static var grid: Color { AnswerInk.white(AnswerInk.line) }
    static var label: Color { AnswerInk.white(AnswerInk.secondary) }
}
