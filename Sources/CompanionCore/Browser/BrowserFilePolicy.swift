import Foundation

/// What `browser_set_files` may hand to a page. `ParentToolPolicy.homePath`
/// is the shared door (under `$HOME`, no hidden component after `realpath`,
/// no launcher, must exist). Uploading is narrower than opening a document:
/// `~/Library` holds keychains and mail, a Photos library is a package whose
/// name does not start with `.` so the hidden-component rule never sees it,
/// and a directory's reported size is not the file the page would receive.
package enum BrowserFilePolicy: Sendable {
    /// What the sheet showed, as the kernel reports it. Compared again just
    /// before the send: any difference means the user approved another file.
    package struct File: Sendable, Equatable {
        /// `homePath`'s resolved path: the one judged, shown and sent.
        package var path: String
        package var device: Int64
        package var inode: UInt64
        package var size: Int64
        /// Integer nanoseconds since the epoch: a Double loses the low bits
        /// that tell two quick rewrites apart.
        package var mtime: Int64
        /// Userspace cannot set `ctime`, so it still moves when an in-place
        /// overwrite keeps the inode and puts `mtime` back.
        package var ctime: Int64
    }

    /// Key material and vaults. The last extension only: `report.pdf.bak` is
    /// a document, and `homePath` already refused launchers.
    private static let deniedExtensions: Set<String> = [
        "pem", "key", "p12", "pfx", "kdbx", "keychain", "keychain-db", "ovpn",
    ]

    package static func judge(_ raw: String, home: URL) throws(ContractError) -> File {
        try rejectDeceptive(raw)
        try rejectLibrary(lexicalPath(raw, home: home), home: home)
        let url = try ParentToolPolicy.homePath(raw, home: home)
        let path = url.path
        try rejectDeceptive(path)
        try rejectLibrary(path, home: home)
        try rejectPhotosLibrary(path)
        try rejectExtension(path)
        let file = try identity(path)
        guard file.size <= Int64(AttachmentPolicy.maxBytes) else {
            throw ContractError(
                code: BridgeCode.fileTooLarge,
                message: "file is larger than \(BrowserCopy.maxMegabytes) MB")
        }
        return file
    }

    /// The sheet prints the path with these scalars stripped; a path that
    /// changes under that is a name built to read as another one.
    private static func rejectDeceptive(_ path: String) throws(ContractError) {
        if ApprovalCopy.plainPreview(path, keepingLayout: false) != path {
            throw .deniedPath("a path with control or invisible characters cannot be uploaded")
        }
    }

    /// The input as `homePath` first reads it, before any lookup, so the
    /// Library answer cannot depend on whether the file exists.
    private static func lexicalPath(_ raw: String, home: URL) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = home.standardizedFileURL.path
        let expanded: String
        if text == "~" {
            expanded = base
        } else if text.hasPrefix("~/") {
            expanded = base + text.dropFirst(1)
        } else if text.hasPrefix("/") {
            expanded = text
        } else {
            expanded = base + "/" + text
        }
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    /// Both spellings of home: `homePath` resolves with realpath, so a home
    /// under `/var` also appears as `/private/var`. Only the first component:
    /// `~/Documents/Library` is a folder the user made.
    private static func rejectLibrary(_ path: String, home: URL) throws(ContractError) {
        let lexical = home.standardizedFileURL.path
        var bases = [lexical]
        if let cString = realpath(lexical, nil) {
            defer { free(cString) }
            bases.append(String(cString: cString))
        }
        if bases.contains(where: { isLibrary(path, under: $0) }) {
            throw .deniedPath("files inside ~/Library cannot be uploaded")
        }
    }

    private static func isLibrary(_ path: String, under rawBase: String) -> Bool {
        let base = (rawBase.hasSuffix("/") ? String(rawBase.dropLast()) : rawBase).lowercased()
        let folded = path.lowercased()
        guard folded.hasPrefix(base + "/") else { return false }
        let first = folded.dropFirst(base.count).split(separator: "/", omittingEmptySubsequences: true).first
        return first == "library"
    }

    private static func rejectPhotosLibrary(_ path: String) throws(ContractError) {
        let inside = path.split(separator: "/").contains { component in
            (component as NSString).pathExtension.lowercased() == "photoslibrary"
        }
        if inside {
            throw .deniedPath("files inside a Photos library cannot be uploaded")
        }
    }

    /// Trailing spaces and dots are dropped before the extension is read:
    /// `secret.pem ` and `secret.pem.` are still a PEM to the page.
    private static func rejectExtension(_ path: String) throws(ContractError) {
        let leaf = (path as NSString).lastPathComponent
        let trimmed = leaf.trimmingCharacters(in: CharacterSet(charactersIn: " .").union(.whitespaces))
        let ext = (trimmed as NSString).pathExtension.lowercased()
        if deniedExtensions.contains(ext) {
            throw .deniedPath("that file type cannot be uploaded")
        }
    }

    /// `lstat` never follows a symlink planted where the resolved path was.
    /// Only a rename-replace gets a new inode; an in-place overwrite keeps it,
    /// which is why `ctime` is part of the identity.
    // HACK: the browser opens the file by path, so a swap after the last
    // recheck is not caught. Pass a descriptor or the bytes instead of a path
    // when that window matters.
    private static func identity(_ path: String) throws(ContractError) -> File {
        var raw = stat()
        guard lstat(path, &raw) == 0 else {
            throw .notFound("path does not exist: \(path)")
        }
        guard (raw.st_mode & S_IFMT) == S_IFREG else {
            throw .deniedPath("only a regular file can be uploaded")
        }
        guard raw.st_nlink <= 1 else {
            throw .deniedPath("a hard-linked file cannot be uploaded")
        }
        return File(
            path: path, device: Int64(raw.st_dev), inode: UInt64(raw.st_ino),
            size: Int64(raw.st_size), mtime: nanoseconds(raw.st_mtimespec),
            ctime: nanoseconds(raw.st_ctimespec))
    }

    /// Saturates instead of trapping: some filesystems report far-future or
    /// pre-1677 times that anyone can set with `touch`. The value is only an
    /// identity to compare, so a pinned extreme is as good as the exact one
    /// and still differs from any ordinary mtime; refusing the file would let
    /// a timestamp decide whether a document can be uploaded.
    package static func nanoseconds(_ spec: timespec) -> Int64 {
        let seconds = Int64(spec.tv_sec)
        let (scaled, scaleOverflow) = seconds.multipliedReportingOverflow(by: 1_000_000_000)
        if scaleOverflow { return seconds < 0 ? Int64.min : Int64.max }
        let (total, sumOverflow) = scaled.addingReportingOverflow(Int64(spec.tv_nsec))
        return sumOverflow ? Int64.max : total
    }
}
