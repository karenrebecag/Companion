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

@Test
func orbGlowOpacityByState() {
    expect(OrbAppearance.glowOpacity(for: .listening)
           > OrbAppearance.glowOpacity(for: .idle),
           "listening glow brighter than idle")
    expect(OrbAppearance.glowOpacity(for: .speaking)
           > OrbAppearance.glowOpacity(for: .error),
           "speaking glow brighter than error")
    expect(OrbAppearance.glowOpacity(for: .idle) > 0, "idle still has a glow")
    expect(OrbAppearance.glowOpacity(for: .idle) <= 1, "glow stays in 0...1")
}

@Test
func orbParticleCountRespectsReduceMotion() {
    expect(OrbAppearance.particleCount(for: .thinking, reduceMotion: false) > 0,
           "thinking: particles on")
    expectEq(
        OrbAppearance.particleCount(for: .thinking, reduceMotion: true),
        0,
        "reduce-motion: no particles")
    expect(
        OrbAppearance.particleCount(for: .listening, reduceMotion: false)
            > OrbAppearance.particleCount(for: .idle, reduceMotion: false),
        "listening has more particles than idle")
}

@Test
func orbPressScaleShrinksWhenPressed() {
    expectEq(OrbAppearance.pressScale(false), 1, "rest: identity scale")
    expect(OrbAppearance.pressScale(true) < 1, "press: shrinks")
    expect(OrbAppearance.pressScale(true) > 0.8, "press: not crushed")
}

@Test @MainActor func orbConfigurationMatchesVoiceStateOrb() {
    let accent = Semantic.accent
    let idle = OrbAppearance.configuration(
        for: .idle, accent: accent, reduceMotion: false)
    expect(!idle.showParticles, "idle: sin particulas")
    expectEq(idle.speed, 26, "idle: speed 26")
    expectEq(idle.coreGlowIntensity, 0.7, "idle: glow 0.7")

    let listen = OrbAppearance.configuration(
        for: .listening, accent: accent, reduceMotion: false)
    expect(listen.showParticles, "listening: particulas")
    expectEq(listen.speed, 78, "listening: speed 78")

    let think = OrbAppearance.configuration(
        for: .thinking, accent: accent, reduceMotion: false)
    expect(think.showParticles, "thinking: particulas")
    expectEq(think.speed, 145, "thinking: speed 145")

    let speak = OrbAppearance.configuration(
        for: .speaking, accent: accent, reduceMotion: false)
    expect(speak.showParticles, "speaking: particulas")

    let connecting = OrbAppearance.configuration(
        for: .connecting, accent: accent, reduceMotion: false)
    expect(!connecting.showParticles, "connecting: sin particulas")

    let error = OrbAppearance.configuration(
        for: .error, accent: accent, reduceMotion: false)
    expect(!error.showParticles, "error: sin particulas")
    expectEq(error.speed, 14, "error: speed 14")

    let reduced = OrbAppearance.configuration(
        for: .listening, accent: accent, reduceMotion: true)
    expectEq(reduced.speed, 0, "reduce-motion: speed 0")
    expect(!reduced.showParticles, "reduce-motion: particulas off")
}
