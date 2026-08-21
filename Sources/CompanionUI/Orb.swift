import CompanionCore
import SwiftUI

public struct Orb: View {
    let state: TurnState
    let levels: VoiceLevels
    let accentColor: Color

    @Environment(\.accessibilityReduceMotion) var reduceMotion

    public init(
        state: TurnState,
        levels: VoiceLevels,
        accentColor: Color
    ) {
        self.state = state
        self.levels = levels
        self.accentColor = accentColor
    }

    public var body: some View {
        OrbCanvas(
            state: state,
            levels: levels,
            accentColor: accentColor,
            reduceMotion: reduceMotion
        )
        .scaleEffect(OrbAppearance.scaleFromLevel(
            state == .listening || state == .speaking ? levels.mic : 0
        ))
        .opacity(OrbAppearance.opacity(for: state))
        .animation(.easeOut(duration: 0.08), value: levels)
        .animation(reduceMotion ? .easeOut(duration: MotionTime.fast)
                   : .springSelect, value: state)
    }
}

/// Separate view to handle Canvas rendering without generic type issues.
private struct OrbCanvas: View {
    let state: TurnState
    let levels: VoiceLevels
    let accentColor: Color
    let reduceMotion: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                drawOrbShape(context: context, size: size, now: timeline.date)
            }
        }
    }

    private func drawOrbShape(
        context: GraphicsContext,
        size: CGSize,
        now: Date
    ) {
        let centerX = size.width / 2
        let centerY = size.height / 2
        let radius = min(size.width, size.height) / 2

        // Time-based animation
        let timeNow = now.timeIntervalSinceReferenceDate
        let effectiveSpeed = OrbAppearance.effectiveAnimationSpeed(
            for: state,
            reduceMotion: reduceMotion
        )
        let angle = effectiveSpeed > 0
            ? (timeNow.remainder(dividingBy: 60 / effectiveSpeed) / (60 / effectiveSpeed)) * 2 * .pi
            : 0

        // Choose base color based on state
        let baseColor = OrbAppearance.baseColor(for: state) == "accent"
            ? accentColor
            : Semantic.destructive

        // Create blob shape (6 control points around circle)
        let points = createBlobPoints(
            center: CGPoint(x: centerX, y: centerY),
            radius: radius * 0.85,
            time: angle,
            count: 6
        )

        // Draw the blob
        var path = Path()
        if !points.isEmpty {
            path.move(to: points[0])
            for i in 0..<points.count {
                let next = (i + 1) % points.count
                let tangent1 = tangent(at: i, points: points)
                let tangent2 = tangent(at: next, points: points)
                let control1 = CGPoint(
                    x: points[i].x + tangent1.x * radius * 0.2,
                    y: points[i].y + tangent1.y * radius * 0.2
                )
                let control2 = CGPoint(
                    x: points[next].x - tangent2.x * radius * 0.2,
                    y: points[next].y - tangent2.y * radius * 0.2
                )
                path.addCurve(to: points[next], control1: control1, control2: control2)
            }
        }

        context.fill(path, with: .color(baseColor))
    }

    private func createBlobPoints(
        center: CGPoint,
        radius: CGFloat,
        time: Double,
        count: Int
    ) -> [CGPoint] {
        (0..<count).map { index in
            let baseAngle = (Double(index) / Double(count)) * 2 * .pi
            let phaseOffset = Double(index) * .pi / 3

            // Vary radius with sine wave for organic breathing
            let radiusScale = 0.85 + sin(time + phaseOffset) * 0.15
            let angle = baseAngle + sin(time + phaseOffset) * 0.1

            return CGPoint(
                x: center.x + cos(angle) * radius * radiusScale,
                y: center.y + sin(angle) * radius * radiusScale
            )
        }
    }

    private func tangent(at index: Int, points: [CGPoint]) -> CGPoint {
        guard points.count > 1 else { return CGPoint(x: 0, y: 0) }
        let prev = points[(index - 1 + points.count) % points.count]
        let next = points[(index + 1) % points.count]
        return CGPoint(
            x: (next.x - prev.x) * 0.5,
            y: (next.y - prev.y) * 0.5
        )
    }
}

#Preview {
    VStack(spacing: Space.x5) {
        Text("Idle")
        Orb(state: .idle, levels: VoiceLevels(mic: 0, agent: 0), accentColor: Semantic.accent)
            .frame(width: 100, height: 100)

        Text("Listening")
        Orb(state: .listening, levels: VoiceLevels(mic: 0.7, agent: 0), accentColor: Semantic.accent)
            .frame(width: 100, height: 100)

        Text("Thinking")
        Orb(state: .thinking, levels: VoiceLevels(mic: 0, agent: 0.5), accentColor: Semantic.accent)
            .frame(width: 100, height: 100)

        Text("Error")
        Orb(state: .error, levels: VoiceLevels(mic: 0, agent: 0), accentColor: Semantic.accent)
            .frame(width: 100, height: 100)
    }
    .padding()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Semantic.background)
}
