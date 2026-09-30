import SwiftUI

package struct OrbConfiguration {
    package let glowColor: Color
    package let backgroundColors: [Color]
    package let particleColor: Color
    package let showBackground: Bool
    package let showWavyBlobs: Bool
    package let showParticles: Bool
    package let showGlowEffects: Bool
    package let showShadow: Bool
    package let coreGlowIntensity: Double
    package let speed: Double

    package init(
        backgroundColors: [Color] = [.green, .blue, .pink],
        glowColor: Color = .white,
        coreGlowIntensity: Double = 1.0,
        showBackground: Bool = true,
        showWavyBlobs: Bool = true,
        showParticles: Bool = true,
        showGlowEffects: Bool = true,
        showShadow: Bool = true,
        speed: Double = 60
    ) {
        self.backgroundColors = backgroundColors
        self.glowColor = glowColor
        self.particleColor = .white
        self.coreGlowIntensity = coreGlowIntensity
        self.showBackground = showBackground
        self.showWavyBlobs = showWavyBlobs
        self.showParticles = showParticles
        self.showGlowEffects = showGlowEffects
        self.showShadow = showShadow
        self.speed = speed
    }
}
