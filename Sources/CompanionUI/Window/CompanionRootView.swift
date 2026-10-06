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
    @State private var settingsSheet = SettingsSheetModel()
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
        grabber: (any RegionGrabbing)? = nil,
        mirror: InspectionMirror? = nil
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
        self.mirror = mirror
    }

    private let updates: UpdateState?
    private let welcome: WelcomeModel
    private let memory: (any MemoryBrowsing)?
    private let browser: BrowserSettingsModel?
    private let apps: AppsModel?
    /// The island's region capture, reused by the feedback modal (16m-7).
    private let grabber: (any RegionGrabbing)?
    /// Where self-inspection reads the screen: page, Settings and tab are
    /// this view's private state, so only the view can report them.
    private let mirror: InspectionMirror?

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
                    detailPage
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
            if let request = chat.session.projection.approval {
                chat.answerApproval(false, requestId: request.requestId)
            } else if settingsSheet.isOpen, dropdowns.session.isOpen {
                withAnimation(ChromeMotion.animation(.springSheet, reduceMotion: reduceMotion)) { dropdowns.dismiss() }
            } else if settingsSheet.isOpen {
                if settingsSheet.escape() == .close { closeSettings() }
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
                    presentSettings()
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
            if settingsSheet.isOpen {
                SettingsSheetHost(
                    model: $settingsSheet, tab: $settingsTab, preview: voicePreview, chat: chat,
                    updates: updates, welcome: welcome, memory: memory, browser: browser,
                    onClose: closeSettings)
                .environment(dropdowns)
            }
        }
        .overlay { feedbackLayer }
        .overlay { taskSheet }
        .animation(ChromeMotion.animation(.springSheet, reduceMotion: reduceMotion), value: openTask?.id)
        .onChange(of: openTask?.id) { _, id in
            openTaskMessages = id.map(chat.transcript) ?? []
        }
        .modifier(ScreenReport(page: page, settingsOpen: settingsSheet.isOpen, settingsTab: settingsTab, mirror: mirror))
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
            presentSettings()
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
                    ApprovalSheet(request: request, answer: chat.approvalAnswer(for: request))
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

    /// The pane on the right of the sidebar: the decision lives in
    /// `DetailPane` so the test can call it without this view's
    /// dependencies.
    @ViewBuilder
    private var detailPage: some View {
        switch DetailPane.detailPane(for: page, appsAvailable: apps != nil) {
        case .home:
            homePage
        case .apps:
            if let apps { AppsPage(apps: apps) }
        case .placeholder:
            if let placeholder = MainSidebar.placeholder(for: page) {
                ModulePlaceholderPage(placeholder: placeholder)
            } else {
                homePage
            }
        }
    }

    private var homePage: some View {
        HomePage(chat: chat, voice: voice, onOpen: { task in
            withAnimation(ChromeMotion.animation(.springSheet, reduceMotion: reduceMotion)) { openTask = task }
        }, onSettings: openSettings)
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
        presentSettings()
    }

    /// Mounted first, settled on the next turn: in one transaction the sheet
    /// would appear already in place and the entrance would never play.
    private func presentSettings() {
        guard settingsSheet.open(animated: !reduceMotion) else { return }
        Task { @MainActor in
            withAnimation(ChromeMotion.animation(SettingsSheetMetrics.motion, reduceMotion: reduceMotion)) { settingsSheet.settle() }
        }
    }

    /// The sheet stays mounted, and reported open, until its exit has played.
    private func closeSettings() {
        guard settingsSheet.canClose else { return }
        dropdowns.dismiss()
        guard !reduceMotion else {
            _ = settingsSheet.close(animated: false)
            return
        }
        withAnimation(ChromeMotion.animation(SettingsSheetMetrics.motion, reduceMotion: reduceMotion)) {
            _ = settingsSheet.close(animated: true)
        } completion: {
            settingsSheet.finishClose()
        }
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
                        onFollowUp: { words in
                            guard chat.followUp(task, saying: words) else { return false }
                            openTask = nil
                            NotificationCenter.default.post(name: .companionFollowUp, object: nil)
                            return true
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
