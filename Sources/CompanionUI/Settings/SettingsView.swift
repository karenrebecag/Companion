import AppKit
import CompanionCore
import CompanionUIPro
import SwiftUI

package enum SettingsOverlayMetrics {
    /// The history overlay still uses the old square bound.
    package static let maxSide: CGFloat = 560
    package static let cardHeight: CGFloat = 68
    package static let avatar: CGFloat = Space.x8 + Space.x1
    package static let bigAvatar: CGFloat = 56
    package static let stepHit: CGFloat = Space.x8
}

/// Settings: one page at a time, with the Arc Pro section nav and the
/// settings palette on top. Each page owns its state; this view owns only
/// where you are and which row a palette pick asked to show.
package struct SettingsView: View {
    private let preview: VoicePreview?
    var chat: ChatViewModel?
    var welcome: WelcomeModel?
    var memory: (any MemoryBrowsing)?
    var browser: BrowserSettingsModel?
    let onClose: () -> Void
    @Binding var tab: SettingsTab
    @Binding var query: String
    @State private var confirmPurge = false
    @State private var history = HistoryClearModel()
    @State private var storageLabel = Localized.string("settings.storage.empty")
    /// Bumped on a language change: every string on screen repaints at once.
    @State private var languageTick = 0
    /// The row a palette pick asked to show, and the nonce that makes a repeat pick count again.
    @State private var reveal: SettingsReveal?
    @Environment(DropdownHost.self) private var dropdowns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let updates: UpdateState?

    package init(
        preview: VoicePreview? = nil,
        chat: ChatViewModel? = nil,
        updates: UpdateState? = nil,
        welcome: WelcomeModel? = nil,
        memory: (any MemoryBrowsing)? = nil,
        browser: BrowserSettingsModel? = nil,
        tab: Binding<SettingsTab> = .constant(.general),
        query: Binding<String> = .constant(""),
        onClose: @escaping () -> Void = {}
    ) {
        self.preview = preview
        self.chat = chat
        self.welcome = welcome
        self.memory = memory
        self.browser = browser
        self.updates = updates
        self._tab = tab
        self._query = query
        self.onClose = onClose
    }

    package var body: some View {
        sheetBody
        .overlay {
            if dropdowns.session.isOpen, case .settingsPick = dropdowns.menu {
                Color.black.opacity(0.001)
                    .onTapGesture {
                        withAnimation(ChromeMotion.animation(.springSheet, reduceMotion: reduceMotion)) { dropdowns.dismiss() }
                    }
            }
        }
        .overlay { purgeConfirm }
        .overlay { HistoryClearDialog(model: history, chat: chat) }
        .dropdownPortal(host: dropdowns)
        .onDisappear {
            dropdowns.dismiss()
        }
        .onAppear { refreshStorage() }
    }

    /// The palette above, the section nav and page below.
    private var sheetBody: some View {
        VStack(alignment: .leading, spacing: Space.none) {
            HStack(spacing: Space.none) {
                SettingsCommand(
                    query: $query, items: SettingsInventory.commandItems,
                    sectionTitle: { SettingsTab(rawValue: $0)?.title ?? "" },
                    strings: SettingsPageChrome.commandStrings, onPick: jump)
                Spacer(minLength: Space.none)
            }
            .padding(.leading, Space.x4)
            .padding(.top, Space.x3)
            .padding(.trailing, SettingsCloseClearance.width)
            .zIndex(1)
            SettingsPage(
                sections: SettingsTab.allCases.map(\.pageSection),
                selection: tabSelection,
                reveal: reveal,
                strings: SettingsPageChrome.pageStrings,
                style: .companion,
                content: { section in page(section) })
        }
        .background(Semantic.background)
    }

    @ViewBuilder private func page(_ section: SettingsPageSection) -> some View {
        Group {
            pageBody(SettingsTab(rawValue: section.id) ?? .general)
        }
        .id(languageTick)
    }

    @ViewBuilder private func pageBody(_ tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            SettingsGeneralPage(accessibility: chat?.accessibility, onLanguageChange: languageChanged)
        case .voice:
            SettingsVoiceSection(preview: preview, secrets: chat?.secrets)
        case .vocabulary:
            SettingsVocabularyPage()
        case .memory:
            SettingsMemoryPage(memory: memory)
        case .you:
            SettingsYouPage()
        case .privacy:
            SettingsPrivacyPage(chat: chat, welcome: welcome, browser: browser)
        case .system:
            SettingsSystemPage(
                chat: chat, updates: updates, welcome: welcome, storageLabel: storageLabel,
                confirmPurge: $confirmPurge, onClose: onClose, onAppear: refreshStorage,
                history: history)
        }
    }

    private var tabSelection: Binding<String> {
        Binding(
            get: { tab.rawValue },
            set: { if let next = SettingsTab(rawValue: $0) { tab = next } })
    }

    /// A palette pick opens its page and, for a row, asks the page to bring
    /// that row into view. A page entry has no row, so it stops at the top.
    private func jump(_ item: SettingsCommandItem) {
        guard let target = SettingsTab(rawValue: item.sectionID) else { return }
        dropdowns.dismiss()
        withAnimation(ChromeMotion.animation(.springSelect, reduceMotion: reduceMotion)) { tab = target }
        let isPage = item.id.hasPrefix("settings.tab.")
        reveal = isPage ? nil : SettingsReveal(anchor: item.id, nonce: (reveal?.nonce ?? 0) + 1)
    }

    private func languageChanged() {
        languageTick += 1
        NotificationCenter.default.post(name: .companionLanguageDidChange, object: nil)
    }

    private func refreshStorage() {
        storageLabel = chat?.attachmentsStorageLabel ?? Localized.string("settings.storage.empty")
    }

    @ViewBuilder
    private var purgeConfirm: some View {
        if confirmPurge {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Semantic.scrim)
                    .onTapGesture { confirmPurge = false }
                VStack(alignment: .leading, spacing: Space.x3) {
                    Text(Localized.string("settings.purge.title"))
                        .font(.uiSubtitle)
                        .foregroundStyle(Semantic.foreground)
                    Text(String(format: Localized.string("settings.purge.blurb"), storageLabel))
                        .font(.uiCaption)
                        .foregroundStyle(Semantic.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: Space.x2) {
                        Spacer()
                        SettingsPill(title: Localized.string("settings.purge.cancel")) { confirmPurge = false }
                        SettingsPill(title: Localized.string("settings.purge.confirm"), kind: .destructive) {
                            chat?.purgeStoredAttachments()
                            refreshStorage()
                            confirmPurge = false
                        }
                    }
                }
                .padding(Space.x5)
                .frame(maxWidth: Container.sheet)
                .background(
                    RoundedRectangle(cornerRadius: Radius.card)
                        .fill(Semantic.surfaceOverlay)
                        .elevation(.sheet))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card)
                        .stroke(Semantic.border, lineWidth: Stroke.hairline))
            }
        }
    }
}

/// The sheet's close button sits in the top corner; the palette keeps clear of it.
enum SettingsCloseClearance {
    static let width: CGFloat = 64
}

enum SettingsVersion {
    static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? Localized.string("settings.app.version.unknown")
    }
}

#if DEBUG
#Preview {
    SettingsView(onClose: {})
        .environment(DropdownHost())
        .frame(width: SettingsSheetMetrics.maxWidth, height: SettingsSheetMetrics.maxHeight)
}
#endif
