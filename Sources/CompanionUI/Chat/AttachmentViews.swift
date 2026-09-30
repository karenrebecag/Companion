import SwiftUI

struct DropVeil: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Semantic.scrim)
                .ignoresSafeArea()
            VStack(spacing: Space.x2) {
                Image(systemName: "arrow.down.doc")
                    .font(Fonts.sans(IconSize.hero).weight(.light))
                    .foregroundStyle(Semantic.foreground)
                Text(Localized.string("attach.drop.title"))
                    .font(.uiTitle)
                    .foregroundStyle(Semantic.foreground)
                Text(Localized.string("attach.drop.subtitle"))
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
            }
            .padding(Space.x6)
        }
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}
