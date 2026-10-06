import CompanionTestKit
@testable import CompanionUI
import Foundation
import Testing

// Arc's motion presets and dark tones, ported 1:1 from uiarc.dev
// (lib/motion-tokens.ts and foundation.css, dark theme).

@Test @MainActor func arcSpringsMatchTheirPresets() {
    expectEq(ArcMotion.panel.response, 0.4, "smooth: 0.4 s")
    expectEq(ArcMotion.panel.damping, 1, "smooth: bounce 0")
    expectEq(ArcMotion.press.response, 0.26, "snappy: 0.26 s")
    expect(abs(ArcMotion.press.damping - 0.88) < 1e-9, "snappy: bounce 0.12")
}

// Anything that reports state lands without overshoot (Arc motion.md).
@Test @MainActor func theSmoothSpringNeverOvershoots() {
    expectEq(ArcMotion.panel.overshoot, 0, "smooth: sin rebote")
    expect(ArcMotion.press.overshoot < 0.08, "snappy: dentro del tope M4")
}

@Test @MainActor func arcDurationsAndCurves() {
    expectEq(ArcMotion.Duration.fast, 0.16, "fast")
    expectEq(ArcMotion.Duration.exit, 0.18, "exit")
    expectEq(ArcMotion.Duration.standard, 0.24, "standard")
    expectEq(ArcMotion.Curve.enter, [0.16, 1, 0.3, 1], "ease.enter")
    expectEq(ArcMotion.Curve.exit, [0.7, 0, 0.84, 0], "ease.exit")
    expectEq(ArcMotion.Curve.standard, [0.22, 1, 0.36, 1], "ease.standard")
    // Exits are faster than entrances.
    expect(ArcMotion.Duration.exit < ArcMotion.Duration.standard, "salida mas corta que la entrada")
}

@Test @MainActor func arcBlur() {
    expectEq(ArcMotion.Blur.soft, 4, "blur.soft")
}

// One tone per meaning: the island used four greens and three reds.
@Test @MainActor func arcDarkTonesAreTheOnlySignalColors() {
    expectEq(ArcTone.success.hex, "4CD676", "success oklch(78% .18 150)")
    expectEq(ArcTone.warning.hex, "FFB90E", "warning oklch(83% .17 80)")
    expectEq(ArcTone.danger.hex, "FF736D", "danger oklch(76% .2 25)")
    expectEq(ArcTone.accent.hex, "6BA3FF", "accent azul oscuro")
    expectEq(ArcTone.surface.hex, "191919", "surface oklch(21.5%)")
    expectEq(ArcTone.surfaceMuted.hex, "242424", "surface-muted oklch(26%)")
    expectEq(ArcTone.border.hex, "2B2B2B", "border oklch(29%)")
}

@Test @MainActor func reduceMotionDropsTravel() {
    expect(ArcMotion.panel.animation(reduceMotion: true) == nil, "reducido: sin resorte")
    expect(ArcMotion.panel.animation(reduceMotion: false) != nil, "normal: con resorte")
}
