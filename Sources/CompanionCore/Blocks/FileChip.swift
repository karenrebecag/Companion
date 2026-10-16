import Foundation

// A local file the reply or a receipt names. The chip shows the name; the path
// is kept only for the actions that need it (open, reveal in Finder).

package struct FileChip: Sendable, Equatable {
    /// As the model wrote it, without a trailing slash: "~/…" or "/…".
    package let path: String
    /// The last path part: the only thing the text shows.
    package let name: String

    /// A URL, a sentence or the root folder is not a file: it stays text.
    package init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.contains("://"), !text.contains(where: \.isNewline),
              text.hasPrefix("/") || text.hasPrefix("~/")
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

    /// The path the actions open: "~/" expanded against the home folder.
    package static func expanded(_ path: String, home: String) -> String {
        path.hasPrefix("~/") ? home + path.dropFirst(1) : path
    }
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
