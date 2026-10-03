import CompanionCore
import SwiftUI

/// The donut ring decided apart from any view: which parts become segments,
/// where each sits on the ring, which colour each key keeps and the path of
/// one segment. Behaviour ported from Arc's free donut-chart (uiarc.dev);
/// every value is pinned in IslandDonutTests.
enum DonutLayout {
    /// The grouped segment's key. Every real part's key carries the label
    /// prefix, so no label a model writes, "__other" or "other" included,
    /// can land on it and merge two segments into one.
    static let otherKey = "other"

    static func key(_ label: String) -> String { "label:" + label }

    struct Member: Equatable {
        let label: String
        let value: Double
    }

    struct Slice: Equatable {
        let key: String
        let label: String
        let value: Double
        /// The parts folded into "Other", empty for any other segment.
        var members: [Member] = []

        var isOther: Bool { key == DonutLayout.otherKey }
    }

    /// A span of the ring in turns, clockwise from twelve o'clock. While the
    /// sweep runs a trailing edge can sit behind its leading one; that draws
    /// nothing rather than a backwards segment.
    struct Arc: Equatable {
        let start: Double
        let end: Double

        var width: Double { max(end - start, 0) }
    }

    // MARK: - Segments

    /// The block's first series against its labels. The key is the label
    /// VoiceOver already hears, so a repeated or empty label still has one.
    static func slices(_ block: ChartBlock) -> [Slice] {
        guard let serie = block.series.first else { return [] }
        let labels = IslandChartData.uniqueLabels(block.labels)
        return slices(labels: labels, values: Array(serie.values.prefix(labels.count)))
    }

    /// Small parts join one "Other" segment, but only when at least two
    /// would: grouping a single part hides it for nothing.
    static func slices(labels: [String], values: [Double],
                       groupBelow: Double = IslandVisualMetrics.donutGroupBelow,
                       maxSegments: Int = IslandVisualMetrics.donutMaxSegments) -> [Slice] {
        let parts = zip(labels, values).enumerated().compactMap { index, pair -> (Int, Slice)? in
            guard pair.1.isFinite, pair.1 > 0 else { return nil }
            return (index, Slice(key: key(pair.0), label: pair.0, value: pair.1))
        }
        let total = parts.reduce(0) { $0 + $1.1.value }
        guard total > 0 else { return [] }
        // Ties keep data order: a plain sort is not stable in Swift.
        let ranked = parts.sorted { $0.1.value != $1.1.value ? $0.1.value > $1.1.value : $0.0 < $1.0 }
        let kept = Set(ranked.enumerated()
            .filter { rank, part in part.1.value / total >= groupBelow && rank < maxSegments - 1 }
            .map(\.element.0))
        let rest = parts.filter { !kept.contains($0.0) }.map(\.1)
        guard rest.count >= 2 else { return parts.map(\.1) }
        let other = Slice(key: otherKey, label: Localized.string("island.chart.other"),
                          value: rest.reduce(0) { $0 + $1.value },
                          members: rest.map { Member(label: $0.label, value: $0.value) })
        return parts.filter { kept.contains($0.0) }.map(\.1) + [other]
    }

    /// Each slice's span in data order; the last one closes the turn exactly.
    static func arcs(_ slices: [Slice]) -> [String: Arc] {
        let total = slices.reduce(0) { $0 + $1.value }
        guard total > 0 else { return [:] }
        var at = 0.0
        var result: [String: Arc] = [:]
        for (index, slice) in slices.enumerated() {
            let end = index == slices.count - 1 ? 1 : at + slice.value / total
            result[slice.key] = Arc(start: at, end: end)
            at = end
        }
        return result
    }

    /// What stays drawn while a change morphs: the new slices, plus each
    /// leaving one at zero right after the neighbour it used to follow, so
    /// it closes where it sat instead of vanishing.
    static func drawn(previous: [Slice], next: [Slice]) -> [Slice] {
        var result = next
        for (index, item) in previous.enumerated() where !result.contains(where: { $0.key == item.key }) {
            let before = previous[..<index].reversed().first { prior in result.contains { $0.key == prior.key } }
            let at = before.flatMap { prior in result.firstIndex { $0.key == prior.key } }.map { $0 + 1 } ?? 0
            result.insert(Slice(key: item.key, label: item.label, value: 0, members: item.members), at: at)
        }
        return result
    }

    /// Where every drawn segment heads: the new layout, and a leaving one
    /// closed to a point at the end of the segment before it.
    static func targets(drawn: [Slice], next: [Slice]) -> [String: Arc] {
        let goal = arcs(next)
        var result = goal
        for (index, item) in drawn.enumerated() where goal[item.key] == nil {
            let place = drawn[..<index].reversed().compactMap { goal[$0.key] }.first?.end ?? 0
            result[item.key] = Arc(start: place, end: place)
        }
        return result
    }

