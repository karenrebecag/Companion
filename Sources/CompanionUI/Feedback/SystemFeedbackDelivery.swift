import AppKit
import CompanionCore
import Foundation

public extension Notification.Name {
    /// The island's "Send feedback" entry: the modal lives in the main window.
    static let companionOpenFeedback = Notification.Name("companion.openFeedback")
}

/// The existing destination, unchanged: a new message in the user's own mail
/// app. With screenshots the system share service is the only way to attach
/// files; if it is not there the text still goes by `mailto:` and the model
/// says the screenshots stayed behind.
struct SystemFeedbackDelivery: FeedbackDelivering {
    func deliver(_ draft: FeedbackDraft, captures: [URL]) -> FeedbackDelivery {
        FeedbackDeliverer(
            share: { subject, items in
                guard let service = NSSharingService(named: .composeEmail) else { return false }
                service.subject = subject
                guard service.canPerform(withItems: items) else { return false }
                service.perform(withItems: items)
                return true
            },
            open: { NSWorkspace.shared.open($0) })
            .deliver(draft, captures: captures, subject: Localized.string("island.feedback.subject"),
                     language: Localized.language())
    }
}
