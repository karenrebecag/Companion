import Foundation
import SwiftUI

// Arc's morph-loader (uiarc.dev, Pro), drawn on its 24-unit grid. Every
// shape is the same four strokes in a new pose, so a status change morphs
// one shape into the next instead of swapping icons.

package enum MorphLoaderStatus: Equatable, Sendable { case loading, success, error }

package enum MorphLoaderShape: CaseIterable, Equatable, Sendable {
    case dots, ring, success, error

    package enum Variant: Equatable, Sendable { case dots, ring }

    package init(status: MorphLoaderStatus, variant: Variant) {
        switch status {
        case .loading: self = variant == .dots ? .dots : .ring
        case .success: self = .success
        case .error: self = .error
        }
    }

    var settles: Bool { self == .success || self == .error }
}

/// One stroke: a center, a chord length, a direction in degrees, a bend
/// (1 / radius, 0 for straight), a width and an opacity.
package struct MorphStrokePose: Equatable, Sendable {
    package var cx: CGFloat
    package var cy: CGFloat
    package var length: CGFloat
    package var angle: CGFloat
    package var bend: CGFloat
    package var width: CGFloat
    package var opacity: CGFloat

    var values: [CGFloat] { [cx, cy, length, angle, bend, width, opacity] }

    init(values v: ArraySlice<CGFloat>) {
        let i = v.startIndex
        self.init(cx: v[i], cy: v[i + 1], length: v[i + 2], angle: v[i + 3], bend: v[i + 4],
                  width: v[i + 5], opacity: v[i + 6])
    }

    init(cx: CGFloat, cy: CGFloat, length: CGFloat, angle: CGFloat, bend: CGFloat, width: CGFloat, opacity: CGFloat) {
        self.cx = cx
        self.cy = cy
        self.length = length
        self.angle = angle
        self.bend = bend
        self.width = width
        self.opacity = opacity
    }
}

/// What the idle loop adds to a stroke on top of its pose.
package struct MorphStrokeOffset: Equatable, Sendable {
    package var dy: CGFloat = 0
    package var length: CGFloat = 0
    package var width: CGFloat = 0
    package static let zero = MorphStrokeOffset()
}

