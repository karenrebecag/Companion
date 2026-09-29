import Foundation

/// The geometry of the two charts Swift Charts does not have (radar and
/// polar area), as pure functions so a test can pin every vertex before any
/// Path draws it. Every result is finite for any input.
enum RadialGeometry {
    /// Axis `index` of `count`, clockwise, the first at twelve o'clock.
    static func angle(index: Int, count: Int) -> Double {
        -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(max(count, 1))
    }

    static func radarVertices(values: [Double], maximum: Double, center: CGPoint,
                              radius: CGFloat) -> [CGPoint] {
        let radii = polarRadii(values: values, maximum: maximum, radius: radius)
        return radii.enumerated().map { index, reach in
            let theta = angle(index: index, count: values.count)
            return CGPoint(x: center.x + reach * CGFloat(cos(theta)),
                           y: center.y + reach * CGFloat(sin(theta)))
        }
    }

    /// Radius proportional to the value, clamped into the canvas.
    static func polarRadii(values: [Double], maximum: Double, radius: CGFloat) -> [CGFloat] {
        guard maximum > 0 else { return values.map { _ in 0 } }
        return values.map { value in
            let share = min(max(value / maximum, 0), 1)
            return radius * CGFloat(share)
        }
    }

    static func ringRadii(count: Int, radius: CGFloat) -> [CGFloat] {
        guard count > 0 else { return [] }
        return (1 ... count).map { radius * CGFloat($0) / CGFloat(count) }
    }
}
