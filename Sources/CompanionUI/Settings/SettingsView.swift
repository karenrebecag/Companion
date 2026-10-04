import AppKit
import CompanionCore
import SwiftUI

package enum SettingsOverlayMetrics {
    /// The history overlay still uses the old square bound.
    package static let maxSide: CGFloat = 560
    package static let cardHeight: CGFloat = 68
    package static let avatar: CGFloat = Space.x8 + Space.x1
    package static let bigAvatar: CGFloat = 56
    package static let stepHit: CGFloat = Space.x8
}

/// The content pane beside the rail (Incredible's gutter and header air).
package enum SettingsPaneMetrics {
    package static let leading: CGFloat = Space.x14
    package static let trailing: CGFloat = 96
    package static let top: CGFloat = 44
    package static let bottom: CGFloat = Space.x10
    package static let titleSize: CGFloat = TypeSize.dialogTitle
}

/// Settings (Wave 16g): a sheet with a sidebar and a search, one page at a
/// time. Each page owns its state; this view owns only where you are.
package struct SettingsView: View {
    private let preview: VoicePreview?
    var chat: ChatViewModel?
    var welcome: WelcomeModel?
    var memory: (any MemoryBrowsing)?
    var browser: BrowserSettingsModel?
    let onClose: () -> Void
    @Binding var tab: SettingsTab
    @Binding var query: String
    @State private var band: SettingsBand?
    /// The row a pick is looking for; the nonce restarts the search on a new pick.
    @State private var jumpTarget: String?
    @State private var jumpNonce = 0
    @State private var presentRows: Set<String> = []
    @State private var confirmPurge = false
    @State private var storageLabel = Localized.string("settings.storage.empty")
    /// Bumped on a language change: every string on screen repaints at once.
    @State private var languageTick = 0
    @Environment(DropdownHost.self) private var dropdowns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    private let updates: UpdateState?

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
        .dropdownPortal(host: dropdowns)
        .onDisappear {
            dropdowns.dismiss()
        }
        .onAppear { refreshStorage() }
    }

    /// Sidebar, hairline, page; the sheet host supplies the surface and the close.
    private var sheetBody: some View {
        HStack(spacing: Space.none) {
            SettingsSidebar(tab: $tab, query: $query, onPick: jump, approvalPending: chat?.pendingApproval != nil)
                .frame(width: SettingsRailMetrics.width)
            Rectangle().fill(Semantic.borderChrome).frame(width: Stroke.hairline)
            pageScroll
        }
    }

    private var pageScroll: some View {
        ScrollViewReader { proxy in
            pageContent
                .task(id: jumpNonce) { await findRow(proxy) }
        }
    }

    private var pageContent: some View {
        ScrollView {
            page
                .padding(.leading, SettingsPaneMetrics.leading)
                .padding(.trailing, SettingsPaneMetrics.trailing)
                .padding(.top, SettingsPaneMetrics.top)
                .padding(.bottom, SettingsPaneMetrics.bottom)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id("\(tab.rawValue)-\(languageTick)")
                .transition(ChromeMotion.transition(.modeSwap, reduceMotion: reduceMotion))
        }
        .scrollIndicators(.hidden)
        .environment(\.settingsBand, band)
        .onPreferenceChange(SettingsRowKeys.self) { presentRows = $0 }
    }

    /// Polls while the new page mounts its rows; a later pick cancels this one.
    private func findRow(_ proxy: ScrollViewProxy) async {
        guard let target = jumpTarget else { return }
        var jump = SettingsSearchJump(target: target)
        while true {
            switch jump.poll(present: presentRows) {
            case .wait:
                do { try await Task.sleep(for: .seconds(SettingsSearchJump.retryInterval)) } catch { return }
            case .found(let key):
                withAnimation(ChromeMotion.animation(.expoOut(MotionTime.panel), reduceMotion: reduceMotion)) {
                    proxy.scrollTo(key, anchor: .center)
                }
                await playBand(key)
                return
            case .done:
                return
            }
        }
    }

    private func playBand(_ key: String) async {
        for step in SettingsSearchJump.bandSteps {
            withAnimation(ChromeMotion.animation(
                MotionCurve.animation(MotionCurve.standard, step.fade), reduceMotion: reduceMotion)) {
                band = SettingsBand(key: key, visible: step.visible)
            }
            do { try await Task.sleep(for: .seconds(step.wait)) } catch { break }
        }
        band = nil
    }

    @ViewBuilder private var page: some View {
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
                confirmPurge: $confirmPurge, onClose: onClose, onAppear: refreshStorage)
        }
    }

    /// A search result opens its page and lights the row for a moment, so
    /// the eye finds what it asked for without reading the page.
    private func jump(_ entry: SettingsSearch.Entry) {
        guard let target = SettingsTab(rawValue: entry.page) else { return }
        dropdowns.dismiss()
        withAnimation(ChromeMotion.animation(.springSelect, reduceMotion: reduceMotion)) { tab = target }
        query = ""
        band = nil
        jumpTarget = SettingsSearchJump.target(for: entry)
        jumpNonce += 1
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
