import CompanionCore
import SwiftUI

/// Home's "hold fn" card. Incredible lays a photo over its right side; ours
/// carries a still glyph of what the voice is doing (Karen chose performance
/// over the animated sphere, 2026-10-13).
struct HomeHero: View {
    let state: TurnState

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
                // One line: squeezed by the mark, each word broke letter by letter.
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                Text(Localized.string("home.hero.body"))
                    .typeRole(.heroBody)
                    .foregroundStyle(Neutral.white.color.opacity(HeroMetrics.bodyAlpha))
                    .frame(maxWidth: HeroMetrics.bodyWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .layoutPriority(1)
            Spacer(minLength: Space.none)
            Image(systemName: Self.symbol(for: state))
                .font(Fonts.symbol(HeroMetrics.glyph, weight: .medium))
                .foregroundStyle(Neutral.white.color.opacity(HeroMetrics.bodyAlpha))
                // No disc behind it: on this card a disc would read as a button it is not.
                .frame(width: HeroMetrics.mark, height: HeroMetrics.mark)
                .accessibilityLabel(Localized.string(Self.orbLabelKey(for: state)))
        }
        .padding(.horizontal, HeroMetrics.paddingX)
        .padding(.vertical, HeroMetrics.paddingY)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: HeroMetrics.radius).fill(HeroMetrics.ink.color))
    }

    /// Per-state description so VoiceOver can read what the voice is doing
    /// without naming the glyph.
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

    static func symbol(for state: TurnState) -> String {
        switch state {
        case .idle, .connecting: "mic"
        case .listening: "mic.fill"
        case .thinking: "ellipsis"
        case .speaking: "waveform"
        case .error: "exclamationmark.triangle"
        }
    }
}
