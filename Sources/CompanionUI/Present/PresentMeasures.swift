import SwiftUI

/// Heights and widths the present blocks share. The island gets less of each:
/// it is a glance, so a chart there keeps its shape and drops its air.
struct PresentMeasures {
    let compact: Bool

    var lineHeight: CGFloat { compact ? 132 : 200 }
    var brushHeight: CGFloat { compact ? 140 : 220 }
    var brushOverview: CGFloat { compact ? 36 : 52 }
    var streamHeight: CGFloat { compact ? 144 : 220 }
    var barHeight: CGFloat { compact ? 120 : 176 }
    var donutSize: CGFloat { compact ? 140 : 192 }
    var treemapHeight: CGFloat { compact ? 180 : 280 }
    var gaugeSize: CGFloat { compact ? 96 : 120 }
    var slopeHeight: CGFloat? { compact ? 150 : nil }
    var codeMaxLines: Int { compact ? 10 : 24 }
    var tileMinWidth: CGFloat { compact ? 180 : 164 }
    var sparklineWidth: CGFloat { compact ? 180 : 164 }

    /// A line chart labels the axis every few points so the dates do not overlap.
    func axisStride(count: Int) -> Int { max(1, count / (compact ? 4 : 6)) }

    /// A point of the file tree must stay readable at a glance.
    static let railDot: CGFloat = 8
    static let noticeIcon: CGFloat = 16
}
