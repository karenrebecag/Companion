import SwiftUI

// Wave 16n: Incredible's main window — Home, the task list and the sidebar —
// and the island field, measured in docs/research/incredible-ui-detalle.md
// and in Karen's 20:13 screenshots.

public enum HomeMetrics {
    public static let maxWidth: CGFloat = 1300
    public static let paddingX: CGFloat = Space.x10
    public static let paddingBottom: CGFloat = 64
    public static let headHeight: CGFloat = 98
    public static let headTop: CGFloat = Space.x2_5
    public static let sideColumn: CGFloat = 300
    public static let columnGap: CGFloat = Space.x8
    public static let tasksTop: CGFloat = Space.x10
    public static let groupGap: CGFloat = Space.section
}

public enum HeroMetrics {
    public static let radius: CGFloat = Radius.card
    public static let paddingX: CGFloat = Space.x10
    public static let paddingY: CGFloat = Space.x6
    public static let ink = Swatch("171310")
    public static let bodyAlpha = 0.75
    public static let titleLeading: CGFloat = 1.25
    /// The keycap sits at 1.25 × the title size.
    public static let keycapScale: CGFloat = 1.25
    /// The body wraps at 34 characters.
    static let bodyWidth: CGFloat = 300
}

/// The brand keycap as Incredible draws it in the hero, in em of its own
/// font size (which is 0.54 of the text around it).
public enum BrandKeycap {
    public static let fontScale: CGFloat = 0.54
    public static let heightEm: CGFloat = 1.8
    public static let minWidthEm: CGFloat = 2.4
    public static let paddingEm: CGFloat = 0.45
    public static let radiusEm: CGFloat = 0.45
    public static let border = Swatch("C9C9CF")
    public static let top = Swatch("FFFFFF")
    public static let bottom = Swatch("F1F1F4")
    static let drop = Swatch("BDBDC4")
}

public enum TaskRowMetrics {
    public static let paddingX: CGFloat = Space.indent
    public static let paddingY: CGFloat = Space.x3_5
    public static let gap: CGFloat = Space.x4
    public static let icon: CGFloat = Space.x6
    public static let chevron: CGFloat = Space.x4
    public static let dividerInset: CGFloat = Space.indent
    public static let listRadius: CGFloat = Radius.card
    public static let listPaddingY: CGFloat = Space.x1
}

public enum SidebarMetrics {
    public static let width: CGFloat = 248
    public static let titleBar: CGFloat = 38
    public static let logoRow: CGFloat = 44
    public static let logoLeading: CGFloat = 19
    public static let trailing: CGFloat = Space.x3_5
    public static let itemRow: CGFloat = 42
    public static let itemHeight: CGFloat = 38
    public static let itemRadius: CGFloat = Radius.chip
    public static let itemPaddingX: CGFloat = Space.x3
    public static let itemGap: CGFloat = Space.x3
    public static let icon: CGFloat = 18
    public static let groupTop: CGFloat = Space.x7
    public static let groupBottom: CGFloat = Space.x1_5
    public static let groupLeading: CGFloat = Space.x6
    public static let accountRow: CGFloat = 54
    public static let accountTrigger: CGFloat = 42
    public static let avatar: CGFloat = 28
    public static let chevron: CGFloat = 15
    public static let selectedAlpha = 0.07
    public static let monogramFill = Swatch("C8DCF1")
}

public enum IslandFieldMetrics {
    public static let height: CGFloat = 38
    public static let radius: CGFloat = 12
    public static let textInset: CGFloat = Space.x3_5
    public static let fill = 0.075
    public static let orb: CGFloat = 36
    public static let orbGap: CGFloat = Space.x2
    public static let send: CGFloat = 28
    public static let tool: CGFloat = 30
    public static let trailing: CGFloat = 5
    public static let sendFill = 0.13
}

public enum Monogram {
    public static func letter(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }
}

/// The key drawn inside the hero title: white-to-grey face, a darker lip.
/// The brand variant of `Keycap`, kept apart on purpose: its face is
/// Incredible's measured hero key (a gradient and a hard drop, sized in em
/// of the title it sits in), not the component cap the rows and the
/// welcome use.
public struct BrandKeycapView: View {
    let text: String
    /// The size of the title it sits in.
    let titleSize: CGFloat

    /// The key's own rendered size: scaled once, exactly as its font is.
    public static func em(titleSize: CGFloat) -> CGFloat {
        TypeScale.apply(titleSize * HeroMetrics.keycapScale * BrandKeycap.fontScale)
    }

    public var body: some View {
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
