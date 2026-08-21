import CompanionCore
import SwiftUI

public struct CompanionRootView: View {
    var chat: ChatViewModel
    var voice: VoiceViewModel

    public init(chat: ChatViewModel, voice: VoiceViewModel) {
        self.chat = chat
        self.voice = voice
    }

    public var body: some View {
        Group {
            if chat.needsOnboarding {
                OnboardingView(model: chat)
            } else {
                ThreadView(chat: chat, voice: voice)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.Color.bg)
        .onAppear {
            chat.onAppear()
            voice.onAppear()
        }
    }
}
