import CompanionCore
import SwiftUI

// Under the notch bar's field: a conversation lives in the chat (`.chat`),
// so the bar only keeps what arrives before a message of it exists.
extension IslandView {
    @ViewBuilder
    func thread(_ state: IslandState) -> some View {
        if let latest = latestReply {
            choiceCard(latest)
        } else {
            // A realtime reply reaches the thread only at transcript.done; until then the caption is all there is.
            IslandLiveReply(voice: voice, text: "", startedAt: replyStart, speaking: false, look: .thread)
                .islandContentColumn()
        }
    }
}
