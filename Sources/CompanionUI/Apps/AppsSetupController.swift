import CompanionCore
import Observation
import SwiftUI

/// Runs one setup attempt: the flow decides, the model saves and loads, and
/// each outcome is said out loud. Kept out of the view so the sequence can be
/// tested against a real AppsModel and a recorded announcer.
@Observable
@MainActor
final class AppsSetupController {
    var endpoint: String
    var key = ""
    private(set) var flow = AppsSetupFlow()
    private let apps: AppsModel
    private let announce: (String) -> Void

    init(
        apps: AppsModel, endpoint: String,
        announce: @escaping (String) -> Void = { AccessibilityNotification.Announcement($0).post() }
    ) {
        self.apps = apps
        self.endpoint = endpoint
        self.announce = announce
    }

    func submit() async {
        guard flow.submit(endpoint: endpoint, key: key) else {
            // Arc's role="alert": the first thing to fix is said, not just drawn.
            if let issue = flow.announcedIssue(endpoint: endpoint, key: key) {
                announce(AppsSetupCopy.issue(issue))
            }
            return
        }
        guard apps.configure(endpoint: endpoint, key: key) else {
            flow.finish(.storageFailed)
            announce(AppsSetupCopy.failure(.storage))
            return
        }
        // The page used to load after the form closed; loading here lets a
        // refused key come back to the form that can fix it.
        await apps.load()
        flow.finish(.after(load: apps.phase))
        if let failure = flow.failure {
            announce(AppsSetupCopy.failure(failure))
        } else if flow.phase == .confirmed {
            key = ""
            announce(AppsSetupCopy.doneTitle)
        }
    }
}
