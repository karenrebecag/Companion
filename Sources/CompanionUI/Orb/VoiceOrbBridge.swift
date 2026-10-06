import CompanionCore
import CompanionUIPro
import SwiftUI

// Bridges the host app's turn machine and design tokens into the Arc Pro
// VoiceOrb. The package takes a state and a palette; this file is the one
// place that translates between them, so the orbs in Home and Welcome share
// the same mapping.

extension VoiceOrbState {
    /// `VoiceOrbState` only knows listening/thinking/speaking. The host
    /// machine carries connecting and error on the same line; both sit
    /// visually at rest, so they fall back to `.idle` here. A redrawn
    /// "speech" or "alert" orb would need its own case upstream.
    init(_ state: TurnState) {
        switch state {
        case .listening: self = .listening
        case .thinking: self = .thinking
        case .speaking: self = .speaking
        case .idle, .connecting, .error: self = .idle
        }
    }
}

extension VoiceOrbPalette {
    /// The orb that sits on the Home hero's ink card. Foreground stays
    /// white so the body fills the dark surface; tint follows the user's
    /// chosen highlight so the cloud picks up the brand the picker shows.
    package static let hero: VoiceOrbPalette = VoiceOrbPalette(
        foreground: Neutral.white.color,
        background: HeroMetrics.ink.color,
        // `Semantic.accent` is the picker-driven highlight; it already
        // resolves per color scheme, so the cloud reads on the ink card.
        tint: Semantic.accent,
        // A second cloud tone so the swirl doesn't read as a single hue;
        // `Semantic.success` is the only status token paired by design
        // with the accent.
        tint2: Semantic.success,
        isDark: true
    )

    /// The orb the welcome screens put over the regular window background.
    /// Foreground flips with the scheme so the body stays visible in both
    /// light and dark.
    package static func surface(colorScheme: ColorScheme) -> VoiceOrbPalette {
        VoiceOrbPalette(
            foreground: Semantic.foreground,
            background: Semantic.background,
            tint: Semantic.accent,
            tint2: Semantic.success,
            isDark: colorScheme == .dark
        )
    }
}
