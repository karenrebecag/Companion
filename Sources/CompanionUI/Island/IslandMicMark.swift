import SwiftUI

enum IslandMicMarkMetrics {
    /// The share of the disc the glyph takes, as the island's icon buttons draw it.
    static let glyphScale: CGFloat = 0.42
}

/// The composer's talk control: a microphone where the voice orb was (Karen
/// chose performance over the animated sphere, 2026-10-13). Drawn like an
/// island icon button, but the caller owns the gesture: a hold talks and a
/// tap opens the window, which a `Button` cannot tell apart.
struct IslandMicMark: View {
    let side: CGFloat
    /// Lit while the microphone is open.
    let listening: Bool
    @State private var hovering = false

    var body: some View {
        Image(systemName: "mic.fill")
            .font(Fonts.symbol(side * IslandMicMarkMetrics.glyphScale, weight: .medium))
            .foregroundStyle(lit ? IslandInk.text : IslandInk.secondary)
            .frame(width: side, height: side)
            .background(Circle().fill(lit ? IslandInk.chipPressed : IslandInk.chip))
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .animation(MotionCurve.animation(MotionCurve.standard, MotionTime.fast), value: lit)
    }

    private var lit: Bool { hovering || listening }
}
