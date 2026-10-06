import CompanionCore
import SwiftUI

/// Arc's voice orb on the island: a soft marble whose inner light swirls
/// while it thinks, swells and ripples with the mic while it listens, and
/// pulses with the voice while it speaks. The math is `IslandOrbSimulation`;
/// this view keeps the clock and paints. Reduce Motion paints one still
/// frame per state.
struct IslandOrb: View {
    let state: IslandOrbState
    var levels = VoiceLevels(mic: 0, agent: 0)
    /// The side of the slot it sits in. The ripples spread a little past it.
    let size: CGFloat
    var tint: Swatch = ArcTone.accent
    var tint2: Swatch = Accent.purple
    /// One still frame instead of the live loop: while the island hides the
    /// orb it should cost nothing.
    var still = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var clock = IslandOrbClock()

    /// The canvas is wider than the slot so the listening ripples are not clipped.
    static let bleed: CGFloat = 1.4

    var body: some View {
        Group {
            if reduceMotion || still {
                canvas(IslandOrbFrame.still(state))
            } else {
                TimelineView(.animation) { timeline in
                    canvas(clock.advance(to: timeline.date, state: state, levels: levels))
                }
            }
        }
        .frame(width: size * Self.bleed, height: size * Self.bleed)
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityElement()
        .accessibilityLabel(Localized.string(label))
    }

    private func canvas(_ frame: IslandOrbFrame) -> some View {
        let palette = IslandOrbPalette(tint: tint, tint2: tint2)
        return Canvas { context, canvasSize in
            IslandOrbPainter.draw(in: &context, side: min(canvasSize.width, canvasSize.height),
                                 frame: frame, palette: palette)
        }
    }

    private var label: String {
        switch state {
        case .idle: "orb.idle"
        case .listening: "orb.listening"
        case .thinking: "orb.thinking"
        case .speaking: "orb.speaking"
        }
    }
}

/// One frame's worth of what the painter needs.
struct IslandOrbFrame: Sendable {
    let params: IslandOrbParams
    let phase: Double
    let swirl: Double
    let level: Double

    static func still(_ state: IslandOrbState) -> IslandOrbFrame {
        IslandOrbFrame(params: .target(state), phase: 1.2, swirl: 0.6, level: state == .speaking ? 0.35 : 0)
    }
}

/// The simulation lives in a reference so a frame can step it without
/// invalidating the view; only the timeline drives redraws.
@MainActor final class IslandOrbClock {
    private var simulation = IslandOrbSimulation(state: .idle)
    private var last: Date?

    func advance(to now: Date, state: IslandOrbState, levels: VoiceLevels) -> IslandOrbFrame {
        let dt = last.map { now.timeIntervalSince($0) } ?? 0
        last = now
        simulation.step(dt: dt, state: state, input: levels.mic, output: levels.agent)
        return IslandOrbFrame(params: simulation.current, phase: simulation.phase,
                             swirl: simulation.swirlPhase, level: simulation.level)
    }
}

struct IslandOrbPalette: Sendable {
    let foreground: (r: Double, g: Double, b: Double)
    let shade: (r: Double, g: Double, b: Double)
    let tint: (r: Double, g: Double, b: Double)
    let tint2: (r: Double, g: Double, b: Double)

    init(tint: Swatch, tint2: Swatch) {
        let fg = Self.rgb(ArcTone.foreground)
        foreground = fg
        // The island is black: the marble's dark side is the foreground pulled a third toward it.
        shade = (fg.r * 0.68, fg.g * 0.68, fg.b * 0.68)
        let a = Self.rgb(tint), b = Self.rgb(tint2)
        self.tint = IslandOrbGeometry.glow(r: a.r, g: a.g, b: a.b)
        self.tint2 = IslandOrbGeometry.glow(r: b.r, g: b.g, b: b.b)
    }

    func color(_ c: (r: Double, g: Double, b: Double), _ alpha: Double) -> Color {
        Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: min(1, max(0, alpha)))
    }

    private static func rgb(_ swatch: Swatch) -> (r: Double, g: Double, b: Double) {
        let c = swatch.ns.usingColorSpace(.sRGB) ?? .white
        return (Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent))
    }
}

enum IslandOrbPainter {
    static func draw(in context: inout GraphicsContext, side: CGFloat, frame: IslandOrbFrame, palette: IslandOrbPalette) {
        let p = frame.params
        let c = side / 2
        let radius = IslandOrbGeometry.bodyRadius(side: Double(side), params: p, phase: frame.phase, level: frame.level)

        // The listening ripple: two faint outlines that spread with the level.
        if p.ring > 0.01 {
            for (spread, weight) in [(0.1, 1.0), (0.22, 0.5)] {
                var calm = p
                calm.wobble *= 0.6
                let ripple = blob(center: c, base: radius * (1 + spread + frame.level * spread * 1.6), params: calm,
                                  phase: frame.phase * 0.8, swirl: frame.swirl, level: frame.level * 0.5)
                context.stroke(ripple, with: .color(palette.color(palette.foreground,
                                                                  p.ring * weight * (0.07 + frame.level * 0.2))),
                               lineWidth: 1.25)
            }
        }

        // The body: a soft marble lit from the upper left.
        let body = blob(center: c, base: radius, params: p, phase: frame.phase, swirl: frame.swirl, level: frame.level)
        let light = CGPoint(x: c - radius * 0.38, y: c - radius * 0.46)
        context.fill(body, with: .radialGradient(
            Gradient(stops: [
                .init(color: palette.color(palette.foreground, 1), location: 0),
                .init(color: palette.color(mix(palette.foreground, palette.shade, 0.7), 1), location: 0.6),
                .init(color: palette.color(palette.shade, 1), location: 1),
            ]),
            center: light, startRadius: radius * 0.05, endRadius: radius * 1.3))

        // Inner light: two tinted clouds orbit inside the body.
        var inner = context
        inner.clip(to: body)
        for i in 0..<2 {
            let angle = frame.swirl * (i == 1 ? -0.8 : 1) + frame.phase * 0.25 + Double(i) * 2.6
            let distance = radius * p.orbit * (1 + 0.25 * sin(frame.phase * 0.9 + Double(i) * 1.7))
            let x = c + cos(angle) * distance, y = c + sin(angle) * distance + radius * 0.12
            let r = radius * (0.78 + frame.level * 0.22 - Double(i) * 0.12)
            let tone = i == 1 ? palette.tint2 : palette.tint
            let alpha = p.tint * (i == 1 ? 0.55 : 0.85) * 0.8
            inner.fill(Path(CGRect(x: 0, y: 0, width: side, height: side)), with: .radialGradient(
                Gradient(stops: [
                    .init(color: palette.color(tone, alpha), location: 0),
                    .init(color: palette.color(tone, alpha * 0.35), location: 0.55),
                    .init(color: palette.color(tone, 0), location: 1),
                ]),
                center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r))
        }
    }

    private static func blob(center c: CGFloat, base: Double, params: IslandOrbParams,
                             phase: Double, swirl: Double, level: Double) -> Path {
        var path = Path()
        let n = IslandOrbGeometry.points
        for i in 0...n {
            let a = Double(i) / Double(n) * 2 * .pi
            let r = IslandOrbGeometry.radius(at: a, base: base, params: params, phase: phase, swirl: swirl, level: level)
            let point = CGPoint(x: c + cos(a) * r, y: c + sin(a) * r)
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private static func mix(_ a: (r: Double, g: Double, b: Double), _ b: (r: Double, g: Double, b: Double),
                            _ t: Double) -> (r: Double, g: Double, b: Double) {
        (a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
    }
}
