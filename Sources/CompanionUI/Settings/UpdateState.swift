import CompanionCore
import Observation
import SwiftUI

/// What Settings shows about updates. The checker lives in Services; the
/// composition feeds results in and handles the on-demand check.
@Observable
@MainActor
package final class UpdateState {
    package struct Available: Equatable {
        package let tag: String
        package let pageURL: URL
        package init(tag: String, pageURL: URL) {
            self.tag = tag
            self.pageURL = pageURL
        }
    }

    package private(set) var available: Available?
    package private(set) var checking = false
    /// The island's offer is waved away per version, for this session.
    private var dismissedTag: String?
    package var noticeTag: String? {
        IslandUpdate.visibleTag(available: available, dismissed: dismissedTag)
    }

    package func dismissNotice() {
        dismissedTag = available?.tag
    }

    private let checkNow: () async -> Available?

    package init(checkNow: @escaping () async -> Available?) {
        self.checkNow = checkNow
    }

    package func found(_ update: Available) {
        available = update
    }

    /// Settings button: explicit check, spinner while it runs, and an honest
    /// "estás al día" is simply the row staying as it was.
    package func requestCheck() {
        guard !checking else { return }
        checking = true
        Task {
            if let update = await checkNow() { available = update }
            checking = false
        }
    }
}
