import CompanionCore
import SwiftUI

// The clip's actions (16i-2): the picker, the screenshot, the captured text.
extension IslandView {
    var attachActions: IslandAttachActions {
        IslandAttachActions(chat: chat, voice: voice, grabber: grabber, say: sayAttach)
    }

    func pickAttach(_ item: IslandAttachItem) {
        switch item {
        case .chooseFile:
            // The picker lives in the window: activating the app is
            // CompanionMain's call, never the island's (conformance 12d).
            onShowMain()
            NotificationCenter.default.post(name: .companionAttach, object: nil)
        case .screenshot:
            Task { await attachActions.screenshot() }
        case .captureText:
            Task {
                guard let text = await attachActions.captureText() else { return }
                draft = IslandDraft.appending(text, to: draft)
            }
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
