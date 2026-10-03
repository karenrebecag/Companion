import CompanionCore
import Foundation

// Ported from Space UI's thinking orb (MIT, see NOTICE.md). Each renderer
// turns (size, time, options) into dots and links; drawing is the view's.

nonisolated package struct OrbDot: Equatable {
    package var x: Double, y: Double, z: Double, r: Double
    /// 0 is ink, 1 is paper; the surface decides which end is bright.
    package var white: Double
    package var a: Double?
}

nonisolated package struct OrbLine: Equatable {
    package var x1: Double, y1: Double, x2: Double, y2: Double
    package var white: Double
    package var a: Double?
    package var w: Double
}

nonisolated package struct OrbPass: Equatable {
    package var dots: [OrbDot]
    package var lines: [OrbLine]
}

nonisolated package enum ThinkingOrbMode: Sendable, CaseIterable {
    case orbits, globe, rubik, wave, web, braid, ribbon, ring, morph

    package var caption: String {
        switch self {
        case .orbits: "Working"
        case .globe: "Searching"
        case .rubik: "Solving"
        case .wave: "Listening"
        case .web: "Connecting"
        case .braid: "Weaving"
        case .ribbon: "Composing"
        case .ring: "Thinking"
        case .morph: "Shaping"
        }
    }

    /// Companion's voice states pick the orb: breathing at rest, linking
    /// while it connects, rippling while it hears, working while it thinks.
    package init(state: TurnState) {
        switch state {
        case .idle: self = .ring
        case .connecting: self = .web
        case .listening: self = .wave
        case .thinking: self = .orbits
        case .speaking: self = .ribbon
        case .error: self = .morph
        }
    }
}

