import CompanionCore
import SwiftUI

enum IslandReceipt {
    /// "Done and verified" only where a read-back verified it; otherwise "Done".
    static func checkLabel(_ line: ReceiptLine, language: AppLanguage) -> String {
        Localized.string(line.verified ? "island.receipt.check" : "island.receipt.done", language: language)
    }

    /// What VoiceOver says when the card appears: the title, then each line.
    /// The block announces a change of state, not its own arrival.
    static func announcement(_ receipt: ActionReceipt, language: AppLanguage) -> String {
        ([Localized.string("island.receipt.title", language: language)] + receipt.lines)
            .joined(separator: ". ")
    }
}

/// What the turn did, one check per line, in the thread's text style. These
/// are the card's content, not live steps, so the block never folds them.
struct IslandReceiptLines: View {
    let receipt: ActionReceipt

    var body: some View {
        VStack(alignment: .leading, spacing: IslandGrid.rowGap) {
            ForEach(Array(receipt.entries.enumerated()), id: \.offset) { _, entry in
                HStack(alignment: .firstTextBaseline, spacing: IslandGrid.gap) {
                    Image(systemName: "checkmark")
                        .font(Fonts.geist(TypeSize.micro).weight(.medium))
                        .foregroundStyle(entry.verified ? ArcTone.success.color : ArcTone.textMuted.color)
                        .accessibilityLabel(IslandReceipt.checkLabel(entry, language: Localized.language()))
                    Text(entry.text)
                        .font(GeistFont.uiBody)
                        .foregroundStyle(ArcTone.foreground.color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}
