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
    @Binding var dialogs: SettingsDialogStack
    @State private var band: SettingsBand?
    /// The row a pick is looking for; the nonce restarts the search on a new pick.
    @State private var jumpTarget: String?
    @State private var jumpNonce = 0
    @State private var presentRows: Set<String> = []
    @State private var history = HistoryClearModel()
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
        dialogs: Binding<SettingsDialogStack> = .constant(SettingsDialogStack()),
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
        self._dialogs = dialogs
        self.onClose = onClose
    }

    private let updates: UpdateState?

    package var body: some View {
        sheetBody
        .environment(\.openSettingsDialog, openDialog)
        .overlay {
            if dropdowns.session.isOpen, case .settingsPick = dropdowns.menu {
                Color.black.opacity(0.001)
                    .onTapGesture {
                        withAnimation(ChromeMotion.animation(.springSheet, reduceMotion: reduceMotion)) { dropdowns.dismiss() }
                    }
            }
        }
        .overlay { HistoryClearDialog(model: history, chat: chat) }
        .overlay {
            SettingsDialogLayer(
                stack: $dialogs, permissions: permissionModels, onConfirm: purgeStoredFiles)
        }
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
            VStack(alignment: .leading, spacing: Space.x5) {
                SettingsGeneralPage(accessibility: chat?.accessibility, onLanguageChange: languageChanged)
                SettingsDialogLinks(ids: [.shortcuts], open: openDialog)
            }
        case .voice:
            SettingsVoiceSection(preview: preview, secrets: chat?.secrets)
        case .vocabulary:
            SettingsVocabularyPage()
        case .memory:
            SettingsMemoryPage(memory: memory)
        case .you:
            SettingsYouPage(welcome: welcome, onClose: onClose)
        case .privacy:
            SettingsPrivacyPage(chat: chat, welcome: welcome, browser: browser)
        case .system:
            SettingsSystemPage(
                chat: chat, updates: updates, storageLabel: storageLabel,
                onAppear: refreshStorage, history: history)
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
        if let dialog = SettingsDialogID.opened(by: entry.id) {
            openDialog(dialog)
        }
    }

    private func openDialog(_ id: SettingsDialogID) {
        dropdowns.dismiss()
        dialogs.present(id)
    }

    /// The same real action the old blurred confirmation ran.
    private func purgeStoredFiles() {
        _ = dialogs.confirm {
            chat?.purgeStoredAttachments()
            refreshStorage()
        }
    }

    private var permissionModels: [PermissionRowModel] {
        WelcomePermission.allCases.map { permission in
            PermissionRowModel(
                kind: permission.rowKind,
                granted: welcome?.facts.granted.contains(permission) ?? false)
        }
    }

    private func languageChanged() {
        languageTick += 1
        NotificationCenter.default.post(name: .companionLanguageDidChange, object: nil)
    }

    private func refreshStorage() {
        storageLabel = chat?.attachmentsStorageLabel ?? Localized.string("settings.storage.empty")
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
