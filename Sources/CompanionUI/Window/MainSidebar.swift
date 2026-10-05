import CompanionCore
import SwiftUI

/// The main window as Incredible draws it (spec 16j §8): a sidebar and a
/// page. The new modules hang in the sidebar but route to a single
/// text-only page until they have their own waves.
package enum MainPage: Hashable {
    case home
    /// 16k-1: under "Customize", as in Incredible.
    case apps
    case browser
    case knowledge
    case savedTasks
    case scheduled
    case autopilot
    case dictation
}

/// Only what the window's sheets size themselves by. The sidebar and avatar
/// live in `SidebarMetrics` (248 and 28, measured); a second copy here read
/// 220 and nothing used it. The detail sheet's 860 x 620 and its 220 side
/// column are Companion's own: Incredible's task detail was never measured.
package enum MainWindowMetrics {
    package static let detailMaxWidth: CGFloat = 860
    package static let detailMaxHeight: CGFloat = 620
    package static let detailSide: CGFloat = 220
}

package extension Notification.Name {
    /// Follow up (spec 16j §8): the window steps aside and the island takes
    /// the task. The app layer hides the window; the UI never does.
    static let companionFollowUp = Notification.Name("companion.followUp")
}

/// What fills the pane on the right of the sidebar. Home and apps have
/// their own views; the six new modules share one text-only placeholder.
/// `.apps` only returns when the apps service is configured; the empty
/// placeholder had no copy and stranded the user on a blank screen.
enum DetailPane: Equatable {
    case home
    case apps
    case placeholder(MainPage)
}

extension DetailPane {
    static func detailPane(for page: MainPage, appsAvailable: Bool) -> DetailPane {
        switch page {
        case .home: return .home
        case .apps: return appsAvailable ? .apps : .home
        case .browser, .knowledge, .savedTasks, .scheduled, .autopilot, .dictation:
            return .placeholder(page)
        }
    }
}

/// Everything the placeholder page needs for one sidebar module, built
/// once by `MainSidebar.placeholder(for:)`. Non-optional so the view
/// cannot be asked to render a page that has no copy of its own.
struct ModulePlaceholder: Equatable {
    let page: MainPage
    let symbol: String
    let titleKey: String
    let bodyKey: String
}

struct MainSidebar: View {
    @Binding var page: MainPage
    let onSettings: () -> Void
    let onFeedback: () -> Void
    @State private var avatarImage = UserProfile.avatarImage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One sidebar row: a page, its SF Symbol, the catalog key for its
    /// title, and the catalog key for the body the placeholder page shows
    /// (nil for home and apps, which have their own views). Symbols live
    /// here so the test can compare them to the spec without parsing the
    /// body, and the body key lives here so the placeholder never has to
    /// re-derive it.
    struct Entry: Hashable {
        let page: MainPage
        let symbol: String
        let titleKey: String
        let bodyKey: String?
    }

    /// A heading plus the entries under it. The home section has no
    /// heading, which is why headingKey is optional.
    struct Section: Hashable {
        let headingKey: String?
        let entries: [Entry]
    }

    /// The single source of truth: every section the sidebar draws.
    /// Tests assert against this so a new page can't sneak in without a
    /// symbol, a key, a heading slot and a body key.
    static let sections: [Section] = [
        Section(headingKey: nil, entries: [
            Entry(page: .home, symbol: "house", titleKey: "sidebar.home", bodyKey: nil)
        ]),
        Section(headingKey: "sidebar.customize", entries: [
            Entry(page: .apps, symbol: "square.grid.2x2", titleKey: "sidebar.apps", bodyKey: nil),
            Entry(page: .browser, symbol: "globe", titleKey: "sidebar.browser", bodyKey: "placeholder.browser.body"),
            Entry(page: .knowledge, symbol: "book", titleKey: "sidebar.knowledge", bodyKey: "placeholder.knowledge.body"),
        ]),
        Section(headingKey: "sidebar.superpowers", entries: [
            Entry(page: .savedTasks, symbol: "cursorarrow.rays", titleKey: "sidebar.savedTasks", bodyKey: "placeholder.savedTasks.body"),
            Entry(page: .scheduled, symbol: "clock", titleKey: "sidebar.scheduled", bodyKey: "placeholder.scheduled.body"),
            Entry(page: .autopilot, symbol: "scope", titleKey: "sidebar.autopilot", bodyKey: "placeholder.autopilot.body"),
            Entry(page: .dictation, symbol: "mic", titleKey: "sidebar.dictation", bodyKey: "placeholder.dictation.body"),
        ]),
    ]

    /// The SF Symbol a sidebar row shows for `page`. Returning nil keeps
    /// the placeholder's caller honest: a page with no sidebar entry has
    /// no icon to draw.
    static func symbol(for page: MainPage) -> String? {
        for section in sections {
            for entry in section.entries where entry.page == page {
                return entry.symbol
            }
        }
        return nil
    }

    /// The full description the placeholder page needs for `page`. Returns
    /// nil for pages with their own view (home, apps) and for any page the
    /// sidebar does not list, so the caller can route the navigation back
    /// to home instead of building an empty placeholder.
    static func placeholder(for page: MainPage) -> ModulePlaceholder? {
        for section in sections {
            for entry in section.entries where entry.page == page {
                guard let bodyKey = entry.bodyKey else { return nil }
                return ModulePlaceholder(
                    page: entry.page,
                    symbol: entry.symbol,
                    titleKey: entry.titleKey,
                    bodyKey: bodyKey)
            }
        }
        return nil
    }

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
            VStack(alignment: .leading, spacing: Space.none) {
                ForEach(MainSidebar.sections, id: \.self) { section in
                    sectionRows(section)
                }
            }
            .padding(.top, Space.x3)
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

    /// The heading lives on the section, not on every row: a future
    /// heading-only section still reads as a group label.
    @ViewBuilder
    private func sectionRows(_ section: Section) -> some View {
        if let headingKey = section.headingKey {
            sectionHeading(headingKey)
        }
        ForEach(section.entries, id: \.page) { entry in
            row(entry.page, symbol: entry.symbol, title: Localized.string(entry.titleKey))
        }
    }

    private func sectionHeading(_ key: String) -> some View {
        Text(Localized.string(key))
            .font(.uiCaption.weight(.medium))
            .foregroundStyle(Semantic.textMuted)
            .padding(.leading, SidebarMetrics.logoLeading)
            .padding(.top, Space.x5)
            .padding(.bottom, Space.x1)
    }

    private func row(_ target: MainPage, symbol: String, title: String) -> some View {
        SidebarRow(symbol: symbol, title: title, selected: page == target) {
            withAnimation(ChromeMotion.animation(.springSelect, reduceMotion: reduceMotion)) { page = target }
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
                    .font(Fonts.sans(SidebarMetrics.chevron * 0.7).weight(.semibold))
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
                    .font(Fonts.sans(SidebarMetrics.icon * 0.85))
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
