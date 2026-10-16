import Foundation

// A local file the reply or a receipt names. The chip shows the name; the path
// is kept only for the actions that need it (open, reveal in Finder).

package struct FileChip: Sendable, Equatable {
    /// As the model wrote it, without a trailing slash: "~/…", "/…" or "dir/…".
    package let path: String
    /// The last path part: the only thing the text shows.
    package let name: String

    /// A URL, a sentence or the root folder is not a file: it stays text. A
    /// name with no folder part ("notas.md") is not a path either: the model
    /// names the file in prose, and the receipt says it by name.
    package init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.contains("://"), !text.contains(where: \.isNewline),
              text.contains("/")
        else { return nil }
        if text.count > 1, text.hasSuffix("/") { text.removeLast() }
        let last = (text as NSString).lastPathComponent
        guard !last.isEmpty, last != "/", last != "~" else { return nil }
        self.path = text
        self.name = last
    }

    /// The home folder folded to "~", for the tooltip only; never in the text.
    package static func tooltip(_ path: String, home: String) -> String {
        guard !home.isEmpty, path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    /// The path the actions open, read as every file tool reads a bare name:
    /// the working folder first, then home, so the chip opens the file the
    /// model read.
    package static func resolved(_ path: String, workdir: String?, home: String) -> String {
        PathValidator(workdir: workdir, extraRoots: [], wholeDisk: true, home: home).absolute(path)
    }

    /// What a click does. A program or script is shown in Finder, never run
    /// from a chip; a protected path does nothing.
    package static func action(for resolved: String, home: String, runnable: (String) -> Bool) -> FileChipAction {
        if PathValidator(workdir: nil, extraRoots: [], wholeDisk: true, home: home).isProtected(resolved) {
            return .none
        }
        let ext = (resolved as NSString).pathExtension.lowercased()
        if FileChipAction.launcherExtensions.contains(ext) || runnable(resolved) { return .revealOnly }
        return .open
    }

    /// A regular file with the execute bit. Folders always have it, so they are not runnable.
    package static func isRunnable(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue
        else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }
}

package enum FileChipAction: Equatable, Sendable {
    case open, revealOnly, none

    /// Programs, scripts and installers: the chip shows them, it never runs them.
    static let launcherExtensions: Set<String> = [
        "app", "command", "tool", "terminal", "sh", "bash", "zsh", "pkg", "mpkg", "workflow", "action",
        "scpt", "scptd", "applescript", "webloc", "inetloc", "fileloc",
    ]
}

/// The symbol that tells a person what kind of thing a row or chip is.
package enum FileSymbol {
    package static func name(forFileNamed name: String, isFolder: Bool) -> String {
        if isFolder { return "folder" }
        switch (name as NSString).pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "svg", "tif", "tiff": return "photo"
        case "mp4", "mov", "m4v", "avi", "mkv": return "film"
        case "mp3", "wav", "m4a", "aac", "flac": return "music.note"
        case "pdf": return "doc.richtext"
        case "zip", "tar", "gz", "tgz", "7z", "rar", "dmg": return "archivebox"
        case "csv", "xlsx", "numbers": return "tablecells"
        case "txt", "md", "rtf", "doc", "docx", "pages": return "doc.text"
        case "swift", "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "java", "kt", "c", "h", "cpp",
             "m", "sh", "json", "yaml", "yml", "toml", "html", "css":
            return "chevron.left.forwardslash.chevron.right"
        default: return "doc"
        }
    }
}
