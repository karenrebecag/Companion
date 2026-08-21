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
    @State private var keyboardMonitor: KeyboardMonitor?

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

    private func tapOrb() {
        let action = VoiceTapAction.forState(voice.snapshot.state)
        switch action {
        case .start:
            voice.start()
        case .interrupt:
            voice.advance()
        case .hangUp:
            voice.hangUp()
        }
    }

    public var body: some View {
        Group {
            if chat.needsOnboarding {
                OnboardingView(model: chat)
            } else {
                ZStack {
                    ThreadView(chat: chat, voice: voice)

                    VStack {
                        HStack {
                            Spacer()
                            Button(action: { showSettings = true }) {
                                Image(systemName: "gear")
                                    .font(.uiBody)
                                    .foregroundStyle(Semantic.mutedForeground)
                            }
                            .buttonStyle(.plain)
                            .padding(Space.x4)
                        }
                        Spacer()
                        // Orb: clickable indicator and control for voice state
                        HStack {
                            Spacer()
                            Button(action: tapOrb) {
                                Orb(
                                    state: voice.snapshot.state,
                                    levels: voice.levels,
                                    accentColor: Semantic.accent
                                )
                                .frame(width: 80, height: 80)
                            }
                            .buttonStyle(.plain)
                            .padding(Space.x4)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Semantic.background)
        .overlay(alignment: .topTrailing) {
            if !chat.needsOnboarding {
                ToastStack(center: chat.notices)
                    .padding(.top, Space.x6 * 2)
                    .padding(.trailing, Space.x4)
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
                    showSettings = true
                case .newConversation:
                    voice.hangUp()
                    chat.newConversation()
                case .attach:
                    pickAttachments()
                case .history:
                    break
                }
            }
            monitor.start()
            keyboardMonitor = monitor
        }
        // Settings sheet
        .sheet(isPresented: $showSettings) {
            SettingsView(
                preview: voicePreview,
                executors: executors,
                onLiveSpeedChange: { voice.setSpeed($0) },
                onAECRearm: onAECRearm,
                echoFreeOutput: voice.echoFreeOutput,
                updates: updates)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .companionOpenSettings)
        ) { _ in
            showSettings = true
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .companionAttach)
        ) { _ in
            pickAttachments()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            dropFiles(providers)
            return true
        }
        // Approval sheet
        .sheet(item: Binding(
            get: { chat.pendingApproval.map(ApprovalItem.init) },
            set: { if $0 == nil { chat.answerApproval(false) } }
        )) { item in
            ApprovalSheet(request: item.request) { approved in
                chat.answerApproval(approved)
            }
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

    private func dropFiles(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    adoptFile(url)
                }
            }
        }
    }

    private func adoptFile(_ url: URL) {
        guard let ref = chat.attach(url) else { return }
        if voice.isActive {
            voice.push(ref)
        }
    }
}


/// Identifiable wrapper: SwiftUI sheets key on identity, ApprovalRequest is
/// a plain value from Core.
private struct ApprovalItem: Identifiable {
    let request: ApprovalRequest
    var id: String { request.requestId }
    init(_ request: ApprovalRequest) { self.request = request }
}
