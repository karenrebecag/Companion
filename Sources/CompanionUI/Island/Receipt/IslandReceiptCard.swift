import CompanionCore
import SwiftUI

/// The receipt card (16h-3). Surface and width are the measured runcard's
/// (`wf-runcard`, docs/research/incredible-isla-componentes.md §2); the
/// eyebrow ink is `ov-card`'s; the green is the island notice's success.
/// Incredible's receipts themselves were not captured, so the rest is ours.
enum ReceiptMetrics {
    static let minWidth = WorkStateMetrics.runMinWidth
    static let maxWidth = WorkStateMetrics.runMaxWidth
    /// ov-card eyebrow: 11 px / 600 at 42 %.
    static let eyebrowSize: CGFloat = 11
    static let eyebrowAlpha = 0.42
    /// island-notice success.
    static let checkHex = "8CDC96"
    /// Own value: a glyph that reads as a check next to 12 px text.
    static let checkSize: CGFloat = 12
    static var check: Color { Swatch(checkHex).color }
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
        VStack(alignment: .leading, spacing: WorkStateMetrics.stepGap) {
            HStack(spacing: Space.x2) {
                Text(Localized.string("island.receipt.title").uppercased())
                    .font(Fonts.geist(ReceiptMetrics.eyebrowSize).weight(.semibold))
                    .foregroundStyle(.white.opacity(ReceiptMetrics.eyebrowAlpha))
                Spacer(minLength: Space.none)
                CloseButton(variant: .island, label: Localized.string("island.receipt.dismiss"),
                            action: onDismiss)
            }
            .padding(.bottom, Space.x1)
            ForEach(Array(receipt.entries.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: Space.x2) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(Fonts.geist(ReceiptMetrics.checkSize))
                        .foregroundStyle(ReceiptMetrics.check)
                        .accessibilityLabel(IslandReceipt.checkLabel(entry, language: Localized.language()))
                    Text(entry.text)
                        .font(Fonts.geist(TypeSize.caption))
                        .foregroundStyle(.white.opacity(IslandAlpha.text))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.vertical, WorkStateMetrics.stepPaddingY)
                .padding(.horizontal, WorkStateMetrics.stepPaddingX)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, WorkStateMetrics.runPaddingTop)
        .padding(.horizontal, WorkStateMetrics.runPaddingX)
        .padding(.bottom, WorkStateMetrics.runPaddingBottom)
        .modifier(WorkSurface())
        .accessibilityElement(children: .contain)
        .onAppear {
            AccessibilityNotification.Announcement(
                IslandReceipt.announcement(receipt, language: Localized.language())).post()
        }
    }
}
