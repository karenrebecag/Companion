import CompanionCore
import SwiftUI

// The receipt family (16h-3): the card a done action leaves in the island,
// now the result card with the lines as its steps.
extension IslandView {
    /// Closing it is the user's word (the model hears "closed"); leaving on
    /// its own is the reducer's clock.
    func receiptCard(_ receipt: ActionReceipt) -> some View {
        let language = Localized.language()
        return resultCard(
            icon: "checklist", spoken: nil,
            steps: IslandResultCardModel.steps(receipt: receipt, language: language),
            sources: [],
            onDismiss: { chat.dismissIslandNotice(.receipt(receipt)) }
        ) { EmptyView() }
        .onAppear {
            AccessibilityNotification.Announcement(
                IslandReceipt.announcement(receipt, language: language)).post()
        }
    }
}
