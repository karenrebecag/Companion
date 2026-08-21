import CompanionCore
import CompanionUI
import Testing

// Pure functions that map state and levels to visual properties.
// These drive the orb but are testable without view instantiation.

@Test
func orbBaseColorForIdleState() {
    expectEq(OrbAppearance.baseColor(for: .idle), "accent",
             "Idle orb uses semantic accent")
}

@Test
func orbBaseColorForConnectingState() {
    expectEq(OrbAppearance.baseColor(for: .connecting), "accent",
             "Connecting orb uses semantic accent")
}

@Test
func orbBaseColorForListeningState() {
    expectEq(OrbAppearance.baseColor(for: .listening), "accent",
             "Listening orb uses semantic accent")
}

@Test
func orbBaseColorForThinkingState() {
    expectEq(OrbAppearance.baseColor(for: .thinking), "accent",
             "Thinking orb uses semantic accent")
}

@Test
func orbBaseColorForSpeakingState() {
    expectEq(OrbAppearance.baseColor(for: .speaking), "accent",
             "Speaking orb uses semantic accent")
}

@Test
func orbBaseColorForErrorState() {
    expectEq(OrbAppearance.baseColor(for: .error), "destructive",
             "Error orb uses destructive semantic")
}

@Test
func orbCoreGlowIntensityByState() {
    expectEq(OrbAppearance.coreGlowIntensity(for: .idle), 0.7, "Idle: low glow")
    expectEq(OrbAppearance.coreGlowIntensity(for: .connecting), 0.5,
             "Connecting: lower glow")
    expectEq(OrbAppearance.coreGlowIntensity(for: .listening), 1.15,
             "Listening: high glow")
    expectEq(OrbAppearance.coreGlowIntensity(for: .thinking), 0.95,
             "Thinking: medium glow")
    expectEq(OrbAppearance.coreGlowIntensity(for: .speaking), 1.25,
             "Speaking: highest glow")
    expectEq(OrbAppearance.coreGlowIntensity(for: .error), 0.6, "Error: low glow")
}

@Test
func orbAnimationSpeedByState() {
    expectEq(OrbAppearance.animationSpeed(for: .idle), 26.0, "Idle: slow breathing")
    expectEq(OrbAppearance.animationSpeed(for: .connecting), 55.0,
             "Connecting: medium")
    expectEq(OrbAppearance.animationSpeed(for: .listening), 78.0, "Listening: fast")
    expectEq(OrbAppearance.animationSpeed(for: .thinking), 145.0,
             "Thinking: very fast")
    expectEq(OrbAppearance.animationSpeed(for: .speaking), 95.0, "Speaking: reactive")
    expectEq(OrbAppearance.animationSpeed(for: .error), 14.0, "Error: very slow")
}

@Test
func levelNormalizationAndScaling() {
    // Level 0 should map to no scale
    expectEq(OrbAppearance.scaleFromLevel(0), 1.0, "Level 0: no scale")

    // Level 1 (max) should scale by ~11%
    let maxScale = OrbAppearance.scaleFromLevel(1)
    #expect(maxScale > 1.1 && maxScale < 1.12,
            Comment(rawValue: "Level 1: ~11% scale"))

    // Mid level
    let midScale = OrbAppearance.scaleFromLevel(0.5)
    #expect(midScale > 1.05 && midScale < 1.06,
            Comment(rawValue: "Level 0.5: ~5.5% scale"))

    // Values above 1 are clamped
    let clampedScale = OrbAppearance.scaleFromLevel(2)
    expectEq(clampedScale, maxScale, "Level 2: clamped to max")

    // Negative values are clamped
    let negativeScale = OrbAppearance.scaleFromLevel(-1)
    expectEq(negativeScale, 1.0, "Level -1: clamped to min")
}

@Test
func orbOpacityInIdleState() {
    expectEq(OrbAppearance.opacity(for: .idle), 0.82, "Idle: dim")
    expectEq(OrbAppearance.opacity(for: .connecting), 1.0, "Connecting: full")
    expectEq(OrbAppearance.opacity(for: .listening), 1.0, "Listening: full")
    expectEq(OrbAppearance.opacity(for: .thinking), 1.0, "Thinking: full")
    expectEq(OrbAppearance.opacity(for: .speaking), 1.0, "Speaking: full")
    expectEq(OrbAppearance.opacity(for: .error), 1.0, "Error: full")
}

@Test
func reducedMotionDisablesAnimation() {
    let normalSpeed = OrbAppearance.effectiveAnimationSpeed(
        for: .listening,
        reduceMotion: false
    )
    expectEq(normalSpeed, 78.0, "Normal: full animation speed")

    let reducedSpeed = OrbAppearance.effectiveAnimationSpeed(
        for: .listening,
        reduceMotion: true
    )
    expectEq(reducedSpeed, 0.0, "Reduced motion: no animation speed")
}

@Test
func shellAnimationDisabledInReducedMotionAndIdle() {
    #expect(!OrbAppearance.shouldAnimateShell(for: .idle, reduceMotion: false),
            Comment(rawValue: "Idle: no shell animation even with motion enabled"))

    #expect(OrbAppearance.shouldAnimateShell(for: .listening, reduceMotion: false),
            Comment(rawValue: "Listening: shell animates with motion enabled"))

    #expect(!OrbAppearance.shouldAnimateShell(for: .listening, reduceMotion: true),
            Comment(rawValue: "Listening: no shell animation with reduced motion"))
}
