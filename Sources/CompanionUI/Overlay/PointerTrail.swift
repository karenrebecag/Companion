import CompanionCore
import SwiftUI

// Wave 16o-3: Incredible's ink trail and the orb that follows the cursor
// while fn is held, measured in docs/research/incredible-fn-glow-pointer.md.

public struct TrailPoint: Equatable, Sendable {
    public let position: CGPoint
    public let time: Double
    /// A jump starts a new stroke, so no line crosses the screen.
    public let stroke: Int
}

public struct PointerTrail: Sendable {
    public static let ink = Swatch("4678F5")
    public static let life = 0.62
    /// The last fifth of a point's life narrows it to nothing.
    public static let taper = 0.2
    public static let alpha = 0.3
    public static let maxWidth: CGFloat = 16
    public static let follow: CGFloat = 0.3
    public static let minStep: CGFloat = 1.5
    public static let breakJump: CGFloat = 260

    public private(set) var points: [TrailPoint] = []
    private var head: CGPoint?
    private var stroke = 0

    public init() {}

    public mutating func add(_ cursor: CGPoint, at time: Double) {
        prune(at: time)
        guard let head else {
            start(at: cursor, time: time)
            return
        }
        if Self.distance(cursor, head) > Self.breakJump {
            stroke += 1
            start(at: cursor, time: time)
            return
        }
        let next = CGPoint(x: head.x + (cursor.x - head.x) * Self.follow,
                           y: head.y + (cursor.y - head.y) * Self.follow)
        self.head = next
        guard Self.distance(next, points.last?.position ?? head) >= Self.minStep else { return }
        points.append(TrailPoint(position: next, time: time, stroke: stroke))
    }

    public mutating func prune(at time: Double) {
        points.removeAll { time - $0.time > Self.life }
    }

    public mutating func reset() {
        points = []
        head = nil
    }

    public static func width(age: Double) -> CGFloat {
        let narrowing = life * (1 - taper)
        guard age > narrowing else { return maxWidth }
        return maxWidth * CGFloat(max(0, (life - age) / (life * taper)))
    }

    private mutating func start(at cursor: CGPoint, time: Double) {
        head = cursor
        points.append(TrailPoint(position: cursor, time: time, stroke: stroke))
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

public enum PointerOrb {
    public static let size: CGFloat = 32
    public static let offset = CGSize(width: 14, height: 17)
    public static let follow: CGFloat = 0.16

    /// Only with fn down, on the display the pointer is on, and never under
    /// Reduce Motion (the pointing itself is still read, only not drawn).
    public static func shows(kind: SessionKind, reduceMotion: Bool, screen: CGRect, cursor: CGPoint) -> Bool {
        kind == .listening && !reduceMotion && screen.contains(cursor)
    }

    /// One frame toward the cursor's corner: it trails, it never covers the tip.
    public static func step(from orb: CGPoint, cursor: CGPoint) -> CGPoint {
        let target = CGPoint(x: cursor.x + offset.width, y: cursor.y + offset.height)
        return CGPoint(x: orb.x + (target.x - orb.x) * follow, y: orb.y + (target.y - orb.y) * follow)
    }
}

/// Mutated from inside the Canvas each frame; a class so drawing never
/// writes SwiftUI state during a render pass.
@MainActor
final class PointerTrailModel {
    var trail = PointerTrail()
    var orb: CGPoint?

    func advance(cursor: CGPoint, at time: Double) {
        trail.add(cursor, at: time)
        orb = PointerOrb.step(from: orb ?? cursor, cursor: cursor)
    }

    func reset() {
        trail.reset()
        orb = nil
    }
}

/// The trail and the orb over one display, drawn only while listening.
struct PointerLayer: View {
    let screenFrame: CGRect
    @State private var model = PointerTrailModel()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, _ in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let global = NSEvent.mouseLocation
                let cursor = CGPoint(x: global.x - screenFrame.minX, y: screenFrame.maxY - global.y)
                model.advance(cursor: cursor, at: time)
                drawTrail(in: &context, at: time)
                drawOrb(in: &context)
            }
        }
        .onDisappear { model.reset() }
    }

    private func drawTrail(in context: inout GraphicsContext, at time: Double) {
        var layer = context
        layer.opacity = PointerTrail.alpha
        let points = model.trail.points
        for (a, b) in zip(points, points.dropFirst()) where a.stroke == b.stroke {
            var path = Path()
            path.move(to: a.position)
            path.addLine(to: b.position)
            let width = PointerTrail.width(age: time - b.time)
            layer.stroke(path, with: .color(PointerTrail.ink.color),
                         style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
    }

    private func drawOrb(in context: inout GraphicsContext) {
        guard let orb = model.orb else { return }
        let radius = PointerOrb.size / 2
        let rect = CGRect(x: orb.x - radius, y: orb.y - radius, width: PointerOrb.size, height: PointerOrb.size)
        let shading = GraphicsContext.Shading.radialGradient(
            Gradient(colors: [Neutral.white.color, ScreenGlow.colors[3].color, ScreenGlow.colors[0].color]),
            center: CGPoint(x: orb.x - radius * 0.3, y: orb.y - radius * 0.3), startRadius: 0, endRadius: radius * 1.3)
        context.fill(Path(ellipseIn: rect), with: shading)
    }
}
