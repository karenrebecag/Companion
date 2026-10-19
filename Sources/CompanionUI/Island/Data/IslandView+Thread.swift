import CompanionCore
import SwiftUI

// Under the notch bar's field: a conversation lives in the chat (`.chat`),
// so the bar only keeps what arrives before a message of it exists.
extension IslandView {
    @ViewBuilder
    func thread(_ state: IslandState) -> some View {
        if let latest = latestReply {
            choiceCard(latest)
        }
    }
}
