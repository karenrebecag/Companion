import CompanionCore
import SwiftUI

// Wave 16o-3: Incredible's ink trail and the orb that follows the cursor
// while fn is held, measured in docs/research/incredible-fn-glow-pointer.md.

package struct TrailPoint: Equatable, Sendable {
    package let position: CGPoint
    package let time: Double
    /// A jump starts a new stroke, so no line crosses the screen.
    package let stroke: Int
}

package struct PointerTrail: Sendable {
    package static let ink = Swatch("4678F5")
    package static let life = 0.62
    /// The last fifth of a point's life narrows it to nothing.
    package static let taper = 0.2
    package static let alpha = 0.3
    package static let maxWidth: CGFloat = 16
    package static let follow: CGFloat = 0.3
    package static let minStep: CGFloat = 1.5
    package static let breakJump: CGFloat = 260

    package private(set) var points: [TrailPoint] = []
    private var head: CGPoint?
    private var stroke = 0

    package init() {}

    package mutating func add(_ cursor: CGPoint, at time: Double) {
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

    package mutating func prune(at time: Double) {
        points.removeAll { time - $0.time > Self.life }
    }

    package mutating func reset() {
        points = []
        head = nil
    }

    package static func width(age: Double) -> CGFloat {
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

package enum PointerOrb {
    package static let size: CGFloat = 32
    package static let offset = CGSize(width: 14, height: 17)
    package static let follow: CGFloat = 0.16

    /// Only with fn down, on the display the pointer is on, and never under
    /// Reduce Motion (the pointing itself is still read, only not drawn).
    package static func shows(kind: SessionKind, reduceMotion: Bool, screen: CGRect, cursor: CGPoint) -> Bool {
        kind == .listening && !reduceMotion && screen.contains(cursor)
    }

    /// One frame toward the cursor's corner: it trails, it never covers the tip.
    package static func step(from orb: CGPoint, cursor: CGPoint) -> CGPoint {
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

/// The trail and the hold companion over one display. The companion's box rides the orb
/// point; the trail is drawn only while the key is down and motion is allowed. Which
/// display the pointer is on is read every frame, so both follow it across screens.
struct PointerLayer: View {
    let screenFrame: CGRect
    let kind: SessionKind
    let reduceMotion: Bool
    let companion: HoldCompanionState
    @State private var model = PointerTrailModel()

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let global = NSEvent.mouseLocation
            ZStack(alignment: .topLeading) {
                if let orb = advance(global: global, at: time) {
                    if PointerOrb.shows(kind: kind, reduceMotion: reduceMotion, screen: screenFrame, cursor: global) {
                        Canvas { context, _ in drawTrail(in: &context, at: time) }
                    }
                    HoldCompanion(state: companion, listening: kind == .listening)
                        .offset(x: orb.x, y: orb.y)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onDisappear { model.reset() }
    }

    /// One frame of the follow, or nil off this display; a class, so the walk never writes
    /// SwiftUI state while drawing.
    private func advance(global: CGPoint, at time: Double) -> CGPoint? {
        guard screenFrame.contains(global) else {
            model.reset()
            return nil
        }
        let cursor = CGPoint(x: global.x - screenFrame.minX, y: screenFrame.maxY - global.y)
        model.advance(cursor: cursor, at: time)
        return model.orb ?? cursor
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
}