    /// The first sweep: the trailing edge of segment `index` leaves this long
    /// after the start, each a beat behind the one before.
    static func sweepDelay(index: Int) -> Double {
        IslandVisualMetrics.donutSweepLead + Double(max(index, 0)) * IslandVisualMetrics.donutSweepStep
    }

    // MARK: - Colour

    /// A key keeps its colour across datasets, so a segment reads as the
    /// same thing through every change; a new key takes the lowest colour
    /// none of the shown keys uses, so two visible segments never match.
    /// A key that returns gets its old colour back while it is still free.
    /// "Other" never takes a series colour.
    static func palette(_ previous: [String: Int], keys: [String]) -> [String: Int] {
        let named = keys.filter { $0 != otherKey }
        var result = previous
        var used = Set<Int>()
        var homeless: [String] = []
        for key in named {
            if let index = previous[key], index < seriesColors, !used.contains(index) {
                used.insert(index)
            } else {
                homeless.append(key)
            }
        }
        for key in homeless {
            // HACK: past seven shown keys the colours repeat. The ring caps at six segments, so it cannot today.
            let free = (0 ..< seriesColors).first { !used.contains($0) } ?? 0
            used.insert(free)
            result[key] = free
        }
        return result
    }

    /// Series colours: the palette without its last swatch, which is Other's.
    private static var seriesColors: Int { IslandChartInk.series.count - 1 }

    /// The swatch index into IslandChartInk: "Other" is the palette's quiet
    /// neutral (its last entry) and the series cycle over the rest.
    static func colorIndex(_ key: String, palette: [String: Int]) -> Int {
        let neutral = IslandChartInk.series.count - 1
        guard key != otherKey else { return neutral }
        return (palette[key] ?? 0) % neutral
    }

    /// The empty track shows once the data is all zero AND every drawn arc
    /// has closed: closing arcs morph out first, and the sweep's first
    /// instant (all arcs at zero, data not) never flashes it.
    static func showsTrack(_ arcs: [Arc], finalTotal: Double) -> Bool {
        finalTotal <= 0 && arcs.allSatisfy { $0.width == 0 }
    }

    /// Whether the ring sweeps in and whether it animates a change. A still
    /// render skips the sweep; Reduce Motion skips both.
    static func motionPlan(reduceMotion: Bool, sweeps: Bool) -> (sweep: Bool, animate: Bool) {
        (sweep: sweeps && !reduceMotion, animate: !reduceMotion)
    }

    /// The ring's radii on a canvas `diameter` across: never past Arc's
    /// size, and on a canvas thinner than the ring the hole shrinks with it
    /// instead of ending up outside the ring.
    static func radii(diameter: CGFloat) -> (outer: CGFloat, inner: CGFloat) {
        let size = min(max(diameter, 0), IslandVisualMetrics.donutSize)
        let outer = max(size / 2 - IslandVisualMetrics.donutMargin, 0)
        let inner = max(IslandVisualMetrics.donutMinInner, outer - IslandVisualMetrics.donutThickness)
        return (outer, min(inner, outer))
    }

    // MARK: - Words

    /// Whole percents, and a sliver says "<1%" rather than a misleading 0 %.
    static func shareText(_ share: Double) -> String {
        guard share.isFinite else { return "0%" }
        if share > 0, share < 0.01 { return "<1%" }
        return "\(Int((share * 100).rounded()))%"
    }

    /// The centre number while it counts: a whole target counts in whole
    /// steps, a fractional one in its own decimals (two at most).
    static func readout(_ value: Double, target: Double) -> String {
        let final = ChartBlock.text(target)
        guard value != target else { return final }
        let decimals = final.split(separator: ".").dropFirst().first.map { min($0.count, 2) } ?? 0
        guard decimals > 0 else { return ChartBlock.text(value.rounded()) }
        return String(format: "%.\(decimals)f", value)
    }

    // MARK: - Geometry

    private static let tau = 2 * Double.pi

    /// Screen angle of a turn, twelve o'clock first, clockwise on a y-down canvas.
    private static func angle(_ turn: Double) -> Double { turn * tau - .pi / 2 }

    /// Below a couple of pixels of outer edge a segment fades instead of
    /// drawing a hairline, so a closing segment never pops.
    static func fade(outer: CGFloat, start: Double, end: Double, gap: CGFloat) -> Double {
        let turns = end - start
        guard turns < 1 - 1e-6 else { return 1 }
        guard turns > 0 else { return 0 }
        let radius = Double(outer)
        let breadth = sin(min(turns * .pi, .pi / 2)) * radius - min(Double(gap) / 2, (1 - turns) * .pi * radius)
        return min(max((breadth - 1) / 3, 0), 1)
    }

