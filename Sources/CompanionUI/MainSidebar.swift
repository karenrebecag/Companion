import CompanionCore
import SwiftUI

/// The main window as Incredible draws it (spec 16j §8): a sidebar and a
/// page. Only sections that already do something are listed; the rest of
/// Incredible's arrive with their own waves.
public enum MainPage: Hashable {
    case home
    /// 16k-1: under "Customize", as in Incredible.
    case apps
}

public enum MainWindowMetrics {
    public static let sidebar: CGFloat = 220
    public static let heroHeight: CGFloat = 150
    public static let startWidth: CGFloat = 250
    public static let pageMaxWidth: CGFloat = 720
    public static let detailMaxWidth: CGFloat = 860
    public static let detailMaxHeight: CGFloat = 620
    public static let detailSide: CGFloat = 220
    public static let avatar: CGFloat = 28
}

public extension Notification.Name {
    /// Follow up (spec 16j §8): the window steps aside and the island takes
    /// the task. The app layer hides the window; the UI never does.
    static let companionFollowUp = Notification.Name("companion.followUp")
}

struct MainSidebar: View {
    @Binding var page: MainPage
    let onSettings: () -> Void
    let onFeedback: () -> Void
    @State private var avatarImage = UserProfile.avatarImage

    // 16n: Incredible's sidebar — a #f9f9f9 panel with a #eee edge, the
    // wordmark row, 38 pt rows in a 42 pt band, the account at the bottom.
    var body: some View {
        VStack(alignment: .leading, spacing: Space.none) {
            Text("Companion")  // token-exempt: nombre del producto.
                .font(Fonts.sans(TypeSize.bannerTitle).weight(.semibold))
                .tracking(Tracking.title, at: TypeSize.bannerTitle)
                .foregroundStyle(Semantic.foreground)
                .padding(.leading, SidebarMetrics.logoLeading)
                .padding(.trailing, SidebarMetrics.trailing)
                .frame(height: SidebarMetrics.logoRow)
                .padding(.top, SidebarMetrics.titleBar + Space.x3)
            VStack(spacing: Space.none) {
                row(.home, symbol: "house", title: Localized.string("sidebar.home"))
            }
            .padding(.top, Space.x3)
            Text(Localized.string("sidebar.customize"))
                .font(.uiCaption.weight(.medium))
                .foregroundStyle(Semantic.textMuted)
                .padding(.leading, SidebarMetrics.logoLeading)
                .padding(.top, Space.x5)
                .padding(.bottom, Space.x1)
            row(.apps, symbol: "square.grid.2x2", title: Localized.string("sidebar.apps"))
            Spacer(minLength: Space.x4)
            profile
        }
        .frame(width: SidebarMetrics.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.bottom, Space.x2)
        .background(Semantic.surfaceSecondary)
        .onReceive(NotificationCenter.default.publisher(for: .companionProfileDidChange)) { _ in
            avatarImage = UserProfile.avatarImage
        }
    }

    private func row(_ target: MainPage, symbol: String, title: String) -> some View {
        SidebarRow(symbol: symbol, title: title, selected: page == target) {
            withAnimation(.springSelect) { page = target }
        }
    }

    /// Incredible's profile row opens its menu; ours holds what exists.
    private var profile: some View {
        Menu {
            Button(Localized.string("island.menu.settings"), action: onSettings)
            Button(Localized.string("island.menu.feedback"), action: onFeedback)
        } label: {
            HStack(spacing: Space.x2_5) {
                avatar
                Text(displayName)
                    .font(Fonts.sans(TypeSize.rowTitle).weight(.medium))
                    .foregroundStyle(Semantic.foreground)
                    .lineLimit(1)
                Spacer(minLength: Space.none)
                Image(systemName: "chevron.down")
                    .font(.system(size: SidebarMetrics.chevron * 0.7, weight: .semibold))
                    .frame(width: SidebarMetrics.chevron, height: SidebarMetrics.chevron)
                    .foregroundStyle(Semantic.chevron)
            }
            .padding(.leading, Space.x2)
            .padding(.trailing, Space.x2_5)
            .frame(height: SidebarMetrics.accountTrigger)
            .contentShape(RoundedRectangle(cornerRadius: SidebarMetrics.itemRadius))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .padding(.horizontal, Space.x3_5)
        .frame(height: SidebarMetrics.accountRow)
    }

    private var displayName: String {
        UserProfile.ownerName.isEmpty ? Localized.string("sidebar.you") : UserProfile.ownerName
    }

    private var avatar: some View {
        Group {
            if let avatarImage {
                Image(nsImage: avatarImage).resizable().scaledToFill()
            } else {
                MonogramAvatar(name: displayName)
            }
        }
        .frame(width: SidebarMetrics.avatar, height: SidebarMetrics.avatar)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

/// One sidebar entry: a 38 pt pill in a 42 pt band, 18 pt icon, 14 pt medium;
/// selected sits on black 7 %, hover on 5 %.
struct SidebarRow: View {
    let symbol: String
    let title: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: SidebarMetrics.itemGap) {
                Image(systemName: symbol)
                    .font(.system(size: SidebarMetrics.icon * 0.85))
                    .frame(width: SidebarMetrics.icon, height: SidebarMetrics.icon)
                    .accessibilityHidden(true)
                Text(title).font(Fonts.sans(TypeSize.rowTitle).weight(.medium))
                Spacer(minLength: Space.none)
            }
            .foregroundStyle(Semantic.foreground)
            .padding(.horizontal, SidebarMetrics.itemPaddingX)
            .frame(height: SidebarMetrics.itemHeight)
            .background(RoundedRectangle(cornerRadius: SidebarMetrics.itemRadius).fill(fill))
            .contentShape(RoundedRectangle(cornerRadius: SidebarMetrics.itemRadius))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, SidebarMetrics.trailing)
        .frame(height: SidebarMetrics.itemRow)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var fill: Color {
        if selected { return Semantic.sidebarSelected }
        return hovering ? Semantic.hover : Color.clear
    }
}
