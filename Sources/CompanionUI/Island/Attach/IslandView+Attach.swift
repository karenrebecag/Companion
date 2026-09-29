import CompanionCore
import SwiftUI

// The clip's actions (16i-2): the picker, the screenshot, the captured text.
// 16m-3 (D1): the picker runs from the island and never opens the window.
extension IslandView {
    var attachActions: IslandAttachActions {
        IslandAttachActions(chat: chat, voice: voice, grabber: grabber, say: sayAttach,
                            pickFiles: pickFiles, onFail: { attachFailures.append($0) })
    }

    /// Returns the work it started, so a caller can wait for the pick.
    @discardableResult
    func pickAttach(_ item: IslandAttachItem) -> Task<Void, Never>? {
        switch item {
        case .chooseFile:
            // One panel at a time: a second click while it is up would open
            // another, and the first to close would fold the island under it.
            guard !geometry.picking else { return nil }
            // The field stays open under the picker, whatever the pointer
            // and the window do while it is up.
            geometry.picking = true
            return Task {
                await attachActions.chooseFiles()
                geometry.picking = false
            }
        case .screenshot:
            return Task { await attachActions.screenshot() }
        case .captureText:
            return Task {
                guard let text = await attachActions.captureText() else { return }
                draft = IslandDraft.appending(text, to: draft)
            }
        }
    }

    /// The staged files and captures under the field. With the main window
    /// in front they are drawn there, not twice.
    @ViewBuilder
    var attachTray: some View {
        if !hold.mainInFront, !chat.pendingAttachments.isEmpty || !attachFailures.isEmpty {
            IslandAttachTray(
                staged: chat.pendingAttachments, failed: attachFailures,
                onRemove: chat.removePending,
                onDismissFailure: { attachFailures = IslandAttachFailure.removing($0.id, from: attachFailures) })
        }
    }

    /// One line under the field for a few seconds, then the usual caption.
    func sayAttach(_ text: String) {
        attachNoteTask?.cancel()
        attachNote = text
        attachNoteTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(IslandAttachMetrics.noteSeconds)) } catch { return }
            attachNote = nil
        }
    }
}
