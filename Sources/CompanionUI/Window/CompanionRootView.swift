import AppKit
import CompanionCore
import SwiftUI
import UniformTypeIdentifiers

/// Which screen fills the window. The welcome is the only first-run flow
/// (spec 16p §4.2): a key that goes missing later routes back to it, never
/// to a second onboarding.
enum RootScreen: CaseIterable, Equatable {
    case welcome, main

    static func pick(welcomeDone: Bool, needsKey: Bool) -> RootScreen {
        welcomeDone && !needsKey ? .main : .welcome
    }
}

package struct CompanionRootView: View {
    var chat: ChatViewModel
    var voice: VoiceViewModel
    private let voicePreview: VoicePreview?
    @State private var showSettings = false
    @State private var settingsTab: SettingsTab = .general
    @State private var chromeTick = 0
    @State private var keyboardMonitor: KeyboardMonitor?
    @State private var dropdowns = DropdownHost()
    @State private var page = MainPage.home
    /// The comments modal, while it is open (16m-7).
    @State private var feedback: FeedbackModel?
    /// The task whose detail sheet is open (spec 16j §8).
    @State private var openTask: ConversationMeta?
    /// Read once per opened task: the store is disk, and the body re-runs
    /// on every streamed token (code review 16j-2).
    @State private var openTaskMessages: [ChatMessage] = []
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    package init(
        chat: ChatViewModel,
        voice: VoiceViewModel,
        voicePreview: VoicePreview? = nil,
        updates: UpdateState? = nil,
        welcome: WelcomeModel,
        memory: (any MemoryBrowsing)? = nil,
        browser: BrowserSettingsModel? = nil,
        apps: AppsModel? = nil,
        grabber: (any RegionGrabbing)? = nil
    ) {
        self.chat = chat
        self.voice = voice
        self.voicePreview = voicePreview
        self.updates = updates
        self.welcome = welcome
        self.memory = memory
        self.browser = browser
        self.apps = apps
        self.grabber = grabber
    }

    private let updates: UpdateState?
    private let welcome: WelcomeModel
    private let memory: (any MemoryBrowsing)?
    private let browser: BrowserSettingsModel?
    private let apps: AppsModel?
    /// The island's region capture, reused by the feedback modal (16m-7).
    private let grabber: (any RegionGrabbing)?

    package var body: some View {
        Group {
            if RootScreen.pick(welcomeDone: welcome.done, needsKey: chat.needsOnboarding) == .welcome {
                WelcomeView(welcome: welcome, chat: chat)
            } else {
                // Incredible's window (spec 16j §8): an index of what the island
                // did. Talking, and continuing a task, happen in the island.
                HStack(spacing: Space.none) {
                    MainSidebar(
                        page: $page,
                        onSettings: { openSettings(.general) },
                        onFeedback: openFeedback)
                    Rectangle().fill(Semantic.borderChrome).frame(width: Stroke.hairline)
                    if page == .apps, let apps {
                        AppsPage(apps: apps)
                    } else {
                        HomePage(chat: chat, onOpen: { task in
                            withAnimation(ChromeMotion.animation(.springSheet, reduceMotion: reduceMotion)) { openTask = task }
                        }, onSettings: openSettings)
                    }
                }
                .id("chrome-\(chromeTick)")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            Semantic.background.ignoresSafeArea()
                .overlay { HalftoneOverlay() }
        }
        .overlay(alignment: .topTrailing) {
            if !chat.needsOnboarding {
                ToastStack(center: chat.notices)
                    .padding(.top, Space.x6 * 2)
                    .padding(.trailing, Space.x4)
            }
        }
        .environment(dropdowns)
        .overlay {
            if dropdowns.menu == .history {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Semantic.scrim)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation(ChromeMotion.animation(.springSheet, reduceMotion: reduceMotion)) { dropdowns.dismiss() }
                    }
            }
        }
        .overlay {
            if !chat.needsOnboarding, dropdowns.menu == .history {
                GeometryReader { geo in
                    let w = min(
                        HistoryOverlayMetrics.maxSide,
                        max(HistoryOverlayMetrics.minWidth,
                            geo.size.width - Space.x6))
                    let h = min(
                        HistoryOverlayMetrics.maxSide,
                        max(240, geo.size.height - Space.x6))
                    HistoryOverlay(chat: chat, voice: voice, host: dropdowns)
                        .frame(width: w)
                        .frame(maxHeight: h)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .transition(.opacity)
            }
        }
        .dropdownPortal(host: dropdowns)
        .animation(ChromeMotion.animation(.springSheet, reduceMotion: reduceMotion), value: dropdowns.menu)
        .onExitCommand {
            if chat.session.projection.approval != nil {
                chat.answerApproval(false)
            } else if showSettings, dropdowns.session.isOpen {
                withAnimation(ChromeMotion.animation(.springSheet, reduceMotion: reduceMotion)) { dropdowns.dismiss() }
            } else if showSettings {
                withAnimation(ChromeMotion.animation(.springSheet, reduceMotion: reduceMotion)) { showSettings = false }
            } else if dropdowns.session.isOpen {
                withAnimation(ChromeMotion.animation(.springSheet, reduceMotion: reduceMotion)) { dropdowns.dismiss() }
            } else if voice.isActive {
                voice.hangUp()
            }
        }
        .onAppear {
            chat.onAppear()
            voice.onAppear()

            // Install keyboard monitor for shortcuts.
            let shortcuts = ShortcutSet.load()
            let monitor = KeyboardMonitor(shortcuts: shortcuts) { @MainActor action in
                switch action {
                case .toggleVoice:
                    if voice.isActive {
                        voice.hangUp()
                    } else {
                        voice.start()
                    }
                case .toggleMute:
                    voice.toggleMute()
                case .hangUp:
                    voice.hangUp()
                case .settings:
                    withAnimation(ChromeMotion.animation(.springSheet, reduceMotion: reduceMotion)) { showSettings = true }
                case .newConversation:
                    voice.hangUp()
                    chat.newConversation()
                case .attach:
                    pickAttachments()
                case .history:
                    withAnimation(ChromeMotion.animation(.springSheet, reduceMotion: reduceMotion)) { dropdowns.toggle(.history) }
                }
            }
            monitor.start()
            keyboardMonitor = monitor
        }
        .overlay {
            if showSettings {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(Semantic.scrim)
                        .ignoresSafeArea()
                        .onTapGesture {
                            dropdowns.dismiss()
                            withAnimation(ChromeMotion.animation(.springSheet, reduceMotion: reduceMotion)) { showSettings = false }
                        }
                    GeometryReader { geo in
                        let w = min(
                            SettingsOverlayMetrics.maxWidth,
                            max(300, geo.size.width - Space.x6))
                        let h = min(
                            SettingsOverlayMetrics.maxHeight,
                            max(320, geo.size.height - Space.x6))
                        SettingsView(
                            preview: voicePreview,
                            chat: chat,
                            updates: updates,
                            welcome: welcome,
                            memory: memory,
                            browser: browser,
                            tab: $settingsTab,
                            onClose: {
                                withAnimation(ChromeMotion.animation(.springSheet, reduceMotion: reduceMotion)) { showSettings = false }
                            })
                        .environment(dropdowns)
                        .frame(width: w, height: h)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(ChromeMotion.animation(.springSheet, reduceMotion: reduceMotion), value: showSettings)
        .overlay { feedbackLayer }
        .overlay { taskSheet }
        .animation(ChromeMotion.animation(.springSheet, reduceMotion: reduceMotion), value: openTask?.id)
        .onChange(of: openTask?.id) { _, id in
            openTaskMessages = id.map(chat.transcript) ?? []
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .companionOpenApps)
        ) { note in
            // 16k-3: the island's "Conectar X" card. The page opens on
            // Apps with that app's panel up, so Conectar is one tap away.
            page = .apps
            if let slug = note.object as? String { apps?.focus(slug) }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .companionOpenFeedback)
        ) { _ in openFeedback() }
        .onAppear { if FeedbackRequest.consume() { openFeedback() } }
        .onReceive(
            NotificationCenter.default.publisher(for: .companionOpenSettings)
        ) { note in
            // The island names the page it means: keys live in privacy, the
            // shortcuts in general; the menu opens at the top.
            settingsTab = (note.object as? String).flatMap(SettingsTab.init(rawValue:)) ?? .general
            withAnimation(ChromeMotion.animation(.springSheet, reduceMotion: reduceMotion)) { showSettings = true }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .companionChromeDidChange)
        ) { _ in
            chromeTick += 1
            if let window = NSApp.keyWindow {
                WindowChrome.applyAppearance(window)
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .companionAttach)
        ) { _ in
            pickAttachments()
        }
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls { adoptFile(url) }
            return true
        } isTargeted: { over in
            withAnimation(ChromeMotion.animation(.expoOut(MotionTime.fast), reduceMotion: reduceMotion)) {
                chat.dropTargeted = over
            }
        }
        .overlay {
            if chat.dropTargeted { DropVeil() }
        }
        .animation(ChromeMotion.animation(.springSheet, reduceMotion: reduceMotion), value: chat.pendingAttachments)
        .overlay {
            if let request = chat.session.projection.approval {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(Semantic.scrim)
                        .ignoresSafeArea()
                    ApprovalSheet(request: request) { approved, remember in
                        chat.answerApproval(approved, remember: remember)
                    }
                    // A new request is a new sheet: without the id, SwiftUI
                    // reuses the view and the countdown ring (and the
                    // remember toggle) inherit the previous request's state
                    // (review 19-1b M1).
                    .id(request.requestId)
                    .background(Semantic.surfaceOverlay)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.xl)
                            .stroke(Semantic.border, lineWidth: Stroke.hairline))
                    .elevation(.sheet)
                }
                .transition(.opacity)
            }
        }
        .animation(ChromeMotion.animation(.springSheet, reduceMotion: reduceMotion), value: chat.session.projection.approval != nil)
    }

    private func pickWorkdir() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            chat.setFolder(url.path)
        }
    }

    private func openFeedback() {
        _ = FeedbackRequest.consume()
        guard feedback == nil else { return }
        feedback = FeedbackModel(
            grabber: grabber, delivery: SystemFeedbackDelivery(), attachments: SystemFeedbackAttachments())
    }

    @ViewBuilder
    private var feedbackLayer: some View {
        if let model = feedback {
            ZStack {
                Rectangle().fill(.ultraThinMaterial).overlay(Semantic.scrim).ignoresSafeArea()
                FeedbackModal(model: model, onClose: { feedback = nil })
                    .elevation(.sheet)
            }
            .transition(.opacity)
        }
    }

    private func openSettings(_ tab: SettingsTab) {
        settingsTab = tab
        withAnimation(ChromeMotion.animation(.springSheet, reduceMotion: reduceMotion)) { showSettings = true }
    }

    @ViewBuilder
    private var taskSheet: some View {
        if let task = openTask {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Semantic.scrim)
                    .ignoresSafeArea()
                    .onTapGesture { openTask = nil }
                GeometryReader { geo in
                    TaskDetailSheet(
                        task: task, messages: openTaskMessages, canFollowUp: chat.canFollowUp,
                        onFollowUp: {
                            guard chat.followUp(task) else { return }
                            openTask = nil
                            NotificationCenter.default.post(name: .companionFollowUp, object: nil)
                        },
                        onClose: { openTask = nil })
                    .frame(width: min(MainWindowMetrics.detailMaxWidth, geo.size.width - Space.x6),
                           height: min(MainWindowMetrics.detailMaxHeight, geo.size.height - Space.x6))
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
            .transition(.opacity)
        }
    }

    private func pickAttachments() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.item]
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls { adoptFile(url) }
        }
    }

    private func adoptFile(_ url: URL) {
        guard let ref = chat.attach(url) else { return }
        if voice.isActive {
            voice.push(ref)
        }
    }
}
