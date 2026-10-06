import CompanionCore
import SwiftUI

/// The receipt (16h-3) on the island's grid: where a run ends. The header
/// carries the same check the run's loader lands on; each line keeps a small
/// check in the lead column. Sentence case, no eyebrow (Arc copy).
enum ReceiptMetrics {
    /// A glyph that reads as a check next to 12 px text.
    static let checkSize: CGFloat = 12
    static var check: Color { ArcTone.success.color }
}

enum IslandReceipt {
    /// "Done and verified" only where a read-back verified it; otherwise "Done".
    static func checkLabel(_ line: ReceiptLine, language: AppLanguage) -> String {
        Localized.string(line.verified ? "island.receipt.check" : "island.receipt.done", language: language)
    }

    /// What VoiceOver says when the card appears: the title, then each line.
    static func announcement(_ receipt: ActionReceipt, language: AppLanguage) -> String {
        ([Localized.string("island.receipt.title", language: language)] + receipt.lines)
            .joined(separator: ". ")
    }
}

/// What the turn did and could prove, one check per line.
struct IslandReceiptCard: View {
    let receipt: ActionReceipt
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: IslandGrid.rowGap) {
            IslandGridRow {
                MorphLoader(status: .success, size: AgentRunMetrics.loader)
                    // The card announces itself on appear; the check would say it twice.
                    .accessibilityHidden(true)
            } content: {
                Text(Localized.string("island.receipt.title"))
                    .font(Fonts.geist(TypeSize.rowTitle).weight(.medium))
                    .foregroundStyle(ArcTone.foreground.color)
            } trail: {
                CloseButton(variant: .island, label: Localized.string("island.receipt.dismiss"),
                            action: onDismiss)
            }
            ForEach(Array(receipt.entries.enumerated()), id: \.offset) { _, entry in
                IslandGridRow {
                    Image(systemName: "checkmark")
                        .font(Fonts.geist(ReceiptMetrics.checkSize).weight(.medium))
                        .foregroundStyle(ReceiptMetrics.check)
                        .accessibilityLabel(IslandReceipt.checkLabel(entry, language: Localized.language()))
                } content: {
                    Text(entry.text)
                        .font(Fonts.geist(TypeSize.caption))
                        .foregroundStyle(ArcTone.textSecondary.color)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(minHeight: AgentRunMetrics.node)
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityElement(children: .contain)
        .onAppear {
            AccessibilityNotification.Announcement(
                IslandReceipt.announcement(receipt, language: Localized.language())).post()
        }
    }
}
