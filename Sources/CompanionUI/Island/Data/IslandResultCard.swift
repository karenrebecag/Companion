import CompanionCore
import SwiftUI

// The island's result card: the document a finished reply becomes. The host
// owns every word; this file owns where they sit.

enum IslandResultCardMetrics {
    /// What the document's content gets: the card's width less its padding.
    static let bodyWidth: CGFloat = DocCardMetrics.width - 2 * DocCardMetrics.padX
}

struct IslandResultCard<Body: View>: View {
    let title: String
    let blocks: [AnswerBlock]
    let links: IslandResultCardModel.Links
    let maxHeight: CGFloat
    let onOpenURL: (URL) -> Void
    var onDismiss: (() -> Void)?
    var onContinue: (() -> Void)?
    @ViewBuilder let content: () -> Body

    var body: some View {
        IslandDocFrame(accent: DocCardInk.narrative, maxHeight: maxHeight, onDismiss: onDismiss) {
            DocColumn(spacing: DocCardMetrics.blockGap) {
                Text(title)
                    .font(Fonts.geist(DocCardMetrics.titleSize).weight(.semibold))
                    .tracking(DocCardMetrics.titleSize * DocCardMetrics.titleTracking)
                    .lineSpacing(DocCardMetrics.lineExtra(
                        size: DocCardMetrics.titleSize, leading: DocCardMetrics.titleLeading))
                    .foregroundStyle(Color.white.opacity(DocCardInk.title))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.trailing, onDismiss == nil ? Space.none : DocCardMetrics.toolReserve)
                    .accessibilityAddTraits(.isHeader)
                if !blocks.isEmpty { IslandDocProse(blocks: blocks) }
                content()
                DocSources(links: links, onOpen: onOpenURL)
                    .padding(.top, links.chips.isEmpty ? Space.none : DocCardMetrics.sourcesLift)
                if let onContinue {
                    DocChip(scale: .action, action: onContinue) { Text(Localized.string("island.result.continue")) }
                }
            }
        }
    }
}
