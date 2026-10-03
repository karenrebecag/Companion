import Foundation

// Ported from Space UI's thinking orb (MIT, see NOTICE.md): the helpers its
// renderers share. Plain Doubles so the scenes stay testable without a view.

nonisolated package enum OrbMath {
    package static func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

    package static func fract(_ x: Double) -> Double { x - x.rounded(.down) }

    package static func clamp(_ x: Double) -> Double { x < 0 ? 0 : (x > 1 ? 1 : x) }

    package static func smoothstep(_ x: Double) -> Double { x * x * (3 - 2 * x) }

    package static func hash(_ x: Double, _ y: Double) -> Double {
        fract(sin(x * 12.9898 + y * 78.233) * 43758.5453)
    }

    package static func valueNoise2D(_ x: Double, _ y: Double) -> Double {
        let xi = x.rounded(.down), yi = y.rounded(.down)
        let xf = smoothstep(x - xi), yf = smoothstep(y - yi)
        let bl = hash(xi, yi), br = hash(xi + 1, yi)
        let tl = hash(xi, yi + 1), tr = hash(xi + 1, yi + 1)
        return bl + (br - bl) * xf + (tl - bl) * yf + (bl - br - tl + tr) * xf * yf
    }

    /// Even points on a sphere by the golden spiral.
    package static func fibonacciSphere(_ i: Int, _ n: Int) -> (Double, Double, Double) {
        let phi = Double.pi * (3 - 5.0.squareRoot())
        let y = 1 - 2 * ((Double(i) + 0.5) / Double(n))
        let radius = max(0, 1 - y * y).squareRoot()
        let theta = Double(i) * phi
        return (radius * cos(theta), y, radius * sin(theta))
    }

    package static func angleDelta(_ a: Double, _ b: Double) -> Double {
        atan2(sin(a - b), cos(a - b))
    }

    package static func responsiveScale(_ px: Double, _ power: Double) -> Double {
        pow(px / 300, power)
    }
}

/// Spin about Y then tilt about X, projected orthographically to the canvas.
nonisolated package struct OrbRotation {
    let sinX: Double, cosX: Double, sinY: Double, cosY: Double
    let cx: Double, cy: Double, scale: Double

    package init(rotY: Double, rotX: Double, cx: Double, cy: Double, scale: Double) {
        sinX = sin(rotX); cosX = cos(rotX); sinY = sin(rotY); cosY = cos(rotY)
        self.cx = cx; self.cy = cy; self.scale = scale
    }

    package func project(_ x: Double, _ y: Double, _ z: Double) -> (x: Double, y: Double, z: Double) {
        let xRotY = x * cosY + z * sinY
        let zRotY = -x * sinY + z * cosY
        let yRotX = y * cosX - zRotY * sinX
        let zRotX = y * sinX + zRotY * cosX
        return (cx + xRotY * scale, cy - yRotX * scale, zRotX)
    }
}
