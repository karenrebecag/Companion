import CompanionCore
import Foundation

/// How an approved delete reaches the disk. Injected so the tests never fill
/// the real Trash or erase anything outside their own temp folder.
package struct FileDisposal: Sendable {
    let trash: @Sendable (URL) throws -> Void
    let remove: @Sendable (URL) throws -> Void

    package init(
        trash: @escaping @Sendable (URL) throws -> Void,
        remove: @escaping @Sendable (URL) throws -> Void
    ) {
        self.trash = trash
        self.remove = remove
    }

    package static let system = FileDisposal(
        trash: { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) },
        remove: { try FileManager.default.removeItem(at: $0) })
}

extension NativeToolRunner {
    /// Trash first; the permanent delete only when the Trash refuses, and the
    /// result says which one happened. The approval gate in `execute` has
    /// already run: nothing here asks. Results are English for the model
    /// whatever the user's language; only the denial is localized.
    func deleteFile(arguments: [String: Any]) -> ToolResult {
        guard let path = arguments["path"] as? String, !path.isEmpty else {
            return ToolResult(ok: false, output: "Missing path argument")
        }
        // The sheet strips these scalars from what it shows; a path that holds
        // any would show one name and delete another.
        guard ApprovalCopy.plainPreview(path, keepingLayout: false) == path else {
            return ToolResult(ok: false, output: "Path contains control or invisible characters")
        }
        let target: String
        switch writeBarrier(path) {
        case .success(let resolved): target = resolved
        case .failure(let refused): return refused
        }
        // The sheet shows the path as given. If resolving moved it anywhere
        // (a link in any component), the file that goes is not the one named.
        // HACK: checked by path, not held open (no openat/O_NOFOLLOW up to the trash).
        // Hold a descriptor if deletes ever run unattended or other processes are in the threat model.
        guard target == lexicalPath(path) else {
            return ToolResult(ok: false, output: "That path goes through a symbolic link; use the real path of the file")
        }
        let kind = Self.attributes(target)?[.type] as? FileAttributeType
        guard !isProtected(target, kind: kind) else {
            return ToolResult(ok: false, output: "Refusing to delete a protected location: a folder directly in the home folder, hidden entries, Library, or Companion's own data")
        }
        guard let kind else {
            return ToolResult(ok: false, output: "Nothing at that path")
        }
        guard kind == .typeRegular || kind == .typeDirectory else {
            return ToolResult(ok: false, output: "Only files and folders can be deleted")
        }
        let url = URL(fileURLWithPath: target)
        do {
            try disposal.trash(url)
            return ToolResult(ok: true, output: "Moved to the Trash; the user can put it back")
        } catch {
            // Any Trash error falls through to a permanent delete, not only
            // "no Trash on this volume": parity with Incredible, which does the
            // same. The user was told on the sheet, and the result says it.
            Log.app("delete_file: trash failed (\(Self.code(error))), trying a permanent delete")
        }
        do {
            try disposal.remove(url)
            return ToolResult(
                ok: true,
                output: "The Trash was not available, so it was deleted permanently and cannot be put back")
        } catch {
            Log.app("delete_file: permanent delete failed (\(Self.code(error)))")
            let partial = kind == .typeDirectory
                ? "; a folder is removed item by item, so the delete may be partial and some of its contents may already be gone"
                : ""
            return ToolResult(
                ok: false, output: "Could not delete it: the Trash and a permanent delete both failed\(partial)")
        }
    }

    /// The path as the sheet showed it, made absolute and standardized, with
    /// the working folder resolved the same way `writeBarrier` resolves.
    private func lexicalPath(_ path: String) -> String {
        let absolute = path.hasPrefix("/")
            ? path
            : (((workdir ?? ".") as NSString).resolvingSymlinksInPath as NSString).appendingPathComponent(path)
        return (absolute as NSString).standardizingPath
    }

    /// Compared case-insensitively on every volume: refusing a case variant
    /// on a case-sensitive disk is the safe side of the same rule.
    private func isProtected(_ target: String, kind: FileAttributeType?) -> Bool {
        let path = target.lowercased()
        let home = self.home.lowercased()
        let roots = pathValidator.roots.map { (($0.path as NSString).resolvingSymlinksInPath).lowercased() }
        if path == "/" || path == home { return true }
        // The target is a root, or a folder that holds one.
        if roots.contains(where: { $0 == path || $0.hasPrefix(path + "/") }) { return true }
        // Companion's memory, skills and knowledge: Hands must not erase the
        // app's own data through a file tool.
        if let app = skills.map({ ($0.root.path as NSString).resolvingSymlinksInPath.lowercased() }),
           path == app || path.hasPrefix(app + "/") { return true }
        guard path.hasPrefix(home + "/") else { return false }
        let inside = path.dropFirst(home.count + 1).split(separator: "/").map(String.init)
        guard let first = inside.first else { return true }
        return first.hasPrefix(".") || first == "library" || (inside.count == 1 && kind == .typeDirectory)
    }

    private static func code(_ error: Error) -> String {
        let ns = error as NSError
        return "\(ns.domain) \(ns.code)"
    }
}