    /// An annular sector with rounded corners. Its sides run parallel to the
    /// radius half a gap away, so the gap between neighbours is the same
    /// width from the inner edge to the outer; a thin sector narrows to a
    /// wedge and then to nothing. Fill it even-odd: the whole ring is two
    /// circles.
    static func sector(center: CGPoint, outer: CGFloat, inner: CGFloat, start: Double, end: Double,
                       gap: CGFloat, corner: CGFloat) -> Path {
        let turns = end - start
        guard turns > 1e-6, inner >= 0, outer > inner else { return Path() }
        let R = Double(outer)
        let r = Double(inner)
        if turns >= 1 - 1e-6 {
            var ring = Path()
            ring.addEllipse(in: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
            ring.addEllipse(in: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2))
            return ring
        }
        // A lone segment closes its gap as the rest of the ring empties, so
        // it becomes the whole ring without a jump.
        let p = min(Double(gap) / 2, (1 - turns) * tau * R / 2)
        let a0 = angle(start)
        let a1 = angle(end)
        let s = sin(min((a1 - a0) / 2, .pi / 2))
        guard s * R > p + 1e-6 else { return Path() }
        let band = (R - r) / 2
        let roundAll = s >= 0.9999
        let ro = max(0, min(Double(corner), band, roundAll ? .infinity : (s * R - p) / (1 + s)))
        let dO = asin(min(1, (p + ro) / (R - ro)))
        let tO = ((R - ro) * (R - ro) - (p + ro) * (p + ro)).squareRoot()

        let geometry = SectorPen(center: center, offset: p)
        var path = Path()
        path.move(to: geometry.side(tO, a0, 1))
        geometry.corner(&path, radius: ro, at: geometry.at(R - ro, a0 + dO), from: a0 - .pi / 2, to: a0 + dO)
        path.addArc(center: center, radius: outer, startAngle: .radians(a0 + dO), endAngle: .radians(a1 - dO),
                    clockwise: false)
        geometry.corner(&path, radius: ro, at: geometry.at(R - ro, a1 - dO), from: a1 - dO, to: a1 + .pi / 2)
        if s * r > p + 1e-6 || roundAll {
            let ri = max(0, min(Double(corner), band, roundAll ? .infinity : (s * r - p) / (1 - s)))
            let dI = asin(min(1, (p + ri) / (r + ri)))
            let tI = ((r + ri) * (r + ri) - (p + ri) * (p + ri)).squareRoot()
            path.addLine(to: geometry.side(tI, a1, -1))
            geometry.corner(&path, radius: ri, at: geometry.at(r + ri, a1 - dI), from: a1 + .pi / 2, to: a1 - dI + .pi)
            path.addArc(center: center, radius: inner, startAngle: .radians(a1 - dI), endAngle: .radians(a0 + dI),
                        clockwise: true)
            geometry.corner(&path, radius: ri, at: geometry.at(r + ri, a0 + dI), from: a0 + dI + .pi, to: a0 + 1.5 * .pi)
        } else {
            // Too thin for the hole: the two sides meet at a point short of it.
            path.addLine(to: geometry.at(p / s, (a0 + a1) / 2))
        }
        path.closeSubpath()
        return path
    }

    /// Points and corner arcs of one sector, around one centre.
    private struct SectorPen {
        let center: CGPoint
        let offset: Double

        func at(_ radius: Double, _ angle: Double) -> CGPoint {
            CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }

        /// A point on the side of a segment: along the radius at `angle`,
        /// pushed half a gap toward the inside of the segment.
        func side(_ along: Double, _ angle: Double, _ sign: Double) -> CGPoint {
            CGPoint(x: center.x + along * cos(angle) - sign * offset * sin(angle),
                    y: center.y + along * sin(angle) + sign * offset * cos(angle))
        }

        /// A rounded corner: the short way round its own small circle.
        func corner(_ path: inout Path, radius: Double, at hub: CGPoint, from: Double, to: Double) {
            guard radius > 0.01 else { return }
            var delta = (to - from).truncatingRemainder(dividingBy: 2 * .pi)
            if delta > .pi { delta -= 2 * .pi }
            if delta <= -.pi { delta += 2 * .pi }
            path.addArc(center: hub, radius: radius, startAngle: .radians(from), endAngle: .radians(from + delta),
                        clockwise: delta < 0)
        }
    }
}
