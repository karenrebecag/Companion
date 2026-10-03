import SwiftUI

// shadcn's Badge (new-york-v4), in Companion's scales: a capsule, px-2
// py-0.5, text-xs medium. The hover states of the source only apply to
// badges that are links, which Companion's status tags never are.

package enum BadgeMetrics {
    package static let paddingX: CGFloat = Space.x2
    package static let paddingY: CGFloat = Space.x0_5
    package static let gap: CGFloat = Space.x1
    package static let fontSize: CGFloat = TypeSize.caption
}

package enum BadgeVariant: Sendable, CaseIterable {
    case `default`, secondary, destructive, outline, ghost, link

    package var background: Color {
        switch self {
        case .default: Semantic.primary
        case .secondary: Semantic.muted
        case .destructive: Semantic.destructive
        case .outline, .ghost, .link: Color.clear
        }
    }

    package var foreground: Color {
        switch self {
        case .default: Semantic.primaryForeground
        case .destructive: Semantic.destructiveForeground
        case .secondary, .outline, .ghost: Semantic.foreground
        case .link: Semantic.primary
        }
    }

    package var border: Color? {
        self == .outline ? Semantic.borderStrong : nil
    }
}

package struct Badge: View {
    let title: String
    let variant: BadgeVariant
    let dot: Color?

    /// `dot` adds a status light before the label, for state tags.
    package init(_ title: String, variant: BadgeVariant = .default, dot: Color? = nil) {
        self.title = title
        self.variant = variant
        self.dot = dot
    }

    package var body: some View {
        HStack(spacing: BadgeMetrics.gap) {
            if let dot { StatusDot(dot) }
            Text(title)
        }
        .font(Fonts.sans(BadgeMetrics.fontSize).weight(.medium))
        .lineLimit(1)
        .foregroundStyle(variant.foreground)
        .padding(.horizontal, BadgeMetrics.paddingX)
        .padding(.vertical, BadgeMetrics.paddingY)
        .background(Capsule().fill(variant.background))
        .overlay {
            if let border = variant.border {
                Capsule().stroke(border, lineWidth: Stroke.hairline)
            }
        }
    }
}
