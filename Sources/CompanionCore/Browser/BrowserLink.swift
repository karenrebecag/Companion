import Foundation

/// Wave 18-4b. What Settings shows about the browser link, in Core so the
/// host (Services) and the panel (UI) agree without either importing the other.
package enum BrowserLinkStatus: Sendable, Equatable {
    case notInstalled
    case disconnected
    case connected(BrowserKind)
}

/// What a connect or remove press ended in. The installer's own errors never
/// cross into the UI; each becomes one line the user can act on.
package enum BrowserLinkOutcome: Sendable, Equatable {
    case done
    /// The app runs from a translocated or mounted path a manifest cannot keep.
    case moveApp
    case noBrowser
    case symlink
    case failed
}
