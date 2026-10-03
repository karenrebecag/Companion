import Foundation

// The second half of the Space UI renderers (MIT): the linked graph, the
// braid, the ribbon and the morphing outline.

nonisolated extension ThinkingOrbScene {
    // MARK: Web (connecting)

    static func web(_ size: Double, _ time: Double, _ o: OrbOptions) -> OrbPass {
        let c = size / 2
        let radius = c * 0.8 * (o["spread"] ?? 1)
        let rot = OrbRotation(rotY: time * 0.12, rotX: 0.32, cx: c, cy: c, scale: radius)
        let scale = OrbMath.responsiveScale(size, o["rsPow"] ?? 0.6)
        let count = Int(o["nodeN"] ?? 30)
        let threshold = o["thr"] ?? 0.72
        let nodeR = o["nodeR"] ?? 1.4
        let nodeRDepth = o["nodeRDepth"] ?? 1.8
        var nodes: [(Double, Double, Double)] = []
        for i in 0..<count {
            let fi = Double(i)
            let b = OrbMath.fibonacciSphere(i, count)
            let nx = b.0 + 0.3 * (OrbMath.valueNoise2D(fi * 0.31 + 9, time * 0.24) - 0.5) * 2
            let ny = b.1 + 0.3 * (OrbMath.valueNoise2D(fi * 0.53 + 27, time * 0.21) - 0.5) * 2
            let nz = b.2 + 0.3 * (OrbMath.valueNoise2D(fi * 0.77 + 55, time * 0.27) - 0.5) * 2
            let len = (nx * nx + ny * ny + nz * nz).squareRoot()
            nodes.append((nx / len, ny / len, nz / len))
        }
        var lines: [OrbLine] = []
        var dots: [OrbDot] = []

        for i in 0..<count {
            for j in (i + 1)..<max(i + 1, count) {
                let dx = nodes[i].0 - nodes[j].0, dy = nodes[i].1 - nodes[j].1, dz = nodes[i].2 - nodes[j].2
                let dist = (dx * dx + dy * dy + dz * dz).squareRoot()
                guard dist < threshold else { continue }
                let p1 = rot.project(nodes[i].0, nodes[i].1, nodes[i].2)
                let p2 = rot.project(nodes[j].0, nodes[j].1, nodes[j].2)
                let avgDepth = ((p1.z + p2.z) / 2 + 1) / 2
                lines.append(OrbLine(x1: p1.x, y1: p1.y, x2: p2.x, y2: p2.y, white: 0.42,
                                     a: (1 - dist / threshold) * (0.3 + 0.55 * avgDepth),
                                     w: max(0.6, (o["lineW"] ?? 0.8) * scale)))
            }
        }
        for i in 0..<count {
            let p = rot.project(nodes[i].0, nodes[i].1, nodes[i].2)
            let depth = (p.z + 1) / 2
            let pulse = 1 + 0.25 * sin(time * 1.4 + Double(i) * 2.7)
            dots.append(OrbDot(x: p.x, y: p.y, z: p.z, r: (nodeR + nodeRDepth * depth) * pulse * scale,
                               white: 0.55 - 0.45 * depth))
        }
        for i in 0..<Int(o["signals"] ?? 5) {
            let fi = Double(i)
            let cycle = (time * 0.55 + fi * 7.31).rounded(.down)
            let from = Int(OrbMath.hash(cycle, fi * 3.1 + 1.7) * Double(count))
            let to = Int(OrbMath.hash(cycle, fi * 5.7 + 4.2) * Double(count))
            guard from != to, from < count, to < count else { continue }
            let t = OrbMath.fract(time * 0.55 + fi * 7.31)
            let sx = OrbMath.lerp(nodes[from].0, nodes[to].0, t)
            let sy = OrbMath.lerp(nodes[from].1, nodes[to].1, t)
            let sz = OrbMath.lerp(nodes[from].2, nodes[to].2, t)
            let sLen = max(1e-6, (sx * sx + sy * sy + sz * sz).squareRoot())
            let p = rot.project(sx / sLen, sy / sLen, sz / sLen)
            let depth = (p.z + 1) / 2
            dots.append(OrbDot(x: p.x, y: p.y, z: p.z, r: (nodeR * 1.5 + nodeRDepth * depth) * scale,
                               white: 0.05, a: 0.5 + 0.5 * depth))
        }
        return finish(dots, lines, minRadius: o["rMin"] ?? 0.3)
    }

    // MARK: Braid (weaving)

    private static func ghostSphere(_ count: Int, _ radius: Double, _ rot: OrbRotation, _ scale: Double) -> [OrbDot] {
        (0..<count).map { i in
            let p = OrbMath.fibonacciSphere(i, count)
            let q = rot.project(p.0 * radius, p.1 * radius, p.2 * radius)
            let depth = (q.z / radius + 1) / 2
            return OrbDot(x: q.x, y: q.y, z: q.z, r: 0.8 * scale, white: 0.78, a: 0.1 + 0.22 * depth)
        }
    }

    static func braid(_ size: Double, _ time: Double, _ o: OrbOptions) -> OrbPass {
        let c = size / 2
        let radius = c * 0.76
        let rot = OrbRotation(rotY: time * 0.4, rotX: 0.3, cx: c, cy: c, scale: 1)
        let scale = OrbMath.responsiveScale(size, o["rsPow"] ?? 0.6)
        var dots = ghostSphere(Int(o["ghostN"] ?? 150), radius, rot, scale)
        let strandCount = Int(o["strandN"] ?? 52)
        let turns = o["turns"] ?? 3

        for s in 0..<3 {
            let phase = Double(s) / 3 * 2 * .pi
            for i in 0..<strandCount {
                let u = (OrbMath.fract(Double(i) / Double(strandCount) + time * 0.045) * 2 - 1) * 0.96
                let radAtU = max(0, 1 - u * u).squareRoot()
                let fade = min(1, (1 - abs(u)) / 0.1)
                let angle = u * .pi * turns + phase
                let rMod = 1 + 0.075 * sin(u * .pi * turns * 2 + phase * 2 + time * 0.8)
                let current = radAtU * radius * rMod
                let p = rot.project(cos(angle) * current, u * radius * rMod, sin(angle) * current)
                let depth = (p.z / radius + 1) / 2
                dots.append(OrbDot(x: p.x, y: p.y, z: p.z,
                                   r: ((o["rBase"] ?? 1.2) + (o["rDepth"] ?? 1.8) * depth) * scale,
                                   white: 0.55 - 0.45 * depth, a: fade * (0.45 + 0.55 * depth)))
            }
        }
        return finish(dots, [], minRadius: o["rMin"] ?? 0.3)
    }

    // MARK: Ribbon and ring (composing, breathing)

    static func ribbonOrRing(_ size: Double, _ time: Double, _ o: OrbOptions) -> OrbPass {
        let c = size / 2
        let radius = c * 0.78
        let spin = o["spin"] ?? 1
        let rot = OrbRotation(rotY: time * 0.1 * spin, rotX: 0.3, cx: c, cy: c, scale: 1)
        let scale = OrbMath.responsiveScale(size, o["rsPow"] ?? 0.6)
        var dots = ghostSphere(Int(o["ghostN"] ?? 150), radius, rot, scale)
        let faceOn = (o["faceOn"] ?? 0) != 0
        let wobMul = o["wobMul"] ?? 1

        let rotAngle = time * 0.24 * spin
        let tilt = faceOn ? -0.3 : 0.55 + 0.3 * sin(time * 0.18) * spin
        let cosR = cos(rotAngle), sinR = sin(rotAngle)
        let tx = -sinR * sin(tilt), ty = cos(tilt), tz = cosR * sin(tilt)
        let nx = -sinR * ty, ny = sinR * tx - cosR * tz, nz = cosR * ty
        let effectiveRadius = faceOn ? radius / (1 + 0.85 * 0.23 * wobMul) : radius
        let segs = Int(o["segs"] ?? 88)
        let lanes = max(1, Int(((o["lanes"] ?? 5) * (o["bandMul"] ?? 1)).rounded()))
        let mid = Double(lanes - 1) / 2

        for lane in 0..<lanes {
            let laneOffset = (Double(lane) - mid) * 0.075
            let edge = abs(Double(lane) - mid) / max(1, mid)
            for seg in 0..<segs {
                let a = Double(seg) / Double(segs) * 2 * .pi
                let ripple = (0.16 * sin(a * 3 - time * 1.7 + Double(lane) * 0.22) + 0.07 * sin(a * 5 + time * 1.1)) * wobMul
                let radial = faceOn ? 1 + ripple : 1
                let normal = faceOn ? laneOffset : laneOffset + ripple
                let vx = cosR * cos(a) + tx * sin(a) + nx * normal
                let vy = ty * sin(a) + ny * normal
                let vz = sinR * cos(a) + tz * sin(a) + nz * normal
                let len = (vx * vx + vy * vy + vz * vz).squareRoot()
                let rs = effectiveRadius * radial
                let p = rot.project(vx / len * rs, vy / len * rs, vz / len * rs)
                let depth = (p.z / radius + 1) / 2
                dots.append(OrbDot(
                    x: p.x, y: p.y, z: p.z,
                    r: ((o["rBase"] ?? 1.1) + (o["rDepth"] ?? 1.7) * depth) * (1 - 0.25 * edge) * scale,
                    white: 0.52 - 0.44 * depth + 0.18 * edge, a: 0.4 + 0.6 * depth))
            }
        }
        return finish(dots, [], minRadius: o["rMin"] ?? 0.3)
    }

    // MARK: Morph (shaping)

    private static let polygons: [[(Double, Double)]] = [
        [],
        [(0, -0.26), (0.24, 0.16), (-0.24, 0.16)],
        [(0, -0.2), (0.2, -0.2), (0.2, 0.2), (-0.2, 0.2), (-0.2, -0.2)],
    ]
    private static let samples = 160
    private static let holdTime = 1.4
    private static let transTime = 0.9

    private static func resample(_ poly: [(Double, Double)], _ n: Int) -> [(Double, Double)] {
        let count = poly.count
        let lengths = (0..<count).map { i -> Double in
            let a = poly[i], b = poly[(i + 1) % count]
            return hypot(b.0 - a.0, b.1 - a.1)
        }
        let total = lengths.reduce(0, +)
        return (0..<n).map { i in
            var target = Double(i) / Double(n) * total
            var seg = 0
            while target > lengths[seg], seg < count - 1 { target -= lengths[seg]; seg += 1 }
            let a = poly[seg], b = poly[(seg + 1) % count]
            let t = lengths[seg] > 0 ? min(1, target / lengths[seg]) : 0
            return (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t)
        }
    }

    private static func outline(_ shape: Int) -> [(Double, Double)] {
        let poly = polygons[shape]
        if poly.isEmpty {
            return (0..<samples).map { i in
                let a = -Double.pi / 2 + Double(i) / Double(samples) * 2 * .pi
                return (cos(a) * 0.24, sin(a) * 0.24)
            }
        }
        return resample(poly, samples)
    }

    static func morph(_ size: Double, _ time: Double, _ o: OrbOptions) -> OrbPass {
        let shapeCycle = 2.3
        let cycleTime = time.truncatingRemainder(dividingBy: shapeCycle * 3)
        let current = Int(cycleTime / shapeCycle)
        let shapeTime = cycleTime - Double(current) * shapeCycle
        let progress = shapeTime > holdTime ? OrbMath.smoothstep((shapeTime - holdTime) / transTime) : 0
        let spread = o["spread"] ?? 1
        let s1 = outline(current), s2 = outline((current + 1) % 3)
        let blended = (0..<samples).map { i in
            ((s1[i].0 + (s2[i].0 - s1[i].0) * progress) * spread,
             (s1[i].1 + (s2[i].1 - s1[i].1) * progress) * spread)
        }
        let lengths = (0..<samples).map { i -> Double in
            let a = blended[i], b = blended[(i + 1) % samples]
            return hypot(b.0 - a.0, b.1 - a.1)
        }
        let total = lengths.reduce(0, +)
        let dotCount = max(6, Int((34 * (o["iconD"] ?? 1)).rounded()))
        let dotRadius = (o["rDot"] ?? 0.021) * 1.35 * spread
        let pulse = 1 + 0.02 * sin(shapeTime * 3.1)
        let center = size / 2
        var dots: [OrbDot] = []
        var seg = 0
        var accumulated = 0.0

        for i in 0..<dotCount {
            let target = Double(i) / Double(dotCount) * total
            while accumulated + lengths[seg] < target, seg < samples - 1 { accumulated += lengths[seg]; seg += 1 }
            let a = blended[seg], b = blended[(seg + 1) % samples]
            let t = lengths[seg] > 0 ? min(1, (target - accumulated) / lengths[seg]) : 0
            let px = (a.0 + (b.0 - a.0) * t) * pulse
            let py = (a.1 + (b.1 - a.1) * t) * pulse
            dots.append(OrbDot(x: center + px * size, y: center + py * size, z: 0,
                               r: max(0.35, dotRadius * size), white: 0.1))
        }
        return finish(dots, [], minRadius: o["rMin"] ?? 0.25)
    }
}
