import CompanionCore
import CompanionUIPro
import SwiftUI

// The `.chat` panel wired to the island's session: the thread with the turn
// in progress, the rows that used to sit under the notch bar's field, and
// Arc's composer around the island's own text field.
extension IslandView {
    func chatPanel(_ state: IslandState) -> some View {
        let live = chat.busy ? ChatLive(streaming: chat.streaming, busy: true, job: chat.job, now: Date()) : nil
        return IslandChatPanel(
            thread: IslandChatModel.thread(chat.messages, live: live),
            maxHeight: IslandChrome.columnMaxHeight(bandHeight: geometry.notch.height),
            onOpenURL: { openURL($0) },
            rows: { chatRows(state) },
            composer: { chatComposer(state) })
            .environment(\.diagramRenderer, diagrams)
            .environment(\.fileSaver, saveFile)
    }

    @ViewBuilder
    private func chatRows(_ state: IslandState) -> some View {
        VStack(alignment: .leading, spacing: IslandGrid.groupGap) {
            if let latest = latestReply, !chat.busy { choiceCard(latest) }
            if let receipt = state.receipt, state.approval == nil {
                IslandReceiptRow(receipt: receipt) { chat.session.send(.undoPressed(id: receipt.id)) }
            }
            if let mentions, mentions.isOpen { MentionSelectorView(model: mentions) }
            attachTray
            if let attachNote {
                caption(attachNote)
            } else if let shown = IslandCopy.visibleLine(state.line), Self.chatCaptions(state.line) {
                caption(shown)
            }
            if clearFlow.asking {
                IslandClearConfirm(onClear: { clearFlow.confirm(chat: chat) }, onCancel: { clearFlow.cancel() })
            }
        }
    }

    /// The thread already shows the turn (thinking, tools, run, words), so
    /// only the lines it cannot show become a caption: a dead key, the hint.
    static func chatCaptions(_ line: IslandState.Line) -> Bool {
        switch line {
        case .holdHint, .keyBlocked, .transcriptsDebug: true
        default: false
        }
    }

    private func chatComposer(_ state: IslandState) -> some View {
        let ready = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !chat.pendingAttachments.isEmpty
        return AIChatComposer(
            action: AIChatComposerAction.resolve(busy: chat.busy, canSend: ready, canStop: state.showsStop),
            focused: fieldFocused,
            strings: AIChatComposerStrings(
                send: Localized.string("island.send"), stop: Localized.string("island.stop")),
            style: .notchComposer,
            onSend: submit, onStop: stop,
            field: {
                IslandComposerField(draft: $draft, focused: $fieldFocused, onSend: submit, mentions: mentions,
                                    size: DocChatMetrics.fieldSize, lineHeight: DocChatMetrics.fieldLine,
                                    placeholderInk: AIThreadStyle.notchChat.muted)
                    .onExitCommand {
                        if mentions?.press(.escape) == true { return }
                        switch IslandEscape.action(popoverOpen: popover != nil) {
                        case .closePopover: popover = nil
                        case .dismissField: dismissField()
                        }
                    }
            },
            leading: {
                IconButton("paperclip", label: Localized.string("island.attach"), size: .chatTool,
                           tone: .island, chip: true, active: popover == .attach) {
                    popover = IslandPopoverToggle.next(current: popover, tapped: .attach)
                }
                .portal(popover == .attach ? .popover(.attach) : nil)
            },
            trailing: {
                orbMark(side: IconButtonSize.chatTool.side)
                    .islandTooltip(Localized.string("island.tip.talk"))
                    .accessibilityValue(IslandCopy.voiceOverOnly(state.line) ? IslandCopy.line(state.line) : "")
            })
    }
}
