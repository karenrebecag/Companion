import CompanionCore
import SwiftUI

// The receipt family (16h-3): the card a done action leaves in the island.
extension IslandView {
    /// Closing it is the user's word (the model hears "closed"); leaving on
    /// its own is the reducer's clock.
    func receiptCard(_ receipt: ActionReceipt) -> some View {
        IslandReceiptCard(receipt: receipt, onDismiss: { chat.dismissIslandNotice(.receipt(receipt)) })
    }
}
