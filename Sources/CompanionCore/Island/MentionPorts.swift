import Foundation

/// The system's answer about the address book, without asking anything.
package enum ContactsAccess: Sendable, Equatable {
    case notDetermined, granted, denied
}

/// The address book as the selector needs it: search by name, and the ways
/// to reach ONE contact once she asks. Nothing lists the book.
package protocol ContactsProviding: Sendable {
    func access() -> ContactsAccess
    /// Shows the system dialog when the answer is still open; the only call
    /// that can. Returns whether the book may be read afterwards.
    func requestAccess() async -> Bool
    /// Names that match, at most `limit`; empty without permission.
    func search(_ query: String, limit: Int) async -> [MentionCandidate]
    /// Email addresses and phone numbers of the one contact she opened.
    func channels(ofContact id: String) async -> [MentionChannel]
}

/// Everything the selector can offer. Contacts are optional (no permission
/// entry, no book); apps and files never need one.
package struct MentionSources: Sendable {
    package let contacts: (any ContactsProviding)?
    package let connectedApps: @Sendable () async -> [MentionCandidate]
    package let recentFiles: @Sendable () async -> [MentionCandidate]

    package init(
        contacts: (any ContactsProviding)?,
        connectedApps: @escaping @Sendable () async -> [MentionCandidate],
        recentFiles: @escaping @Sendable () async -> [MentionCandidate]
    ) {
        self.contacts = contacts
        self.connectedApps = connectedApps
        self.recentFiles = recentFiles
    }
}

/// Which recent files the selector may offer. Only files inside the user's
/// home that are not hidden, not in Library and not inside a package: a
/// mention attaches the file, so what is offered must be something she
/// would attach by hand.
package enum MentionFiles {
    /// Directories that Finder shows as one file. A mention attaches by
    /// copying, so none of them is ever offered.
    static let packageExtensions: Set<String> = [
        "app", "bundle", "framework", "plugin", "xpc", "appex", "kext",
        "photoslibrary", "musiclibrary", "tvlibrary", "imovielibrary", "fcpbundle",
    ]

    static func isPackage(_ component: String) -> Bool {
        guard let dot = component.lastIndex(of: "."), dot != component.startIndex else { return false }
        return packageExtensions.contains(component[component.index(after: dot)...].lowercased())
    }

    package static func candidate(path: String, home: String) -> MentionCandidate? {
        let prefix = home.hasSuffix("/") ? home : home + "/"
        guard path.hasPrefix(prefix), !path.hasSuffix("/") else { return nil }
        let parts = path.dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 1, !parts.contains(where: \.isEmpty), !parts.contains("..") else { return nil }
        // Any component: a package is a directory that looks like a file, and
        // copying one would take the whole tree (also as the LAST component).
        for part in parts where isPackage(part) { return nil }
        guard !parts.contains(where: { $0.hasPrefix(".") }), parts.first != "Library" else { return nil }
        let folder = parts.count >= 2 ? parts[parts.count - 2] : nil
        return MentionCandidate(id: path, kind: .file, name: parts[parts.count - 1], detail: folder)
    }
}
