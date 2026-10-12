import CompanionCore

enum IslandReceipt {
    /// What VoiceOver says when the card appears: the title, then each line.
    /// The block announces a change of state, not its own arrival.
    static func announcement(_ receipt: ActionReceipt, language: AppLanguage) -> String {
        ([Localized.string("island.receipt.title", language: language)] + receipt.lines)
            .joined(separator: ". ")
    }
}
