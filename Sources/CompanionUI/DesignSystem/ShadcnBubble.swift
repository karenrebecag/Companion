import CompanionCore
import SwiftUI

// shadcn's message and bubble (new-york-v4), in Companion's scales. The
// reactions and header/footer slots of the source have no data behind them
// in Companion's transcript, so they are not ported.

package nonisolated enum MessageAlign: Sendable, Equatable {
    case start, end

    package init(role: TurnRole?) {
        self = role == .user ? .end : .start
    }
}

package enum MessageMetrics {
    package static let gap: CGFloat = Space.x2
}

package enum BubbleMetrics {
    package static let paddingX: CGFloat = Space.x3
    package static let paddingY: CGFloat = Space.x2
    package static let radius: CGFloat = Radius.bubble
    package static let fontSize: CGFloat = TypeSize.rowTitle
    package static let maxWidthFraction: CGFloat = 0.8
}

package enum BubbleVariant: Sendable, Equatable, Hashable, CaseIterable {
    case `default`, secondary, outline, ghost, destructive

    /// The user's turn is the primary bubble, the reply the secondary one.
    package init(role: TurnRole?) {
        self = role == .user ? .default : .secondary
    }

    package var background: Color {
        switch self {
        case .default: Semantic.primary
        case .secondary: Semantic.muted
        case .outline: Semantic.background
        case .ghost: Color.clear
        case .destructive: Semantic.dangerWash
        }
    }

    package var foreground: Color {
        switch self {
        case .default: Semantic.primaryForeground
        case .secondary, .outline, .ghost: Semantic.foreground
        case .destructive: Semantic.destructive
        }
    }

    package var border: Color? {
        self == .outline ? Semantic.border : nil
    }

    package var padded: Bool { self != .ghost }
}

/// The bubble's width rules as plain numbers, so they are testable without
/// a window.
package nonisolated enum BubbleGeometry {
    package static func childWidth(row: CGFloat, fraction: CGFloat) -> CGFloat {
        max(0, row) * fraction
    }

    package static func originX(row: CGFloat, child: CGFloat, align: MessageAlign) -> CGFloat {
        align == .end ? row - child : 0
    }
}

/// Offers its child a fraction of the row and pins it to one edge, which a
/// plain frame cannot do without stretching a short bubble to full width.
private struct BubbleWidth: Layout {
    let fraction: CGFloat
    let align: MessageAlign

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // No width to take a fraction of: behave as the child would alone.
        guard let row = proposal.width else { return subviews[0].sizeThatFits(.unspecified) }
        guard row > 0 else { return .zero }
        let child = subviews[0].sizeThatFits(
            ProposedViewSize(width: BubbleGeometry.childWidth(row: row, fraction: fraction), height: nil))
        return CGSize(width: row, height: child.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let child = subviews[0].sizeThatFits(
            ProposedViewSize(width: BubbleGeometry.childWidth(row: bounds.width, fraction: fraction), height: nil))
        let x = bounds.minX + BubbleGeometry.originX(row: bounds.width, child: child.width, align: align)
        subviews[0].place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: child.width, height: child.height))
    }
}

package struct ChatBubble<Content: View>: View {
    let variant: BubbleVariant
    let align: MessageAlign
    @ViewBuilder let content: Content

    package init(variant: BubbleVariant = .default, align: MessageAlign = .start,
                 @ViewBuilder content: () -> Content) {
        self.variant = variant
        self.align = align
        self.content = content()
    }

    package var body: some View {
        let shape = RoundedRectangle(cornerRadius: BubbleMetrics.radius)
        BubbleWidth(fraction: variant == .ghost ? 1 : BubbleMetrics.maxWidthFraction, align: align) {
            content
                .font(Fonts.sans(BubbleMetrics.fontSize))
                .lineSpacing(Space.x0_5)
                .foregroundStyle(variant.foreground)
                .padding(.horizontal, variant.padded ? BubbleMetrics.paddingX : Space.none)
                .padding(.vertical, variant.padded ? BubbleMetrics.paddingY : Space.none)
                .background(shape.fill(variant.background))
                .overlay {
                    if let border = variant.border {
                        shape.stroke(border, lineWidth: Stroke.hairline)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
