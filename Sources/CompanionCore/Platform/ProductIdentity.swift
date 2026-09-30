import Foundation

/// Who the app says it is: bundle id, the name in the Finder, and the log it
/// writes. Two builds coexist on the author's Mac — the shipped product and
/// the one being worked on — and the scar this encodes is that two apps
/// sharing a bundle id make LaunchServices open whichever it resolved first.
///
/// The strings live here and `scripts/bundle.sh` is checked against them: a
/// plist written by bash that drifts from the source installs an app whose
/// own code does not recognise it.
package enum ProductIdentity: Sendable, Equatable, CaseIterable {
    case release
    case development

    package var bundleID: String {
        switch self {
        case .release: "com.karen.companion"
        case .development: "com.karen.companion.next"
        }
    }

    package var displayName: String {
        switch self {
        case .release: "Companion"
        case .development: "Companion Next"
        }
    }

    /// Separate files on purpose: debugging a voice turn is unreadable when
    /// two builds interleave their lines.
    package var logFileName: String {
        switch self {
        case .release: "Companion.log"
        case .development: "CompanionNext.log"
        }
    }

    /// An unknown id (or none, as with `swift run`) is development: the
    /// product identity is claimed, never assumed.
    package static func of(bundleID: String?) -> ProductIdentity {
        bundleID == release.bundleID ? .release : .development
    }
}
