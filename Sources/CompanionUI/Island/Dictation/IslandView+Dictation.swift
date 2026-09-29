import CompanionCore
import SwiftUI

// The dictation result card's actions (16m-4). The text lives in the
// session projection for as long as the card does; both buttons act on it
// there, and only the machine lets it go.
extension IslandView {
    func dictationCard(app: String, text: DictatedText) -> some View {
        IslandDictationCard(
            app: app, text: text.value,
            onCopy: {
                IslandDictation.copy(text.value)
                chat.session.send(.dictationCardCopied)
            },
            onHide: { chat.session.send(.dictationHidden) },
            onHover: { chat.session.send(.dictationCardHover($0)) })
    }
}