nonisolated package enum ThinkingOrbScene {
    package static func render(
        _ mode: ThinkingOrbMode, size: Double, time: Double, options: OrbOptions
    ) -> OrbPass {
        switch mode {
        case .orbits: orbits(size, time, options)
        case .globe: globe(size, time, options)
        case .rubik: rubik(size, time, options)
        case .wave: wave(size, time, options)
        case .web: web(size, time, options)
        case .braid: braid(size, time, options)
        case .ribbon, .ring: ribbonOrRing(size, time, options)
        case .morph: morph(size, time, options)
        }
    }

    /// Drops what is too faint to see, floors the radius and sorts far to
    /// near so nearer dots paint over farther ones.
    static func finish(_ dots: [OrbDot], _ lines: [OrbLine], minRadius: Double) -> OrbPass {
        var kept = dots.filter { ($0.a ?? 1) >= 0.02 }
        for i in kept.indices { kept[i].r = max(minRadius, kept[i].r) }
        kept.sort { $0.z < $1.z }
        return OrbPass(dots: kept, lines: lines.filter { ($0.a ?? 1) >= 0.02 })
    }

    // MARK: Orbits (working)

    static func orbits(_ size: Double, _ time: Double, _ o: OrbOptions) -> OrbPass {
        let c = size / 2
        let radius = c * 0.82
        let rot = OrbRotation(rotY: time * 0.12, rotX: 0.3, cx: c, cy: c, scale: 1)
        let scale = OrbMath.responsiveScale(size, o["rsPow"] ?? 0.6)
        let orbitCount = Int(o["orbitN"] ?? 12)
        let ghostCount = Int(o["ghostN"] ?? 40)
        let particleCount = Int(o["particles"] ?? 3)
        var dots: [OrbDot] = []

        for i in 0..<orbitCount {
            let fi = Double(i)
            let r1 = OrbMath.hash(fi, 1.7), r2 = OrbMath.hash(fi, 5.2), r3 = OrbMath.hash(fi, 8.9)
            let orbitRadius = radius * (0.45 + 0.52 * r1)
            let phi = r1 * 2 * .pi
            let theta = acos(2 * r2 - 1)
            let nx = sin(theta) * cos(phi), ny = cos(theta), nz = sin(theta) * sin(phi)
            var ux = -ny, uy = nx
            let uLen = max(1e-6, (ux * ux + uy * uy).squareRoot())
            ux /= uLen; uy /= uLen
            let vx = -nz * uy, vy = nz * ux, vz = nx * uy - ny * ux
            let speed = (0.25 + 0.55 * r3) * (r3 > 0.5 ? 1 : -1)

            func at(_ angle: Double) -> (x: Double, y: Double, z: Double) {
                rot.project((ux * cos(angle) + vx * sin(angle)) * orbitRadius,
                            (uy * cos(angle) + vy * sin(angle)) * orbitRadius,
                            (vz * sin(angle)) * orbitRadius)
            }
            for g in 0..<ghostCount {
                let p = at(Double(g) / Double(ghostCount) * 2 * .pi)
                let depth = (p.z / orbitRadius + 1) / 2
                dots.append(OrbDot(x: p.x, y: p.y, z: p.z, r: (o["ghostR"] ?? 0.9) * scale, white: 0.72,
                                   a: (o["ghostA"] ?? 0.5) * (0.4 + 0.6 * depth)))
            }
            for k in 0..<particleCount {
                let p = at(time * speed + Double(k) / Double(particleCount) * 2 * .pi + r2 * 6)
                let depth = (p.z / orbitRadius + 1) / 2
                dots.append(OrbDot(x: p.x, y: p.y, z: p.z,
                                   r: ((o["partR"] ?? 1.2) + (o["partRDepth"] ?? 1.6) * depth) * scale,
                                   white: 0.3 - 0.22 * depth))
            }
        }
        return finish(dots, [], minRadius: o["rMin"] ?? 0.3)
    }

    // MARK: Globe (searching)

    static func globe(_ size: Double, _ time: Double, _ o: OrbOptions) -> OrbPass {
        let c = size / 2
        let radius = c * 0.82
        let rotX = 0.4 + 0.06 * sin(time * 0.35)
        let rot = OrbRotation(rotY: time * 0.5, rotX: rotX, cx: c, cy: c, scale: radius)
        let scanSweep = time * (0.5 + 1.2 * (o["scanMul"] ?? 1))
        let scale = OrbMath.responsiveScale(size, o["rsPow"] ?? 0.6)
        let dimBase = o["dimBase"] ?? 1
        let latRings = Int(o["latRings"] ?? 17)
        let lonDensity = o["lonDensity"] ?? 44
        var dots: [OrbDot] = []

        for ring in 0...latRings {
            let lat = -Double.pi / 2 + Double(ring) / Double(latRings) * .pi
            let cosLat = cos(lat), sinLat = sin(lat)
            let lonCount = max(1, Int((abs(cosLat) * lonDensity).rounded()))
            for lon in 0..<lonCount {
                let lonAngle = Double(lon) / Double(lonCount) * 2 * .pi
                let p = rot.project(cosLat * cos(lonAngle), sinLat, cosLat * sin(lonAngle))
                let depth = (p.z + 1) / 2
                let delta = OrbMath.angleDelta(lonAngle + time * 0.5, scanSweep)
                let scan = exp(-(delta * delta) / 0.18) * max(0, p.z)
                dots.append(OrbDot(
                    x: p.x, y: p.y, z: p.z,
                    r: ((o["rBase"] ?? 0.6) + (o["rDepth"] ?? 1.7) * depth + (o["rBoost"] ?? 1) * scan) * scale,
                    white: (o["inkFar"] ?? 0.62) - (o["inkSpan"] ?? 0.54) * depth,
                    a: dimBase + (1 - dimBase) * min(1, scan)))
            }
        }
        return finish(dots, [], minRadius: o["rMin"] ?? 0.3)
    }

    // MARK: Rubik (solving)

    private struct Move { let axis: Int; let lo: Double; let hi: Double; let ang: Double }

    private static func moves(_ count: Int) -> [Move] {
        (0..<count).map { i in
            let fi = Double(i)
            let axis = min(2, Int(OrbMath.hash(fi, 2.3) * 3))
            let slice = -1 + 0.5 * Double(min(3, Int(OrbMath.hash(fi, 5.9) * 4)))
            let dir: Double = OrbMath.hash(fi, 7.7) < 0.5 ? 1 : -1
            return Move(axis: axis, lo: slice, hi: slice + 0.5, ang: dir * .pi / 2)
        }
    }

    private static func amounts(_ time: Double, _ count: Int, _ moveDur: Double, _ pause: Double)
        -> (amount: [Double], active: Int)
    {
        let total = 2 * Double(count) * moveDur + pause
        let t = time.truncatingRemainder(dividingBy: total)
        var amount = [Double](repeating: 0, count: count)
        guard t < 2 * Double(count) * moveDur else { return (amount, -1) }
        let step = Int(t / moveDur)
        let stepT = (t - Double(step) * moveDur) / moveDur
        let ease = 1 - pow(1 - min(1, stepT / 0.7), 3)
        if step < count {
            for i in 0..<step { amount[i] = 1 }
            amount[step] = ease
            return (amount, step)
        }
        let rewind = 2 * count - 1 - step
        for i in 0..<rewind { amount[i] = 1 }
        amount[rewind] = 1 - ease
        return (amount, rewind)
    }

    static func rubik(_ size: Double, _ time: Double, _ o: OrbOptions) -> OrbPass {
        let c = size / 2
        let radius = c * 0.82
        let rot = OrbRotation(rotY: time * 0.55, rotX: 0.35 + 0.1 * sin(time * 0.9), cx: c, cy: c, scale: radius)
        let scale = OrbMath.responsiveScale(size, o["rsPow"] ?? 0.6)
        let moveCount = Int(o["moveCount"] ?? 14)
        let list = moves(moveCount)
        let anim = amounts(time, moveCount, 0.42, 1.2)
        let latRings = Int(o["latRings"] ?? 15)
        let lonDensity = o["lonDensity"] ?? 40
        var dots: [OrbDot] = []

        for ring in 0...latRings {
            let lat = -Double.pi / 2 + Double(ring) / Double(latRings) * .pi
            let cosLat = cos(lat), sinLat = sin(lat)
            let lonCount = max(1, Int((abs(cosLat) * lonDensity).rounded()))
            for lon in 0..<lonCount {
                let lonAngle = Double(lon) / Double(lonCount) * 2 * .pi
                var (x, y, z) = (cosLat * cos(lonAngle), sinLat, cosLat * sin(lonAngle))
                var active = false
                for (i, move) in list.enumerated() where anim.amount[i] > 0 {
                    let coord = move.axis == 0 ? x : (move.axis == 1 ? y : z)
                    guard coord >= move.lo, coord < move.hi else { continue }
                    if i == anim.active { active = true }
                    let angle = move.ang * anim.amount[i]
                    let ca = cos(angle), sa = sin(angle)
                    switch move.axis {
                    case 0: let ny = y * ca - z * sa; z = y * sa + z * ca; y = ny
                    case 1: let nx = x * ca + z * sa; z = -x * sa + z * ca; x = nx
                    default: let nx = x * ca - y * sa; y = x * sa + y * ca; x = nx
                    }
                }
                let p = rot.project(x, y, z)
                let depth = (p.z + 1) / 2
                dots.append(OrbDot(
                    x: p.x, y: p.y, z: p.z,
                    r: ((o["rBase"] ?? 0.6) + (o["rDepth"] ?? 1.7) * depth + (active ? (o["rActive"] ?? 0.3) : 0)) * scale,
                    white: (o["inkFar"] ?? 0.62) - (o["inkSpan"] ?? 0.54) * depth - (active ? 0.14 : 0)))
            }
        }
        return finish(dots, [], minRadius: o["rMin"] ?? 0.3)
    }

    // MARK: Wave (listening)

    static func wave(_ size: Double, _ time: Double, _ o: OrbOptions) -> OrbPass {
        let c = size / 2
        let radius = c * 0.874
        let rot = OrbRotation(rotY: time * 0.18, rotX: 0.38, cx: c, cy: c, scale: 1)
        let scale = OrbMath.responsiveScale(size, o["rsPow"] ?? 0.6)
        let rings = Int(o["rings"] ?? 15)
        let lonDensity = o["lonDensity"] ?? 40
        var dots: [OrbDot] = []

        for ring in 0...rings {
            let fr = Double(ring)
            let lat = -Double.pi / 2 + fr / Double(rings) * .pi
            let cosLat = cos(lat), sinLat = sin(lat)
            let w = 0.62 * sin(time * 2.1 - fr * 0.52) + 0.38 * sin(time * 1.27 + fr * 0.83)
            let current = radius * (0.88 + 0.105 * w)
            let lonCount = max(1, Int((abs(cosLat) * lonDensity).rounded()))
            for lon in 0..<lonCount {
                let lonAngle = Double(lon) / Double(lonCount) * 2 * .pi
                let p = rot.project(cosLat * cos(lonAngle) * current, sinLat * current, cosLat * sin(lonAngle) * current)
                let depth = (p.z / radius + 1) / 2
                let pos = max(0, w)
                dots.append(OrbDot(
                    x: p.x, y: p.y, z: p.z,
                    r: ((o["rBase"] ?? 0.6) + (o["rDepth"] ?? 1.7) * depth) * (1 + 0.4 * pos) * scale,
                    white: 0.66 - 0.56 * depth - 0.1 * pos))
            }
        }
        return finish(dots, [], minRadius: o["rMin"] ?? 0.3)
    }
}
