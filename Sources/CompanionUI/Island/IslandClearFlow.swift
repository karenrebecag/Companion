import CompanionCore

/// The island's two-step clear, apart from the view that draws it: asking is
/// not clearing, and the question stays until the cut happened or was refused.
struct IslandClearFlow: Equatable {
    private(set) var asking = false

    mutating func ask() {
        asking = true
    }

    mutating func cancel() {
        asking = false
    }

    /// The same cut as Settings. The question stays on a failure so she can
    /// retry; the reason shows where the island already shows errors.
    mutating func confirm(chat: ChatViewModel) {
        do {
            try chat.applyHistoryClear(.confirm)
            asking = false
        } catch {
            chat.log("history: clear failed")
            chat.errorText = Localized.string("settings.history.error")
        }
    }
}
