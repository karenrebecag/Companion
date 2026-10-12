import CompanionCore
import SwiftUI

// The receipt family (16h-3): the card a done action leaves in the island,
// now the result card with the lines as its body.
extension IslandView {
    /// Closing it is the user's word (the model hears "closed"); leaving on
    /// its own is the reducer's clock.
    func receiptCard(_ receipt: ActionReceipt) -> some View {
        resultCard(
            icon: "checklist", spoken: nil, steps: [], sources: [],
            onDismiss: { chat.dismissIslandNotice(.receipt(receipt)) }
        ) { IslandReceiptLines(receipt: receipt) }
        .onAppear {
            AccessibilityNotification.Announcement(
                IslandReceipt.announcement(receipt, language: Localized.language())).post()
        }
    }
}
