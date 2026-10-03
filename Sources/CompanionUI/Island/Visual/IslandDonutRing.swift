import CompanionCore
import SwiftUI

/// The donut: Arc's ring (uiarc.dev donut-chart) on the island. DonutMotion
/// says where every edge is at any instant; this view only runs a clock
/// while something moves and paints the frame. The ring and its readout are
/// decorative: the canvas around it carries the spoken summary.
struct IslandDonutRing: View {
    let block: ChartBlock
    /// Key to colour, owned by the visual so the legend reads the same one.
    let palette: [String: Int]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.islandChartSweeps) private var sweeps
    @State private var motion: DonutMotion?
    @State private var animating = false

    private var slices: [DonutLayout.Slice] { DonutLayout.slices(block) }

    var body: some View {
        let shown = motion ?? DonutMotion(slices: slices)
        let colors = DonutLayout.palette(palette, keys: slices.map(\.key))
        GeometryReader { proxy in
            let (outer, inner) = DonutLayout.radii(diameter: min(proxy.size.width, proxy.size.height))
            TimelineView(.animation(paused: !animating)) { context in
                let now = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    Canvas { canvas, size in
                        let frames = shown.arcs(at: now)
                        paint(frames, empty: DonutLayout.showsTrack(frames.map(\.arc), finalTotal: shown.finalTotal),
                              colors: colors, outer: outer, inner: inner,
                              center: CGPoint(x: size.width / 2, y: size.height / 2), into: &canvas)
                    }
                    readout(shown, at: now, width: max(inner * 2 - IslandVisualMetrics.donutReadoutInset, Space.none))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .onAppear {
            guard DonutLayout.motionPlan(reduceMotion: reduceMotion, sweeps: sweeps).sweep, motion == nil else { return }
            start(DonutMotion(slices: slices).sweeping(at: Date.now.timeIntervalSinceReferenceDate))
        }
        .onChange(of: slices) { previous, next in
            let now = Date.now.timeIntervalSinceReferenceDate
            let animate = DonutLayout.motionPlan(reduceMotion: reduceMotion, sweeps: sweeps).animate
            start((motion ?? DonutMotion(slices: previous)).updated(to: next, at: now, reduced: !animate))
        }
        // The clock stops once the last spring rests, so an idle ring costs no frames.
        .task(id: motion) {
            guard let motion, animating else { return }
            let wait = motion.settleTime - Date.now.timeIntervalSinceReferenceDate
            if wait > 0 {
                do { try await Task.sleep(for: .seconds(wait)) } catch { return }
            }
            animating = false
        }
    }

    private func start(_ next: DonutMotion) {
        motion = next
        animating = DonutLayout.motionPlan(reduceMotion: reduceMotion, sweeps: sweeps).animate
    }

    private func paint(_ frames: [DonutMotion.Frame], empty: Bool, colors: [String: Int], outer: CGFloat, inner: CGFloat,
                       center: CGPoint, into canvas: inout GraphicsContext) {
        let gap = IslandVisualMetrics.donutGap
        let corner = min(IslandVisualMetrics.donutCorner, IslandVisualMetrics.donutThickness / 4)
        if empty {
            // Nothing to draw: the empty track says the whole is zero, not that it failed.
            let track = DonutLayout.sector(center: center, outer: outer, inner: inner, start: 0, end: 1,
                                           gap: gap, corner: corner)
            canvas.fill(track, with: .color(IslandChartInk.grid), style: FillStyle(eoFill: true))
            return
        }
        for frame in frames where frame.arc.width > 0 {
            let path = DonutLayout.sector(center: center, outer: outer, inner: inner, start: frame.arc.start,
                                          end: frame.arc.end, gap: gap, corner: corner)
            let fade = DonutLayout.fade(outer: outer, start: frame.arc.start, end: frame.arc.end, gap: gap)
            let color = IslandChartInk.color(at: DonutLayout.colorIndex(frame.slice.key, palette: colors))
            canvas.fill(path, with: .color(color.opacity(fade)), style: FillStyle(eoFill: true))
        }
    }

    /// The total in a fixed cell: tabular digits, so a counting number never
    /// shifts sideways as its digits change.
    private func readout(_ motion: DonutMotion, at now: Double, width: CGFloat) -> some View {
        VStack(spacing: Space.x0_5) {
            Text(Localized.string("island.chart.total"))
                .font(Fonts.geist(IslandVisualMetrics.axisSize))
                .foregroundStyle(IslandChartInk.label)
            Text(DonutLayout.readout(motion.total(at: now), target: motion.finalTotal))
                .font(Fonts.geist(IslandVisualMetrics.donutValueSize).weight(.medium))
                .monospacedDigit()
                .foregroundStyle(AnswerInk.white(AnswerInk.text))
            if let unit = block.unit, !unit.isEmpty {
                Text(unit)
                    .font(Fonts.geist(IslandVisualMetrics.axisSize))
                    .foregroundStyle(IslandChartInk.axis)
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(width: width)
    }
}

extension EnvironmentValues {
    /// A still render (a snapshot, an exported picture) wants the finished
    /// ring, not the first instant of its sweep.
    @Entry var islandChartSweeps = true
}
