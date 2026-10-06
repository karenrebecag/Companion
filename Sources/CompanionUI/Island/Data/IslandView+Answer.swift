import CompanionCore
import SwiftUI

// The rich answer that opens under the island (16m-1): the data family.

/// Every open and close of the popover goes through here, so the reducer
/// hears it from the button, the Escape key and the island's own rest alike.
enum IslandAnswerSignal {
    @discardableResult
    @MainActor
    static func changed(from old: UUID?, to new: UUID?, session: SessionModel) -> [SessionEffect] {
        if new != nil { return session.send(.answerOpened) }
        guard old != nil else { return [] }
        return session.send(.answerClosed)
    }

    /// The popover dies with its message (a new conversation): without this
    /// the reducer would keep holding the island open for a popover nobody sees.
    @MainActor
    static func reconcile(
        open: UUID?, messageExists: Bool, session: SessionModel
    ) -> (open: UUID?, effects: [SessionEffect]) {
        guard let open, !messageExists else { return (open, []) }
        return (nil, changed(from: open, to: nil, session: session))
    }
}
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
            // The channel card is not in the text. Without it here, "Ver"
            // would open a popup that does not contain the result.
            let channel = Self.channelCard(on: message)
            AnswerPopupView(
                blocks: blocks,
                card: channel,
                // The notch sits centered on its screen, so twice its midX
                // IS the screen width the 76 % cap wants.
                screenWidth: geometry.notch.midX * 2,
                maxHeight: IslandChrome.canvasHeight - shown.height
                    - AnswerPopupMetrics.dropGap - IslandChrome.shadowRoom
                    - AnswerPopupMetrics.chrome,
                onClose: closeAnswer)
                .environment(\.diagramRenderer, diagrams)
                .environment(\.fileSaver, saveFile)
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

    /// A reply landing under the island is shown to the user; the model
    /// hears it, and later whether it was opened or left alone (16h-3).
    func reportReplyShown(_ id: UUID?) {
        guard let id else { return }
        for event in resultAttention.replyShown(id) { chat.session.report(event) }
    }

    func closeAnswer() {
        resultAttention.attended()
        chat.session.report(.closed(.answer))
        // The settle was held back by this answer; closing it releases it.
        IslandAnswerSignal.changed(from: openAnswer, to: nil, session: chat.session)
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
              Self.opensInPopup(message)
        else {
            onShowMain()
            return
        }
        IslandAnswerSignal.changed(from: openAnswer, to: id, session: chat.session)
        withAnimation(.expoOut(IslandMotionBudget.popover.openDuration)) { openAnswer = id }
    }
}
