import CompanionCore
import SwiftUI

// The rich answer that opens under the island (16m-1): the data family.
extension IslandView {
    /// The rich answer under the shape (16m-1): a card's "Ver" opens it, ×
    /// or Escape closes it, and its frame joins the click area the way the
    /// dropdown's does. It dies with its message and with the island's rest.
    @ViewBuilder
    var answerLayer: some View {
        if let id = openAnswer,
           let message = chat.messages.first(where: { $0.id == id })
        {
            let blocks = AnswerBlocks.blocks(from: message.text)
            AnswerPopupView(
                blocks: blocks,
                // The notch sits centered on its screen, so twice its midX
                // IS the screen width the 76 % cap wants.
                screenWidth: geometry.notch.midX * 2,
                maxHeight: IslandChrome.canvasHeight - shown.height
                    - AnswerPopupMetrics.dropGap - IslandChrome.shadowRoom
                    - AnswerPopupMetrics.chrome,
                onClose: closeAnswer)
                .offset(y: shown.height + AnswerPopupMetrics.dropGap)
                .onGeometryChange(for: CGRect.self, of: { proxy in
                    proxy.frame(in: .named("islandCanvas"))
                }, action: { frame in
                    // A report landing during the close fade must not
                    // resurrect the click area (security review 16m).
                    guard openAnswer != nil else { return }
                    geometry.answer = frame.intersection(CGRect(
                        x: 0, y: 0, width: IslandChrome.canvasWidth,
                        height: IslandChrome.canvasHeight))
                })
                .onDisappear { geometry.answer = nil }
                .transition(.islandPopover(anchor: .top, reduceMotion: reduceMotion))
        }
    }

    /// A reply landing under the island is a result card shown; the model
    /// hears it, and later whether it was opened or left alone (16h-3).
    func reportReplyShown(_ id: UUID?) {
        guard let id else { return }
        for event in resultAttention.replyShown(id) { chat.session.report(event) }
    }

    func closeAnswer() {
        resultAttention.attended()
        chat.session.report(.closed(.answer))
        withAnimation(.expoOut(IslandMotionBudget.popover.openDuration)) { openAnswer = nil }
        // Not waiting for the fade, same rule as the dropdown: the click
        // area shrinks with the decision.
        geometry.answer = nil
    }

    /// "Ver" earns a popup only when the reply holds more than the card
    /// already says (D2, spec 16m §5); a short answer keeps opening the
    /// window, which shows the same thing bigger.
    func openResult(_ id: UUID) {
        resultAttention.attended()
        guard let message = chat.messages.first(where: { $0.id == id }),
              AnswerBlocks.isRich(AnswerBlocks.blocks(from: message.text))
        else {
            onShowMain()
            return
        }
        withAnimation(.expoOut(IslandMotionBudget.popover.openDuration)) { openAnswer = id }
    }
}
