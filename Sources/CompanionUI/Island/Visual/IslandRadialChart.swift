import CompanionCore
import SwiftUI

/// Radar (one polygon per series over shared axes), polar area (one wedge
/// per label, its radius the value) and the donut ring. Geometry comes from
/// RadialGeometry and DonutLayout; this file only strokes it.
struct IslandRadialChart: View {
    let block: ChartBlock
    var palette: [String: Int] = [:]

    var body: some View {
        if block.kind == .donut {
            IslandDonutRing(block: block, palette: palette)
        } else {
            axes
        }
    }

    private var axes: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = max(min(size.width / 2 - IslandVisualMetrics.radialLabelWidth - Space.x2,
                                 size.height / 2 - IslandVisualMetrics.radialLabelInset), Space.none)
            let maximum = IslandChartData.maximum(block)
            ZStack {
                rings(center: center, radius: radius)
                if block.kind == .radar {
                    spokes(center: center, radius: radius)
                    ForEach(Array(block.series.enumerated()), id: \.offset) { s, serie in
                        polygon(serie.values, maximum: maximum, center: center, radius: radius,
                                color: IslandChartInk.color(at: s))
                    }
                } else {
                    wedges(maximum: maximum, center: center, radius: radius)
                }
                labels(center: center, radius: radius)
            }
        }
    }

    private func rings(center: CGPoint, radius: CGFloat) -> some View {
        ForEach(Array(RadialGeometry.ringRadii(count: IslandVisualMetrics.radarRings, radius: radius).enumerated()),
                id: \.offset) { _, ring in
            Path { $0.addEllipse(in: CGRect(x: center.x - ring, y: center.y - ring,
                                            width: ring * 2, height: ring * 2)) }
                .stroke(IslandChartInk.grid, lineWidth: Stroke.hairline)
        }
    }

    private func spokes(center: CGPoint, radius: CGFloat) -> some View {
        Path { path in
            for index in block.labels.indices {
                let theta = RadialGeometry.angle(index: index, count: block.labels.count)
                path.move(to: center)
                path.addLine(to: CGPoint(x: center.x + radius * CGFloat(cos(theta)),
                                         y: center.y + radius * CGFloat(sin(theta))))
            }
        }
        .stroke(IslandChartInk.grid, lineWidth: Stroke.hairline)
    }

    private func polygon(_ values: [Double], maximum: Double, center: CGPoint, radius: CGFloat,
                         color: Color) -> some View {
        let points = RadialGeometry.radarVertices(values: values, maximum: maximum, center: center, radius: radius)
        let shape = Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            points.dropFirst().forEach { path.addLine(to: $0) }
            path.closeSubpath()
        }
        return ZStack {
            shape.fill(color.opacity(IslandVisualMetrics.areaAlpha))
            shape.stroke(color, lineWidth: IslandVisualMetrics.lineWidth)
        }
    }

    private func wedges(maximum: Double, center: CGPoint, radius: CGFloat) -> some View {
        let values = block.series.first?.values ?? []
        let reaches = RadialGeometry.polarRadii(values: values, maximum: maximum, radius: radius)
        return ForEach(Array(reaches.enumerated()), id: \.offset) { index, reach in
            let start = RadialGeometry.angle(index: index, count: reaches.count)
            let end = RadialGeometry.angle(index: index + 1, count: reaches.count)
            let shape = Path { path in
                path.move(to: center)
                path.addArc(center: center, radius: reach, startAngle: .radians(start),
                            endAngle: .radians(end), clockwise: false)
                path.closeSubpath()
            }
            ZStack {
                shape.fill(IslandChartInk.color(at: index).opacity(IslandVisualMetrics.wedgeAlpha))
                shape.stroke(IslandChartInk.color(at: index), lineWidth: Stroke.thin)
            }
        }
    }

    /// Axis names sit just outside the outer ring, pushed sideways by their
    /// own half width so a name on the right starts at the ring, not on it.
    private func labels(center: CGPoint, radius: CGFloat) -> some View {
        let count = block.labels.count
        let half = IslandVisualMetrics.radialLabelWidth / 2
        return ForEach(Array(block.labels.enumerated()), id: \.offset) { index, label in
            let theta = RadialGeometry.angle(index: index, count: count)
                + (block.kind == .polar ? .pi / Double(max(count, 1)) : 0)
            let cosine = CGFloat(cos(theta))
            let side: CGFloat = cosine > 0.3 ? 1 : (cosine < -0.3 ? -1 : 0)
            Text(label)
                .font(Fonts.geist(IslandVisualMetrics.axisSize))
                .foregroundStyle(IslandChartInk.label)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: IslandVisualMetrics.radialLabelWidth,
                       alignment: side > 0 ? .leading : (side < 0 ? .trailing : .center))
                .position(x: center.x + (radius + Space.x2) * cosine + side * half,
                          y: center.y + (radius + Space.x3) * CGFloat(sin(theta)))
        }
    }
}
