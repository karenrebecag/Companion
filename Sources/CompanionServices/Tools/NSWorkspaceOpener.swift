import AppKit
import CompanionCore
import Foundation

/// `WorkspaceOpening` over NSWorkspace. No subprocess, no `open -a`, no PATH
/// lookup: the app by name is found in the standard application folders and
/// among what is running, and the URL goes to whatever the user's default is.
package struct NSWorkspaceOpener: WorkspaceOpening {
    private static var roots: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            // Where Apple ships Safari now; /Applications only links to it.
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications"),
        ]
    }

    package init() {}

    package func openApplication(named name: String) async throws(ContractError) {
        let running = NSWorkspace.shared.runningApplications.first { app in
            !app.isTerminated && app.activationPolicy == .regular
                && (app.localizedName == name || app.bundleURL.map(Self.name(of:)) == name)
        }
        // Running but installed elsewhere (a build folder, a disk image, or
        // /System/Library/CoreServices, where Finder lives): its own bundle
        // is as good as a listed one.
        guard let bundle = Self.bundles().first(where: { Self.name(of: $0) == name })
            ?? running?.bundleURL
        else { throw .notFound("no app named \(name)") }
        // `activates` goes through LaunchServices, which can bring an app
        // forward for a background caller; `NSRunningApplication.activate()`
        // alone is a request macOS 14+ may ignore (cooperative activation).
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: bundle, configuration: configuration)
        } catch {
            throw .notFound("could not launch \(name): \(error.localizedDescription)")
        }
        guard let running, !running.isActive else { return }
        guard AppActivation.bringToFront(running) else {
            throw .notFound("could not bring \(name) to the front")
        }
    }

    package func applicationName(toOpen url: URL) -> String? {
        NSWorkspace.shared.urlForApplication(toOpen: url).map(Self.name(of:))
    }

    // HACK: check-then-act. The policy validated a path string; LaunchServices
    // resolves it again here, and a symlink swapped in between wins the race.
    // NSWorkspace has no fd- or bookmark-based open. Upgrade trigger: an API
    // that opens what was validated, not a path that names it.
    package func open(_ url: URL) async throws(ContractError) {
        guard NSWorkspace.shared.open(url) else {
            throw .notFound("could not open \(url.isFileURL ? url.path : url.absoluteString)")
        }
    }

    /// Only what the user would call an app: menu-bar agents and helpers
    /// (`.accessory`, `.prohibited`) are not something to "open".
    package func runningApplications() -> [String] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.localizedName)
    }

    package func installedApplications() -> [String] {
        Self.bundles().map(Self.name(of:))
    }

    /// By path, not by URL: on macOS 26 `/Applications/Safari.app` is a
    /// symlink into a cryptex and the URL enumeration with `.skipsHiddenFiles`
    /// drops it — "abre Safari" came back `not_found` on a Mac with Safari.
    /// `readdir` sees what the Finder sees.
    private static func bundles() -> [URL] {
        roots.flatMap { root -> [URL] in
            let names: [String]
            do {
                names = try FileManager.default.contentsOfDirectory(atPath: root.path)
            } catch {
                return []
            }
            return names
                .filter { $0.hasSuffix(".app") && !$0.hasPrefix(".") }
                .map { root.appendingPathComponent($0) }
        }
    }

    package func localizedApplicationNames() -> [String: String] {
        var names: [String: String] = [:]
        for bundle in Self.bundles() {
            let shown = FileManager.default.displayName(atPath: bundle.path)
            let localized = shown.hasSuffix(".app") ? String(shown.dropLast(4)) : shown
            let own = Self.name(of: bundle)
            if localized.lowercased() != own.lowercased() { names[localized.lowercased()] = own }
        }
        return names
    }

    private static func name(of bundle: URL) -> String {
        bundle.deletingPathExtension().lastPathComponent
    }
}
