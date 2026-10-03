import Foundation

// Ported from Space UI (MIT): the per-mode density and speed, interpolated
// between a 20 px and a 64 px profile so a small orb stays legible.

package typealias OrbOptions = [String: Double]

nonisolated package enum ThinkingOrbPreset {
    package struct Result {
        package let speed: Double
        package let options: OrbOptions
    }

    private struct Profile {
        let speed: Double, count: Double, size: Double
        var extra: [String: Double] = [:]
    }

    package static func make(_ mode: ThinkingOrbMode, pixelSize: Double) -> Result {
        let (small, large) = profiles(mode)
        let t = OrbMath.clamp((pixelSize - 20) / 44)
        let countScale = OrbMath.lerp(small.count, large.count, t)
        let sizeScale = OrbMath.lerp(small.size, large.size, t)
        var options = defaults(mode)
        if countScale != 1 { options = scaleCounts(options, countScale) }
        if sizeScale != 1 { options = scaleSizes(options, sizeScale) }
        for (key, from) in small.extra {
            options[key] = OrbMath.lerp(from, large.extra[key] ?? from, t)
        }
        return Result(speed: OrbMath.lerp(small.speed, large.speed, t), options: options)
    }

    private static let countCouples = [["latRings", "lonDensity"], ["rings", "lonDensity"], ["lanes", "segs"]]
    private static let countKeys = ["orbitN", "ghostN", "nodeN", "strandN", "signals"]
    private static let sizeKeys = ["rBase", "rDepth", "rActive", "rDot", "ghostR", "partR", "partRDepth", "nodeR", "nodeRDepth"]

    private static func scaleCounts(_ config: OrbOptions, _ factor: Double) -> OrbOptions {
        var result = config
        var visited = Set<String>()
        let root = factor.squareRoot()
        for couple in countCouples {
            let (k1, k2) = (couple[0], couple[1])
            if let v1 = result[k1], let v2 = result[k2], !visited.contains(k1), !visited.contains(k2) {
                result[k1] = max(2, (v1 * root).rounded())
                result[k2] = max(2, (v2 * root).rounded())
                visited.insert(k1)
                visited.insert(k2)
            }
        }
        for key in countKeys {
            if let v = result[key], v != 0, !visited.contains(key) {
                result[key] = max(1, (v * factor).rounded())
            }
        }
        if let d = result["iconD"] { result["iconD"] = max(0.02, d * factor) }
        return result
    }

    private static func scaleSizes(_ config: OrbOptions, _ factor: Double) -> OrbOptions {
        var result = config
        for key in sizeKeys {
            if let v = result[key] { result[key] = v * factor }
        }
        return result
    }

    private static func defaults(_ mode: ThinkingOrbMode) -> OrbOptions {
        switch mode {
        case .globe:
            ["latRings": 17, "lonDensity": 44, "rBase": 0.6, "rDepth": 1.7, "rBoost": 1,
             "inkFar": 0.62, "inkSpan": 0.54, "rsPow": 0.6, "rMin": 0.3]
        case .orbits:
            ["orbitN": 12, "ghostN": 40, "ghostR": 0.9, "ghostA": 0.5, "particles": 3,
             "partR": 1.2, "partRDepth": 1.6, "rsPow": 0.6, "rMin": 0.3]
        case .rubik:
            ["latRings": 15, "lonDensity": 40, "moveCount": 14, "rBase": 0.6, "rDepth": 1.7,
             "rActive": 0.3, "inkFar": 0.62, "inkSpan": 0.54, "rsPow": 0.6, "rMin": 0.3]
        case .wave:
            ["rings": 15, "lonDensity": 40, "rBase": 0.6, "rDepth": 1.7, "rsPow": 0.6, "rMin": 0.3]
        case .web:
            ["nodeN": 30, "thr": 0.72, "signals": 5, "nodeR": 1.4, "nodeRDepth": 1.8,
             "lineW": 0.8, "rsPow": 0.6, "rMin": 0.3]
        case .braid:
            ["strandN": 52, "turns": 3, "ghostN": 150, "rBase": 1.2, "rDepth": 1.8,
             "rsPow": 0.6, "rMin": 0.3]
        case .ribbon:
            ["lanes": 5, "segs": 88, "ghostN": 150, "rBase": 1.1, "rDepth": 1.7,
             "rsPow": 0.6, "rMin": 0.3]
        case .ring:
            ["lanes": 5, "segs": 88, "ghostN": 0, "faceOn": 1, "rBase": 1.1, "rDepth": 1.7,
             "rsPow": 0.6, "rMin": 0.3]
        case .morph:
            ["rDot": 0.021, "iconD": 1, "rMin": 0.25]
        }
    }

    private static func profiles(_ mode: ThinkingOrbMode) -> (small: Profile, large: Profile) {
        switch mode {
        case .orbits:
            (Profile(speed: 3.9, count: 0.238, size: 2.4), Profile(speed: 1.885, count: 1, size: 1))
        case .globe:
            (Profile(speed: 2.665, count: 0.105, size: 1.75, extra: ["scanMul": 4.335, "dimBase": 0.45]),
             Profile(speed: 2.015, count: 0.42, size: 1.15, extra: ["scanMul": 4.08, "dimBase": 0.45]))
        case .rubik:
            (Profile(speed: 1.95, count: 0.088, size: 1.9), Profile(speed: 1.82, count: 0.35, size: 1.05))
        case .wave:
            (Profile(speed: 3.998, count: 0.105, size: 1.6), Profile(speed: 4.388, count: 0.341, size: 1))
        case .web:
            (Profile(speed: 6.63, count: 0.25, size: 1.52), Profile(speed: 3.315, count: 1.35, size: 0.95))
        case .braid:
            (Profile(speed: 2.75, count: 0.1125, size: 1.36), Profile(speed: 1.625, count: 0.5, size: 1))
        case .ribbon:
            (Profile(speed: 3.12, count: 0.051, size: 1.073, extra: ["spin": 0, "bandMul": 4.94, "wobMul": 1]),
             Profile(speed: 2.34, count: 0.25, size: 0.85, extra: ["spin": 0, "bandMul": 3.9, "wobMul": 1]))
        case .ring:
            (Profile(speed: 3.78, count: 0.028, size: 1.622, extra: ["spin": 0, "bandMul": 3.968, "wobMul": 0.565]),
             Profile(speed: 3.24, count: 0.25, size: 0.956, extra: ["spin": 0, "bandMul": 3.627, "wobMul": 0.368]))
        case .morph:
            (Profile(speed: 2.08, count: 0.53, size: 1.011, extra: ["spread": 1.45]),
             Profile(speed: 2.405, count: 0.702, size: 0.395, extra: ["spread": 1.45]))
        }
    }
}
