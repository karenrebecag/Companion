import Foundation

/// The printable palette. The same hexes as the UI's `Palette` (a test
/// compares them), kept here because Core cannot see the UI target.
// HACK: a hand-kept mirror guarded by a parity test. Generate both from one
// token file when the palette grows past these few colors.
package enum DocumentTheme {
    package static let ink = "1C1C1E"
    package static let muted = "6C6C70"
    package static let border = "E5E5EA"
    package static let surface = "F9F9F9"
    package static let success = "34C759"
    package static let warning = "FF9500"
    package static let danger = "FF3B30"
    package static let link = "007AFF"
    /// Series colours, in order; the first is the ink, as on the cards.
    package static let series = ["1C1C1E", "007AFF", "34C759", "FF9500", "AF52DE", "FF3B30", "5AC8FA", "8E8E93"]
}

/// A chart as inline SVG for the PDF (spec 20 D3): no script, no remote
/// reference, and the same data the card draws. Every coordinate is finite.
package enum ChartSVG {
    static let width = 640.0
    static let height = 280.0
    static let pad = (left: 48.0, right: 16.0, top: 16.0, bottom: 36.0)

    package static func render(_ block: ChartBlock) -> String {
        let body: String
        switch block.kind {
        case .pie, .donut: body = pie(block)
        default: body = cartesian(block)
        }
        return "<svg viewBox=\"0 0 \(n(width)) \(n(height))\" "
            + "width=\"100%\" role=\"img\">" + body + legend(block) + "</svg>"
    }

    private static func cartesian(_ block: ChartBlock) -> String {
        let values = block.series.flatMap(\.values)
        let low = min(values.min() ?? 0, 0)
        let high = max(values.max() ?? 0, 0)
        let span = high - low == 0 ? 1 : high - low
        let plotW = width - pad.left - pad.right
        let plotH = height - pad.top - pad.bottom
        let count = Double(max(block.labels.count, 1))
        let step = plotW / count
        func y(_ v: Double) -> Double { pad.top + plotH * (1 - (v - low) / span) }
        func x(_ i: Int) -> Double { pad.left + step * (Double(i) + 0.5) }
        var out = axis(zero: y(0), plotW: plotW)
        out += "<text x=\"\(n(pad.left - 6))\" y=\"\(n(y(high) + 4))\" text-anchor=\"end\" class=\"t\">"
            + DocumentHTML.escape(DataCells.number(high)) + "</text>"
        let every = max(1, block.labels.count / 12)
        for (i, label) in block.labels.enumerated() where i % every == 0 {
            out += "<text x=\"\(n(x(i)))\" y=\"\(n(height - pad.bottom + 16))\" text-anchor=\"middle\" class=\"t\">"
                + DocumentHTML.escape(String(label.prefix(14))) + "</text>"
        }
        let seriesCount = Double(block.series.count)
        for (s, serie) in block.series.enumerated() {
            let color = DocumentTheme.series[s % DocumentTheme.series.count]
            switch block.kind {
            case .line, .area:
                let pts = serie.values.enumerated().map { "\(n(x($0.offset))),\(n(y($0.element)))" }
                if block.kind == .area, let first = pts.first, let last = pts.last {
                    let base = n(y(0))
                    out += "<polygon points=\"\(first.split(separator: ",")[0]),\(base) \(pts.joined(separator: " ")) "
                        + "\(last.split(separator: ",")[0]),\(base)\" fill=\"#\(color)\" fill-opacity=\"0.18\"/>"
                }
                out += "<polyline points=\"\(pts.joined(separator: " "))\" fill=\"none\" stroke=\"#\(color)\" stroke-width=\"2\"/>"
            case .scatter:
                for (i, v) in serie.values.enumerated() {
                    out += "<circle cx=\"\(n(x(i)))\" cy=\"\(n(y(v)))\" r=\"3.5\" fill=\"#\(color)\"/>"
                }
            default:
                let barW = step * 0.7 / seriesCount
                for (i, v) in serie.values.enumerated() {
                    let left = x(i) - step * 0.35 + barW * Double(s)
                    let top = min(y(v), y(0))
                    out += "<rect x=\"\(n(left))\" y=\"\(n(top))\" width=\"\(n(barW))\" "
                        + "height=\"\(n(abs(y(v) - y(0))))\" fill=\"#\(color)\"/>"
                }
            }
        }
        return out
    }

    private static func axis(zero: Double, plotW: Double) -> String {
        "<line x1=\"\(n(pad.left))\" y1=\"\(n(zero))\" x2=\"\(n(pad.left + plotW))\" y2=\"\(n(zero))\" "
            + "stroke=\"#\(DocumentTheme.border)\"/>"
    }

    /// The first series only: a pie has one ring.
    private static func pie(_ block: ChartBlock) -> String {
        let values = block.series.first?.values.map { max($0, 0) } ?? []
        let total = values.reduce(0, +)
        let center = (x: width / 2 - 80, y: height / 2)
        let radius = height / 2 - 20
        guard total > 0 else {
            return "<circle cx=\"\(n(center.x))\" cy=\"\(n(center.y))\" r=\"\(n(radius))\" fill=\"#\(DocumentTheme.border)\"/>"
        }
        var out = ""
        var angle = -Double.pi / 2
        for (i, value) in values.enumerated() where value > 0 {
            let sweep = value / total * 2 * .pi
            let color = DocumentTheme.series[i % DocumentTheme.series.count]
            if sweep >= 2 * .pi - 1e-9 {
                out += "<circle cx=\"\(n(center.x))\" cy=\"\(n(center.y))\" r=\"\(n(radius))\" fill=\"#\(color)\"/>"
            } else {
                let start = (x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                let end = (x: center.x + radius * cos(angle + sweep), y: center.y + radius * sin(angle + sweep))
                out += "<path d=\"M\(n(center.x)),\(n(center.y)) L\(n(start.x)),\(n(start.y)) "
                    + "A\(n(radius)),\(n(radius)) 0 \(sweep > .pi ? 1 : 0) 1 \(n(end.x)),\(n(end.y)) Z\" fill=\"#\(color)\"/>"
            }
            angle += sweep
        }
        if block.kind == .donut {
            out += "<circle cx=\"\(n(center.x))\" cy=\"\(n(center.y))\" r=\"\(n(radius * 0.6))\" fill=\"#ffffff\"/>"
        }
        return out
    }

    private static func legend(_ block: ChartBlock) -> String {
        let names: [String]
        switch block.kind {
        case .pie, .donut: names = block.labels
        default: names = block.series.count > 1 ? block.series.enumerated().map { $0.element.name ?? "\($0.offset + 1)" } : []
        }
        var out = ""
        let x = block.kind == .pie || block.kind == .donut ? width / 2 + 40 : pad.left
        for (i, name) in names.prefix(10).enumerated() {
            let y = block.kind == .pie || block.kind == .donut ? 30 + Double(i) * 20 : height - 6
            let dx = block.kind == .pie || block.kind == .donut ? x : x + Double(i) * 110
            let color = DocumentTheme.series[i % DocumentTheme.series.count]
            out += "<rect x=\"\(n(dx))\" y=\"\(n(y - 9))\" width=\"10\" height=\"10\" fill=\"#\(color)\"/>"
                + "<text x=\"\(n(dx + 16))\" y=\"\(n(y))\" class=\"t\">" + DocumentHTML.escape(String(name.prefix(24))) + "</text>"
        }
        return out
    }

    /// Two decimals, never NaN or inf in the markup.
    static func n(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        return String(format: "%.2f", value)
    }
}
