import SwiftUI

// Wave 16l-3: Incredible's cards — the plain elevated card, the action card
// whose colour halo follows the pointer, and the status dot. Measurements from docs/research/incredible-componentes.md.

package enum CardChrome {
    package static let radius: CGFloat = Radius.lg
    package static let padding: CGFloat = Space.x4
}

package enum ActionCardMetrics {
    package static let paddingTop: CGFloat = Space.x6
    package static let paddingX: CGFloat = Space.x6
    package static let paddingBottom: CGFloat = 26
    package static let gap: CGFloat = Space.x6
    package static let radius: CGFloat = Radius.panel
    /// The halo is wider than the card so its edge never shows.
    package static let haloWidth: CGFloat = 1.3
    package static let haloRest = 0.6
    package static let haloHover = 1.0
    package static let haloDuration = 0.9
    /// The gradient reaches transparent at 72 % of its radius.
    static let haloFade: CGFloat = 0.72
}

package enum ActionCardHalo {
    /// Where the halo sits: under the pointer while it is inside the card,
    /// otherwise resting on the top-trailing corner.
    package static func center(pointer: CGPoint?, in size: CGSize) -> CGPoint {
        guard let pointer,
              pointer.x >= 0, pointer.y >= 0,
              pointer.x <= size.width, pointer.y <= size.height
        else { return CGPoint(x: size.width, y: 0) }
        return pointer
    }
}

/// A white card with a soft colour field that trails the pointer.
package struct ActionCard<Content: View>: View {
    let accent: Color
    @ViewBuilder let content: () -> Content

    @State private var pointer: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    package init(accent: Color, @ViewBuilder content: @escaping () -> Content) {
        self.accent = accent
        self.content = content
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: ActionCardMetrics.gap) {
            content()
        }
        .padding(.top, ActionCardMetrics.paddingTop)
        .padding(.horizontal, ActionCardMetrics.paddingX)
        .padding(.bottom, ActionCardMetrics.paddingBottom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { proxy in
                let side = proxy.size.width * ActionCardMetrics.haloWidth
                let center = ActionCardHalo.center(pointer: pointer, in: proxy.size)
                Circle()
                    .fill(RadialGradient(
                        colors: [accent, accent.opacity(0)],
                        center: .center, startRadius: 0,
                        endRadius: side / 2 * ActionCardMetrics.haloFade))
                    .frame(width: side, height: side)
                    .position(center)
                    .opacity(pointer == nil ? ActionCardMetrics.haloRest : ActionCardMetrics.haloHover)
            }
            .background(Semantic.surface)
            .clipShape(RoundedRectangle(cornerRadius: ActionCardMetrics.radius))
            .accessibilityHidden(true)
        }
        .overlay(RoundedRectangle(cornerRadius: ActionCardMetrics.radius)
            .strokeBorder(Semantic.borderChrome, lineWidth: Stroke.hairline))
        .elevation(.hover)
        .onContinuousHover { phase in
            let next: CGPoint? = switch phase {
            case .active(let location): location
            case .ended: nil
            }
            if reduceMotion { pointer = next; return }
            withAnimation(MotionCurve.animation(MotionCurve.settle, ActionCardMetrics.haloDuration)) {
                pointer = next
            }
        }
    }
}

/// An 8 pt status light.
package struct StatusDot: View {
    package static let side: CGFloat = 8
    let color: Color

    package init(_ color: Color) { self.color = color }

    package var body: some View {
        Circle().fill(color).frame(width: Self.side, height: Self.side)
            .accessibilityHidden(true)
    }
}
