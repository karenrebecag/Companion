import AppKit
import CompanionCore
import SwiftUI

public enum SettingsOverlayMetrics {
    /// The history overlay still uses the old square bound.
    public static let maxSide: CGFloat = 560
    /// 16g: the sidebar widens the sheet; the height stays a sheet's.
    public static let maxWidth: CGFloat = 780
    public static let maxHeight: CGFloat = 620
    public static let sidebar: CGFloat = 200
    public static let cardHeight: CGFloat = 68
    public static let avatar: CGFloat = Space.x8 + Space.x1
    public static let bigAvatar: CGFloat = 56
    public static let stepHit: CGFloat = Space.x8
    /// How long a row stays lit after a search lands on it.
    public static let highlightSeconds: Double = 1.6
}

/// Settings (Wave 16g): a sheet with a sidebar and a search, one page at a
/// time. Each page owns its state; this view owns only where you are.
public struct SettingsView: View {
    private let preview: VoicePreview?
    var chat: ChatViewModel?
    var welcome: WelcomeModel?
    var memory: (any MemoryBrowsing)?
    let onClose: () -> Void
    @Binding var tab: SettingsTab
    @State private var query = ""
    @State private var highlight: String?
    @State private var highlightTimer: Task<Void, Never>?
    @State private var confirmPurge = false
    @State private var storageLabel = Localized.string("settings.storage.empty")
    /// Bumped on a language change: every string on screen repaints at once.
    @State private var languageTick = 0
    @Environment(DropdownHost.self) private var dropdowns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        preview: VoicePreview? = nil,
        chat: ChatViewModel? = nil,
        updates: UpdateState? = nil,
        welcome: WelcomeModel? = nil,
        memory: (any MemoryBrowsing)? = nil,
        tab: Binding<SettingsTab> = .constant(.general),
        onClose: @escaping () -> Void = {}
    ) {
        self.preview = preview
        self.chat = chat
        self.welcome = welcome
        self.memory = memory
        self.updates = updates
        self._tab = tab
        self.onClose = onClose
    }

    private let updates: UpdateState?

    public var body: some View {
        HStack(spacing: Space.none) {
            SettingsSidebar(tab: $tab, query: $query, onPick: jump)
                .frame(width: SettingsOverlayMetrics.sidebar)
            Rectangle().fill(Semantic.border).frame(width: Stroke.hairline)
            ScrollView {
                page
                    .padding(Space.x6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("\(tab.rawValue)-\(languageTick)")
                    .transition(ChromeMotion.transition(.modeSwap, reduceMotion: reduceMotion))
            }
            .scrollIndicators(.hidden)
            .environment(\.settingsHighlight, highlight)
        }
        .background(Semantic.background)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
        .background(
            RoundedRectangle(cornerRadius: Radius.xl)
                .fill(Semantic.background)
                .elevation(.sheet))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl)
                .stroke(Semantic.border, lineWidth: Stroke.hairline))
        .overlay(alignment: .topTrailing) { closeButton }
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
            highlightTimer?.cancel()
        }
        .onAppear { refreshStorage() }
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
            SettingsPrivacyPage(chat: chat, welcome: welcome)
        case .system:
            SettingsSystemPage(
                chat: chat, updates: updates, welcome: welcome, storageLabel: storageLabel,
                confirmPurge: $confirmPurge, onClose: onClose, onAppear: refreshStorage)
        }
    }

    private var closeButton: some View {
        CloseButton {
            dropdowns.dismiss()
            withAnimation(ChromeMotion.animation(.springSheet, reduceMotion: reduceMotion)) { onClose() }
        }
        .padding(Space.x4)
    }

    /// A search result opens its page and lights the row for a moment, so
    /// the eye finds what it asked for without reading the page.
    private func jump(_ entry: SettingsSearch.Entry) {
        guard let target = SettingsTab(rawValue: entry.page) else { return }
        dropdowns.dismiss()
        withAnimation(ChromeMotion.animation(.springSelect, reduceMotion: reduceMotion)) { tab = target }
        query = ""
        highlight = entry.id
        highlightTimer?.cancel()
        highlightTimer = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(SettingsOverlayMetrics.highlightSeconds)) } catch { return }
            highlight = nil
        }
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

/// Search on top, the pages in two groups, the version at the bottom.
struct SettingsSidebar: View {
    @Binding var tab: SettingsTab
    @Binding var query: String
    let onPick: (SettingsSearch.Entry) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            searchField
                .padding(.bottom, Space.x3)
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                group(SettingsTab.firstGroup)
                Spacer().frame(height: Space.x4)
                group(SettingsTab.secondGroup)
            } else {
                results
            }
            Spacer(minLength: Space.x4)
            Text(String(format: Localized.string("settings.sidebar.version"), SettingsVersion.current))
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
                .padding(.horizontal, Space.x2)
        }
        .padding(Space.x4)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var searchField: some View {
        HStack(spacing: Space.x2) {
            Image(systemName: "magnifyingglass")
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
                .accessibilityHidden(true)
            TextField(Localized.string("settings.search.placeholder"), text: $query)
                .textFieldStyle(.plain)
                .font(.uiLabel)
                .onSubmit {
                    if let first = SettingsSearch.match(query, in: SettingsInventory.searchEntries).first {
                        onPick(first)
                    }
                }
        }
        .padding(.horizontal, Space.x3)
        .padding(.vertical, Space.x2)
        // A text field in a capsule, not a button: CapsuleChipStyle has
        // nothing to style here.
        .background(Capsule().fill(Semantic.muted))
    }

    private func group(_ pages: [SettingsTab]) -> some View {
        ForEach(pages, id: \.self) { page in
            Button {
                withAnimation(ChromeMotion.animation(.springSelect, reduceMotion: reduceMotion)) { tab = page }
            } label: {
                HStack(spacing: Space.x2) {
                    Image(systemName: page.symbol)
                        .font(.uiLabel)
                        .frame(width: Space.x5)
                        .accessibilityHidden(true)
                    Text(page.title).font(.uiLabel)
                    Spacer(minLength: Space.none)
                }
                .foregroundStyle(tab == page ? Semantic.foreground : Semantic.mutedForeground)
                .padding(.horizontal, Space.x2)
                .padding(.vertical, Space.x2)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md)
                        .fill(tab == page ? Semantic.muted : Color.clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(tab == page ? .isSelected : [])
        }
    }

    @ViewBuilder private var results: some View {
        let found = SettingsSearch.match(query, in: SettingsInventory.searchEntries)
        if found.isEmpty {
            Text(String(format: Localized.string("settings.search.none"), query))
                .font(.uiCaption)
                .foregroundStyle(Semantic.mutedForeground)
                .padding(.horizontal, Space.x2)
        } else {
            ForEach(found.prefix(8), id: \.id) { entry in
                Button { onPick(entry) } label: {
                    VStack(alignment: .leading, spacing: Space.none) {
                        Text(entry.title)
                            .font(.uiLabel)
                            .foregroundStyle(Semantic.foreground)
                            .lineLimit(1)
                        Text(SettingsTab(rawValue: entry.page)?.title ?? "")
                            .font(.uiCaption)
                            .foregroundStyle(Semantic.mutedForeground)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Space.x2)
                    .padding(.vertical, Space.x1)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
        .frame(width: SettingsOverlayMetrics.maxWidth, height: SettingsOverlayMetrics.maxHeight)
}
#endif
