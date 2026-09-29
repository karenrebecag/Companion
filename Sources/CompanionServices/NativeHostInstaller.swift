import CompanionCore
import Foundation

/// Wave 18-4a, ADR 007. Writes the Chrome native messaging host manifest into
/// another app's config folder. It only runs from the Settings button and
/// `remove` undoes it; nothing here is called at launch.
public struct NativeHostInstaller {
    public enum Failure: Error, Equatable {
        case symlinkAtDestination(BrowserKind)
        case unstableExecutablePath
    }

    static let hostName = "com.karen.companion.browser"
    private static let fileName = hostName + ".json"

    // Order is the order of every returned list.
    private static let supportPaths: [(BrowserKind, String)] = [
        (.chrome, "Library/Application Support/Google/Chrome"),
        (.comet, "Library/Application Support/Comet"),
    ]

    private let home: URL
    private let executable: URL
    private let fileManager: FileManager

    public init(home: URL, executable: URL, fileManager: FileManager = .default) {
        self.home = home
        self.executable = executable
        self.fileManager = fileManager
    }

    private func browserDir(_ relative: String) -> URL {
        home.appendingPathComponent(relative, isDirectory: true)
    }

    private func manifestURL(_ relative: String) -> URL {
        browserDir(relative)
            .appendingPathComponent("NativeMessagingHosts", isDirectory: true)
            .appendingPathComponent(Self.fileName)
    }

    /// A browser counts as present only if its own support folder exists, so
    /// a browser the user never installed never gets a folder created for it.
    public func detected() -> [BrowserKind] {
        Self.supportPaths.filter { isDirectory(browserDir($0.1)) }.map(\.0)
    }

    public func installed() -> [BrowserKind] {
        Self.supportPaths.filter { isOurs(manifestURL($0.1)) }.map(\.0)
    }

    public func install() throws -> [BrowserKind] {
        let data = try Self.manifestData(path: try stablePath())
        var done: [BrowserKind] = []
        for (kind, relative) in Self.supportPaths where isDirectory(browserDir(relative)) {
            let url = manifestURL(relative)
            try refuseSymlink(url, kind)
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            // Chrome runs as the same user but a restrictive umask must not hide the file from it.
            try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
            done.append(kind)
        }
        return done
    }

    public func remove() throws -> [BrowserKind] {
        var done: [BrowserKind] = []
        for (kind, relative) in Self.supportPaths {
            let url = manifestURL(relative)
            try refuseSymlink(url, kind)
            guard isOurs(url) else { continue }
            try fileManager.removeItem(at: url)
            done.append(kind)
        }
        return done
    }

    // MARK: Helpers

    /// The manifest outlives this launch, and the browser will run whatever it
    /// names. A relative, missing or non-executable path never works, and a
    /// Gatekeeper translocation path (a randomized read-only mount) is gone
    /// after the next launch, so the UI is told to move the app instead.
    private func stablePath() throws -> String {
        let marker = "/AppTranslocation/"
        guard executable.path.hasPrefix("/"), !executable.path.contains(marker) else {
            throw Failure.unstableExecutablePath
        }
        let resolved = executable.resolvingSymlinksInPath().path
        var isDir: ObjCBool = false
        guard !resolved.contains(marker),
              fileManager.fileExists(atPath: resolved, isDirectory: &isDir), !isDir.boolValue,
              fileManager.isExecutableFile(atPath: resolved)
        else { throw Failure.unstableExecutablePath }
        return resolved
    }

    static func manifestData(path: String) throws -> Data {
        let manifest: [String: Any] = [
            "name": hostName,
            "description": "Companion",
            "path": path,
            "type": "stdio",
            "allowed_origins": BrowserPolicy.pinnedOrigins.sorted(),
        ]
        return try JSONSerialization.data(
            withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// `attributesOfItem` does not traverse the final component, so a link is seen as a link.
    private func refuseSymlink(_ url: URL, _ kind: BrowserKind) throws {
        let type: FileAttributeType?
        do {
            type = try fileManager.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
        } catch {
            return // nothing at the destination yet
        }
        if type == .typeSymbolicLink { throw Failure.symlinkAtDestination(kind) }
    }

    /// Unreadable or foreign content is treated as not ours so it is never deleted.
    private func isOurs(_ url: URL) -> Bool {
        guard let data = fileManager.contents(atPath: url.path) else { return false }
        do {
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return object?["name"] as? String == Self.hostName
        } catch {
            return false
        }
    }
}
