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
        if let bundle = Self.bundles().first(where: { Self.name(of: $0) == name }) {
            do {
                _ = try await NSWorkspace.shared.openApplication(
                    at: bundle, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                throw .notFound("could not launch \(name): \(error.localizedDescription)")
            }
            return
        }
        // Running but installed elsewhere (a build folder, a disk image):
        // bringing it to the front is still opening it.
        if let running = NSWorkspace.shared.runningApplications
            .first(where: { $0.localizedName == name }) {
            guard running.activate() else {
                throw .notFound("could not bring \(name) to the front")
            }
            return
        }
        throw .notFound("no app named \(name)")
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

    private static func name(of bundle: URL) -> String {
        bundle.deletingPathExtension().lastPathComponent
    }
}
