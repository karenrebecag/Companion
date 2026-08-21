import AppKit
import CompanionCore
import SwiftUI
import UniformTypeIdentifiers

public struct CompanionRootView: View {
    var chat: ChatViewModel
    var voice: VoiceViewModel
    private let voicePreview: VoicePreview?
    private let executors: ExecutorChoice?
    @State private var showSettings = false
    @State private var settingsTab: SettingsTab = .you
    @State private var chromeTick = 0
    @State private var keyboardMonitor: KeyboardMonitor?
    @State private var dropdowns = DropdownHost()
    @State private var mode: InteractionMode = .voice

    public init(
        chat: ChatViewModel,
        voice: VoiceViewModel,
        voicePreview: VoicePreview? = nil,
        executors: ExecutorChoice? = nil,
        onAECRearm: (() -> Void)? = nil,
        updates: UpdateState? = nil
    ) {
        self.chat = chat
        self.voice = voice
        self.voicePreview = voicePreview
        self.executors = executors
        self.onAECRearm = onAECRearm
        self.updates = updates
    }

    private let onAECRearm: (() -> Void)?
    private let updates: UpdateState?

    public var body: some View {
        Group {
            if chat.needsOnboarding {
                OnboardingView(model: chat)
            } else {
                VStack(alignment: .leading, spacing: Space.x2) {
                    HeaderView(
                        chat: chat,
                        voice: voice,
                        executors: executors,
                        mode: $mode,
                        onSettings: {
                            settingsTab = .you
                            withAnimation(.springSheet) { showSettings = true }
                        },
                        onFolder: pickWorkdir
                    )
                    .zIndex(2)
                    ThreadView(chat: chat, mode: mode)
                        .zIndex(0)
                    StatusLine(chat: chat, voice: voice)
                        .zIndex(2)
                    if !chat.pendingAttachments.isEmpty {
                        AttachmentStrip(chat: chat)
                            .transition(.modeSwap)
                            .zIndex(2)
                    }
                    Group {
                        if mode == .text {
                            ChatInputView(chat: chat, voice: voice)
                                .padding(.horizontal, Space.x4)
                                .padding(.bottom, Space.x3)
                                .transition(.modeSwap)
                        } else {
                            ControlBar(voice: voice, mode: mode)
                                .padding(.bottom, Space.x3)
                                .transition(.modeSwap)
                        }
                    }
                    .animation(.springSheet, value: mode)
                    .zIndex(2)
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
            if dropdowns.menu == .choice || dropdowns.menu == .history {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Semantic.scrim)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .allowsHitTesting(dropdowns.menu == .history)
                    .onTapGesture {
                        withAnimation(.springSheet) { dropdowns.dismiss() }
                    }
            }
        }
        .overlay {
            if dropdowns.blocksRoot {
                Color.black.opacity(0.001)
                    .onTapGesture {
                        withAnimation(.springSheet) { dropdowns.dismiss() }
                    }
            }
        }
        .overlay(alignment: .topLeading) {
            if !chat.needsOnboarding, dropdowns.menu == .choice {
                ChoiceDropdown(executors: executors, host: dropdowns)
                    .padding(.leading, Space.x4)
                    .padding(.top, Space.x1 * 25)
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
        .animation(.springSheet, value: dropdowns.menu)
        .onExitCommand {
            if chat.pendingApproval != nil {
                chat.answerApproval(false)
            } else if showSettings, dropdowns.session.isOpen {
                withAnimation(.springSheet) { dropdowns.dismiss() }
            } else if showSettings {
                withAnimation(.springSheet) { showSettings = false }
            } else if dropdowns.session.isOpen {
                withAnimation(.springSheet) { dropdowns.dismiss() }
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
                    withAnimation(.springSheet) { showSettings = true }
                case .newConversation:
                    voice.hangUp()
                    chat.newConversation()
                case .attach:
                    pickAttachments()
                case .history:
                    withAnimation(.springSheet) { dropdowns.toggle(.history) }
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
                            withAnimation(.springSheet) { showSettings = false }
                        }
                    GeometryReader { geo in
                        let w = min(
                            SettingsOverlayMetrics.maxSide,
                            max(300, geo.size.width - Space.x6))
                        let h = min(
                            SettingsOverlayMetrics.maxSide,
                            max(320, geo.size.height - Space.x6))
                        SettingsView(
                            preview: voicePreview,
                            chat: chat,
                            onLiveSpeedChange: { voice.setSpeed($0) },
                            onLiveVolumeChange: { voice.setVolume($0) },
                            onAECRearm: onAECRearm,
                            echoFreeOutput: voice.echoFreeOutput,
                            updates: updates,
                            tab: $settingsTab,
                            onClose: {
                                withAnimation(.springSheet) { showSettings = false }
                            })
                        .environment(dropdowns)
                        .frame(width: w, height: h)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.springSheet, value: showSettings)
        .onReceive(
            NotificationCenter.default.publisher(for: .companionOpenSettings)
        ) { _ in
            settingsTab = .app
            withAnimation(.springSheet) { showSettings = true }
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
            withAnimation(.easeOut(duration: MotionTime.fast)) {
                chat.dropTargeted = over
            }
        }
        .overlay {
            if chat.dropTargeted { DropVeil() }
        }
        .animation(.springSheet, value: chat.pendingAttachments)
        .overlay {
            if let request = chat.pendingApproval {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(Semantic.scrim)
                        .ignoresSafeArea()
                    ApprovalSheet(request: request) { approved in
                        chat.answerApproval(approved)
                    }
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
        .animation(.springSheet, value: chat.pendingApproval != nil)
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
