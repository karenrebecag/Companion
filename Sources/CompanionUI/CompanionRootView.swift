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
        // Presented from the real flow: the sheet is the only way to answer,
        // so a request that never reaches it dies in the auto-deny.
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
