import CompanionCore
import CompanionUIPro
import SwiftUI

/// Home's "hold fn" card. Incredible lays a photo over its right side; ours
/// carries the voice orb there, which shows what the voice is doing.
struct HomeHero: View {
    let state: TurnState
    /// Live mic and agent levels, so the orb moves with the real voice; nil
    /// (previews, tests) lets the orb draw its own speech envelope.
    var levels: VoiceLevels? = nil

    var body: some View {
        HStack(alignment: .center, spacing: Space.x4) {
            VStack(alignment: .leading, spacing: Space.x2) {
                HStack(spacing: Space.x2) {
                    Text(Localized.string("home.hero.before"))
                    BrandKeycapView(text: "fn", titleSize: TypeSize.bannerTitle)
                    Text(Localized.string("home.hero.after"))
                }
                .font(Fonts.sans(TypeSize.bannerTitle).weight(.semibold))
                .tracking(Tracking.title, at: TypeSize.bannerTitle)
                .foregroundStyle(Neutral.white.color)
                Text(Localized.string("home.hero.body"))
                    .typeRole(.heroBody)
                    .foregroundStyle(Neutral.white.color.opacity(HeroMetrics.bodyAlpha))
                    .frame(maxWidth: HeroMetrics.bodyWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Space.none)
            VoiceOrb(
                state: VoiceOrbState(state),
                muted: false,
                inputLevel: levels?.mic,
                outputLevel: levels?.agent,
                size: HeroMetrics.orbSize,
                palette: .hero,
                accessibilityLabel: Localized.string(Self.orbLabelKey(for: state)))
        }
        .padding(.horizontal, HeroMetrics.paddingX)
        .padding(.vertical, HeroMetrics.paddingY)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: HeroMetrics.radius).fill(HeroMetrics.ink.color))
    }

    /// Per-state description so VoiceOver can read what the orb is doing
    /// without naming the colour or the mode.
    static func orbLabelKey(for state: TurnState) -> String {
        switch state {
        case .idle: "home.hero.orb.idle"
        case .listening: "home.hero.orb.listening"
        case .thinking: "home.hero.orb.thinking"
        case .speaking: "home.hero.orb.speaking"
        case .connecting: "home.hero.orb.connecting"
        case .error: "home.hero.orb.error"
        }
    }
}
