import CompanionCore
import SwiftUI

/// Home's "hold fn" card. Incredible lays a photo over its right side; ours
/// carries Space UI's orb there, which shows what the voice is doing.
struct HomeHero: View {
    let state: TurnState
    var paused = false

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
            ThinkingOrb(mode: ThinkingOrbMode(state: state), surface: .ink, size: HeroMetrics.orbSize, paused: paused)
        }
        .padding(.horizontal, HeroMetrics.paddingX)
        .padding(.vertical, HeroMetrics.paddingY)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: HeroMetrics.radius).fill(HeroMetrics.ink.color))
    }
}