package enum MorphLoaderGeometry {
    package static let grid: CGFloat = 24
    package static let stroke: CGFloat = 2.5
    /// The ring turns this many degrees a second while loading.
    package static let ringSpeed: Double = 330
    /// The finished mark pops once: up to 1.14 in 0.15 s, back in 0.27 s.
    package static let popScale: CGFloat = 1.14
    package static let popRise: Double = 0.15
    package static let popFall: Double = 0.27
    /// Arc's stroke springs (0.46 s / bounce 0.12 to gather, 0.52 s / 0.28 to
    /// draw the mark, 0.6 s / 0.1 to turn upright) as response and damping.
    package static let gather = MotionSpring(response: 0.46, damping: 0.88)
    package static let settle = MotionSpring(response: 0.52, damping: 0.72)
    package static let turn = MotionSpring(response: 0.6, damping: 0.9)

    package static func poses(_ shape: MorphLoaderShape, stroke w: CGFloat = stroke) -> [MorphStrokePose] {
        switch shape {
        case .dots:
            var hidden = dot(12, 12, 0)
            hidden.opacity = 0
            return [dot(5, 12, 4), dot(12, 12, 4), dot(19, 12, 4), hidden]
        case .ring:
            return [0, 90, 180, 270].map { arc(radius: 8.5, center: $0 - 90, span: 64, width: w) }
        case .success:
            return [line(5, 12.5, 7.6, 15.1, w), line(7.6, 15.1, 10.2, 17.7, w),
                    line(10.2, 17.7, 14.6, 12.6, w), line(14.6, 12.6, 19, 7.5, w)]
        case .error:
            return [line(6.5, 6.5, 12, 12, w), line(12, 12, 17.5, 17.5, w),
                    line(17.5, 6.5, 12, 12, w), line(12, 12, 6.5, 17.5, w)]
        }
    }

    /// A stroke's two end points on the grid.
    package static func ends(_ p: MorphStrokePose) -> (CGPoint, CGPoint) {
        let half = max(p.length, 0.01) / 2
        let a = p.angle * .pi / 180
        let dx = cos(a) * half, dy = sin(a) * half
        return (CGPoint(x: p.cx - dx, y: p.cy - dy), CGPoint(x: p.cx + dx, y: p.cy + dy))
    }

    /// The stroke as a path: a line when straight, else the minor arc through
    /// the same end points, sampled so any bend draws without a sweep flag.
    package static func path(_ p: MorphStrokePose, scale: CGFloat) -> Path {
        let (a, b) = ends(p)
        var path = Path()
        guard abs(p.bend) >= 0.004 else {
            path.move(to: CGPoint(x: a.x * scale, y: a.y * scale))
            path.addLine(to: CGPoint(x: b.x * scale, y: b.y * scale))
            return path
        }
        let r = 1 / abs(p.bend)
        let half = max(p.length, 0.01) / 2
        let rise = (max(r * r - half * half, 0)).squareRoot()
        let normal = (p.angle + (p.bend > 0 ? 90 : -90)) * .pi / 180
        let center = CGPoint(x: p.cx + cos(normal) * rise, y: p.cy + sin(normal) * rise)
        let start = atan2(a.y - center.y, a.x - center.x)
        var sweep = atan2(b.y - center.y, b.x - center.x) - start
        while sweep > .pi { sweep -= 2 * .pi }
        while sweep < -.pi { sweep += 2 * .pi }
        let segments = 12
        for i in 0...segments {
            let t = start + sweep * CGFloat(i) / CGFloat(segments)
            let point = CGPoint(x: (center.x + cos(t) * r) * scale, y: (center.y + sin(t) * r) * scale)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    /// The shortest turn to a new direction; straight strokes may also flip by 180.
    package static func nearestAngle(from: CGFloat, to: CGFloat, symmetric: Bool) -> CGFloat {
        let period: CGFloat = symmetric ? 180 : 360
        return to + ((from - to) / period).rounded() * period
    }

    /// The finished mark carries on forward to the next full revolution, never back.
    package static func uprightAngle(after angle: Double) -> Double {
        (max(0, angle - 1) / 360).rounded(.up) * 360
    }

    package static func ringDegrees(elapsed: TimeInterval) -> Double {
        max(0, elapsed) * ringSpeed
    }

    /// The idle loop: dots bounce in a wave, the ring's arcs breathe.
    package static func loopOffsets(_ shape: MorphLoaderShape, t: TimeInterval) -> [MorphStrokeOffset] {
        var offsets = Array(repeating: MorphStrokeOffset.zero, count: 4)
        switch shape {
        case .dots:
            for i in 0..<3 {
                let phase = max(0, sin(t / 0.9 * 2 * .pi - Double(i) * 0.8))
                offsets[i] = MorphStrokeOffset(dy: -3.2 * phase, length: 0, width: 0.6 * phase)
            }
        case .ring:
            let breathe = 0.5 + 0.5 * sin(t * 2 * .pi / 1.4)
            for i in 0..<4 { offsets[i] = MorphStrokeOffset(dy: 0, length: -3.2 * breathe, width: 0) }
        case .success, .error:
            break
        }
        return offsets
    }

    private static func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ w: CGFloat) -> MorphStrokePose {
        MorphStrokePose(cx: (x1 + x2) / 2, cy: (y1 + y2) / 2, length: hypot(x2 - x1, y2 - y1),
                        angle: atan2(y2 - y1, x2 - x1) * 180 / .pi, bend: 0, width: w, opacity: 1)
    }

    private static func arc(radius: CGFloat, center: CGFloat, span: CGFloat, width: CGFloat) -> MorphStrokePose {
        let half = span / 2 * .pi / 180, mid = center * .pi / 180
        return MorphStrokePose(cx: 12 + radius * cos(half) * cos(mid), cy: 12 + radius * cos(half) * sin(mid),
                               length: 2 * radius * sin(half), angle: center + 90, bend: 1 / radius,
                               width: width, opacity: 1)
    }

    private static func dot(_ x: CGFloat, _ y: CGFloat, _ size: CGFloat) -> MorphStrokePose {
        MorphStrokePose(cx: x, cy: y, length: 0.01, angle: 0, bend: 0, width: size, opacity: 1)
    }
}

/// All four poses as one vector, so SwiftUI springs every value at once and
/// an interruption keeps each value's velocity.
package struct MorphLoaderPoses: VectorArithmetic, Sendable {
    private static let width = 28
    package var values: [CGFloat]

    package init(_ poses: [MorphStrokePose]) { values = poses.flatMap(\.values) }
    private init(values: [CGFloat]) { self.values = values }

    package var poses: [MorphStrokePose] {
        let full = values.count == Self.width ? values : Array(repeating: 0, count: Self.width)
        return stride(from: 0, to: Self.width, by: 7).map { MorphStrokePose(values: full[$0..<$0 + 7]) }
    }

    package static var zero: MorphLoaderPoses { MorphLoaderPoses(values: []) }

    package static func + (lhs: MorphLoaderPoses, rhs: MorphLoaderPoses) -> MorphLoaderPoses {
        MorphLoaderPoses(values: combine(lhs.values, rhs.values, +))
    }

    package static func - (lhs: MorphLoaderPoses, rhs: MorphLoaderPoses) -> MorphLoaderPoses {
        MorphLoaderPoses(values: combine(lhs.values, rhs.values, -))
    }

    package mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }

    package var magnitudeSquared: Double { values.reduce(0) { $0 + Double($1 * $1) } }

    package static func == (lhs: MorphLoaderPoses, rhs: MorphLoaderPoses) -> Bool {
        combine(lhs.values, rhs.values, -).allSatisfy { $0 == 0 }
    }

    /// The empty vector is zero at any length, so `zero` needs no size.
    private static func combine(_ a: [CGFloat], _ b: [CGFloat], _ op: (CGFloat, CGFloat) -> CGFloat) -> [CGFloat] {
        let n = max(a.count, b.count)
        return (0..<n).map { op($0 < a.count ? a[$0] : 0, $0 < b.count ? b[$0] : 0) }
    }
}
