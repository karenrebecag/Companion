import SwiftUI

// Wave 16n: Incredible's main window — Home, the task list and the sidebar —
// and the island field, measured in docs/research/incredible-ui-detalle.md
// and in Karen's 20:13 screenshots.

package enum HomeMetrics {
    package static let maxWidth: CGFloat = 1300
    package static let paddingX: CGFloat = Space.x10
    package static let paddingBottom: CGFloat = 64
    package static let headHeight: CGFloat = 98
    package static let headTop: CGFloat = Space.x2_5
    package static let sideColumn: CGFloat = 300
    package static let columnGap: CGFloat = Space.x8
    package static let tasksTop: CGFloat = Space.x10
    package static let groupGap: CGFloat = Space.section
}

package enum HeroMetrics {
    package static let radius: CGFloat = Radius.card
    package static let paddingX: CGFloat = Space.x10
    package static let paddingY: CGFloat = Space.x6
    package static let ink = Swatch("171310")
    package static let bodyAlpha = 0.75
    package static let titleLeading: CGFloat = 1.25
    /// The keycap sits at 1.25 × the title size.
    package static let keycapScale: CGFloat = 1.25
    /// The body wraps at 34 characters.
    static let bodyWidth: CGFloat = 300
    /// The orb on the right of the card, at the sheets' hero figure size.
    package static let orbSize: CGFloat = Container.hero
}

/// The brand keycap as Incredible draws it in the hero, in em of its own
/// font size (which is 0.54 of the text around it).
package enum BrandKeycap {
    package static let fontScale: CGFloat = 0.54
    package static let heightEm: CGFloat = 1.8
    package static let minWidthEm: CGFloat = 2.4
    package static let paddingEm: CGFloat = 0.45
    package static let radiusEm: CGFloat = 0.45
    package static let border = Swatch("C9C9CF")
    package static let top = Swatch("FFFFFF")
    package static let bottom = Swatch("F1F1F4")
    static let drop = Swatch("BDBDC4")
}

package enum TaskRowMetrics {
    package static let paddingX: CGFloat = Space.indent
    package static let paddingY: CGFloat = Space.x3_5
    package static let gap: CGFloat = Space.x4
    package static let icon: CGFloat = Space.x6
    package static let chevron: CGFloat = Space.x4
    package static let dividerInset: CGFloat = Space.indent
    package static let listRadius: CGFloat = Radius.card
    package static let listPaddingY: CGFloat = Space.x1
}

package enum SidebarMetrics {
    package static let width: CGFloat = 248
    package static let titleBar: CGFloat = 38
    package static let logoRow: CGFloat = 44
    package static let logoLeading: CGFloat = 19
    package static let trailing: CGFloat = Space.x3_5
    package static let itemRow: CGFloat = 42
    package static let itemHeight: CGFloat = 38
    package static let itemRadius: CGFloat = Radius.chip
    package static let itemPaddingX: CGFloat = Space.x3
    package static let itemGap: CGFloat = Space.x3
    package static let icon: CGFloat = 18
    package static let groupTop: CGFloat = Space.x7
    package static let groupBottom: CGFloat = Space.x1_5
    package static let groupLeading: CGFloat = Space.x6
    package static let accountRow: CGFloat = 54
    package static let accountTrigger: CGFloat = 42
    package static let avatar: CGFloat = 28
    package static let chevron: CGFloat = 15
    package static let selectedAlpha = 0.07
    package static let monogramFill = Swatch("C8DCF1")
}

package enum IslandFieldMetrics {
    package static let height: CGFloat = 38
    package static let radius: CGFloat = 12
    package static let textInset: CGFloat = Space.x3_5
    package static let fill = 0.075
    package static let orb: CGFloat = 36
    package static let orbGap: CGFloat = Space.x2
    package static let send: CGFloat = 28
    package static let tool: CGFloat = 30
    package static let trailing: CGFloat = 5
    package static let sendFill = 0.13
}

package enum Monogram {
    package static func letter(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }
}

/// The key drawn inside the hero title: white-to-grey face, a darker lip.
/// The brand variant of `Keycap`, kept apart on purpose: its face is
/// Incredible's measured hero key (a gradient and a hard drop, sized in em
/// of the title it sits in), not the component cap the rows and the
/// welcome use.
package struct BrandKeycapView: View {
    let text: String
    /// The size of the title it sits in.
    let titleSize: CGFloat

    /// The key's own rendered size: scaled once, exactly as its font is.
    package static func em(titleSize: CGFloat) -> CGFloat {
        TypeScale.apply(titleSize * HeroMetrics.keycapScale * BrandKeycap.fontScale)
    }

    package var body: some View {
        let em = Self.em(titleSize: titleSize)
        Text(text)
            .font(Fonts.sans(titleSize * HeroMetrics.keycapScale * BrandKeycap.fontScale).weight(.semibold))
            .tracking(Tracking.snug * em)
            .foregroundStyle(Neutral.black.color)
            .padding(.horizontal, em * BrandKeycap.paddingEm)
            .frame(minWidth: em * BrandKeycap.minWidthEm, minHeight: em * BrandKeycap.heightEm)
            .background(RoundedRectangle(cornerRadius: em * BrandKeycap.radiusEm)
                .fill(LinearGradient(colors: [BrandKeycap.top.color, BrandKeycap.bottom.color],
                                     startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: em * BrandKeycap.radiusEm)
                .strokeBorder(BrandKeycap.border.color, lineWidth: Stroke.hairline))
            .shadow(color: BrandKeycap.drop.color, radius: 0, y: em * 0.16)
            .shadow(color: .black.opacity(0.35), radius: em * 0.3, y: em * 0.3)
    }
}

/// The 24 pt round icon at the start of a task row's second line.
struct TaskChipIcon: View {
    var symbol = "bubble.left"

    var body: some View {
        Image(systemName: symbol)
            .font(Fonts.sans(TaskRowMetrics.icon * 0.5))
            .foregroundStyle(Semantic.faintForeground)
            .frame(width: TaskRowMetrics.icon, height: TaskRowMetrics.icon)
            .background(Circle().fill(Semantic.surface))
            .overlay(Circle().strokeBorder(Semantic.popupBorder, lineWidth: Stroke.hairline))
            .accessibilityHidden(true)
    }
}

/// The user's initial on Incredible's sky disc, when there is no photo.
struct MonogramAvatar: View {
    let name: String

    var body: some View {
        Text(Monogram.letter(name))
            .font(Fonts.sans(SidebarMetrics.avatar * 0.38).weight(.semibold))
            .foregroundStyle(Palette.textPrimary.color)
            .frame(width: SidebarMetrics.avatar, height: SidebarMetrics.avatar)
            .background(Circle().fill(SidebarMetrics.monogramFill.color))
            .accessibilityHidden(true)
    }
}
