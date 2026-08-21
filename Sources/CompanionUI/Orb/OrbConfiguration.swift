import SwiftUI

public struct OrbConfiguration {
    public let glowColor: Color
    public let backgroundColors: [Color]
    public let particleColor: Color
    public let showBackground: Bool
    public let showWavyBlobs: Bool
    public let showParticles: Bool
    public let showGlowEffects: Bool
    public let showShadow: Bool
    public let coreGlowIntensity: Double
    public let speed: Double

    public init(
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
