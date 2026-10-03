import CompanionCore
import SwiftUI

/// Which end of the grey ramp is bright: `ink` is light dots on a dark
/// ground, `paper` the reverse, `auto` follows the appearance.
package enum ThinkingOrbSurface: Sendable {
    case ink, paper, auto
}

/// Space UI's thinking orb (MIT, see NOTICE.md) drawn with Canvas. It is
/// decorative: the state it shows is already spoken by the surrounding UI.
package struct ThinkingOrb: View {
    let mode: ThinkingOrbMode
    let surface: ThinkingOrbSurface
    let scale: Double
    let speed: Double
    let size: CGFloat
    let paused: Bool

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    package init(
        mode: ThinkingOrbMode, surface: ThinkingOrbSurface = .auto, scale: Double = 0.72,
        speed: Double = 1, size: CGFloat, paused: Bool = false
    ) {
        self.mode = mode
        self.surface = surface
        self.scale = scale
        self.speed = speed
        self.size = size
        self.paused = paused
    }

    /// Space UI throttles its canvas to about 45 fps; an ambient orb has no
    /// use for the display's full rate.
    package static let frameInterval = 1.0 / 45

    /// The still frame is the source's static render, at 0.6 of its clock.
    package static func sceneTime(still: Bool, now: Double, speed: Double, presetSpeed: Double) -> Double {
        still ? 0.6 * presetSpeed : now * max(speed, 0.05) * presetSpeed
    }

    private var darkSurface: Bool {
        switch surface {
        case .ink: true
        case .paper: false
        case .auto: colorScheme == .dark
        }
    }

    package var body: some View {
        // Reduce motion freezes the scene at the frame the source uses for
        // its static render.
        let still = paused || reduceMotion
        TimelineView(.animation(minimumInterval: Self.frameInterval, paused: still)) { timeline in
            Canvas { context, canvas in
                draw(&context, canvas, at: timeline.date.timeIntervalSinceReferenceDate, still: still)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func draw(_ context: inout GraphicsContext, _ canvas: CGSize, at now: Double, still: Bool) {
        let inner = max(8, Double(min(canvas.width, canvas.height)) * OrbMath.clamp(scale))
        let preset = ThinkingOrbPreset.make(mode, pixelSize: inner)
        let time = Self.sceneTime(still: still, now: now, speed: speed, presetSpeed: preset.speed)
        let pass = ThinkingOrbScene.render(mode, size: inner, time: time, options: preset.options)
        context.translateBy(x: (canvas.width - inner) / 2, y: (canvas.height - inner) / 2)
        for line in pass.lines {
            var path = Path()
            path.move(to: CGPoint(x: line.x1, y: line.y1))
            path.addLine(to: CGPoint(x: line.x2, y: line.y2))
            context.stroke(path, with: .color(grey(line.white, line.a)), lineWidth: line.w)
        }
        for dot in pass.dots {
            let rect = CGRect(x: dot.x - dot.r, y: dot.y - dot.r, width: dot.r * 2, height: dot.r * 2)
            context.fill(Path(ellipseIn: rect), with: .color(grey(dot.white, dot.a)))
        }
    }

    /// On a dark surface a small `white` is a bright highlight.
    private func grey(_ white: Double, _ alpha: Double?) -> Color {
        let w = OrbMath.clamp(white)
        return Color(white: darkSurface ? 1 - w : w, opacity: alpha ?? 1)
    }
}

extension ThinkingOrb {
    package init(state: TurnState, surface: ThinkingOrbSurface = .auto, size: CGFloat) {
        self.init(mode: ThinkingOrbMode(state: state), surface: surface, size: size)
    }
}
