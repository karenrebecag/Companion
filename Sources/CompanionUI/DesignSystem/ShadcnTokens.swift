import SwiftUI

// MARK: - Button Sizes

/// Button size tokens mapping shadcn's size variants to Companion's space scale.
package enum ButtonSize {
    case xs, sm, `default`, lg

    /// Button height in points.
    package var height: CGFloat {
        switch self {
        case .xs: 24
        case .sm: 32
        case .default: 36
        case .lg: 40
        }
    }

    /// Horizontal padding in points.
    package var paddingX: CGFloat {
        switch self {
        case .xs: Space.x2      // 8pt
        case .sm: Space.x3      // 12pt
        case .default: Space.x4 // 16pt
        case .lg: Space.x6      // 24pt
        }
    }

    /// Vertical padding in points.
    package var paddingY: CGFloat {
        switch self {
        case .xs: Space.x0_5     // 2pt
        case .sm: Space.x1       // 4pt
        case .default: Space.x1  // 4pt
        case .lg: Space.x1_5     // 6pt
        }
    }

    /// Font size for button text.
    package var fontSize: CGFloat {
        switch self {
        case .xs: TypeSize.caption      // 12pt
        case .sm: TypeSize.caption      // 12pt
        case .default: TypeSize.body    // 13pt
        case .lg: TypeSize.rowTitle     // 14pt
        }
    }
}

// MARK: - Button Colors

/// Semantic colors for button variants, mapping shadcn's color scheme
/// to Companion's token system.
package enum ButtonColors {
    /// Default: solid primary button (black on light, n50 on dark).
    case `default`
    /// Destructive: red background for dangerous actions.
    case destructive
    /// Outline: bordered button with transparent background.
    case outline
    /// Secondary: muted background button.
    case secondary
    /// Ghost: no background, text-only until hovered.
    case ghost
    /// Link: text-only, underlined on hover.
    case link

    /// Background color for the button (resting state).
    package var background: Color {
        switch self {
        case .default: Semantic.primary
        case .destructive: Semantic.destructive
        case .outline: Color.clear
        case .secondary: Semantic.surfaceSecondary
        case .ghost: Color.clear
        case .link: Color.clear
        }
    }

    /// Foreground color for text/icons (resting state).
    package var foreground: Color {
        switch self {
        case .default: Semantic.primaryForeground
        case .destructive: Semantic.destructiveForeground
        case .outline: Semantic.foreground
        case .secondary: Semantic.foreground
        case .ghost: Semantic.foreground
        case .link: Semantic.primary
        }
    }

    /// Background color on hover.
    package var backgroundHover: Color {
        switch self {
        case .default: Semantic.primary.opacity(0.85)
        case .destructive: Semantic.dangerHover
        case .outline: Semantic.hover
        case .secondary: Semantic.surface
        case .ghost: Semantic.hover
        case .link: Color.clear
        }
    }

    /// Border color; only outline variant uses it.
    package var border: Color? {
        switch self {
        case .outline: Semantic.border
        default: nil
        }
    }
}

// MARK: - Gaps (Icon-text spacing)

/// Gap tokens for spacing between icons and text in components.
package enum Gap {
    package static let xs: CGFloat = Space.x1         // 4pt
    package static let sm: CGFloat = Space.x2         // 8pt
    package static let `default`: CGFloat = Space.x2  // 8pt
}
