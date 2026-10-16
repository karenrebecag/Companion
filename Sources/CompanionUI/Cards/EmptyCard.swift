import CompanionCore
import SwiftUI

/// A search that found nothing, said in the card's own voice. It names what
/// was looked for so a typo is visible at a glance.
struct EmptyCard: View {
    let result: EmptyResult

    var body: some View {
        HStack(alignment: .top, spacing: Space.x3) {
            Image(systemName: symbol)
                .font(.uiBody)
                .foregroundStyle(Semantic.mutedForeground)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(title)
                    .font(.uiLabel)
                    .foregroundStyle(Semantic.foreground)
                Text(detail)
                    .font(.uiCaption)
                    .foregroundStyle(Semantic.mutedForeground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var symbol: String {
        switch result {
        case .places: "magnifyingglass"
        case .folder: "folder"
        }
    }

    private var title: String {
        switch result {
        case .places(let query):
            String(format: Localized.string("card.empty.places.title"), query)
        case .folder:
            Localized.string("card.empty.folder.title")
        }
    }

    private var detail: String {
        switch result {
        case .places: Localized.string("card.empty.places.detail")
        case .folder: Localized.string("card.empty.folder.detail")
        }
    }
}
