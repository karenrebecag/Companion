import CompanionCore
import SwiftUI

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
        executors: ExecutorChoice? = nil
    ) {
        self.chat = chat
        self.voice = voice
        self.voicePreview = voicePreview
        self.executors = executors
    }

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
                }
            }
            monitor.start()
            keyboardMonitor = monitor
        }
        // Settings sheet
        .sheet(isPresented: $showSettings) {
            SettingsView(preview: voicePreview, executors: executors)
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
}


/// Identifiable wrapper: SwiftUI sheets key on identity, ApprovalRequest is
/// a plain value from Core.
private struct ApprovalItem: Identifiable {
    let request: ApprovalRequest
    var id: String { request.requestId }
    init(_ request: ApprovalRequest) { self.request = request }
}
