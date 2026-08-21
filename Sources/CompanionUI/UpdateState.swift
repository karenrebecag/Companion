import CompanionCore
import Observation
import SwiftUI

/// What Settings shows about updates. The checker lives in Services; the
/// composition feeds results in and handles the on-demand check.
@Observable
@MainActor
public final class UpdateState {
    public struct Available: Equatable {
        public let tag: String
        public let pageURL: URL
        public init(tag: String, pageURL: URL) {
            self.tag = tag
            self.pageURL = pageURL
        }
    }

    public private(set) var available: Available?
    public private(set) var checking = false

    private let checkNow: () async -> Available?

    public init(checkNow: @escaping () async -> Available?) {
        self.checkNow = checkNow
    }

    public func found(_ update: Available) {
        available = update
    }

    /// Settings button: explicit check, spinner while it runs, and an honest
    /// "estás al día" is simply the row staying as it was.
    public func requestCheck() {
        guard !checking else { return }
        checking = true
        Task {
            if let update = await checkNow() { available = update }
            checking = false
        }
    }
}
