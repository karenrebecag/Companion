import CompanionCore
import Foundation

// H-7 PR4c: list_file_history and restore_file_version. The model names a
// version by an opaque id, never by a path into the private store.

extension NativeToolRunner {
    func listFileHistory(arguments: [String: Any]) -> ToolResult {
        guard let versions else { return ToolResult(ok: false, output: "File history is unavailable") }
        guard let path = arguments["path"] as? String, !path.isEmpty else {
            return ToolResult(ok: false, output: "Missing path argument")
        }
        guard pathValidator.isAllowed(path) else {
            return ToolResult(ok: false, output: "Path outside working directory")
        }
        let real = resolveRealPath(path)
        guard pathValidator.isAllowed(real) else {
            return ToolResult(ok: false, output: "Resolved path outside working directory")
        }
        let kept = Self.historyEntries(versions, real)
        guard !kept.isEmpty else { return ToolResult(ok: true, output: "No saved versions of that file") }
        let stamp = ISO8601DateFormatter()
        let lines = kept.map { entry -> String in
            let when = entry.version.trigger == FileVersions.Trigger.preSave ? "pre-save" : "post-save"
            return "\(entry.id)  \(stamp.string(from: entry.version.date))  \(when)"
        }
        return ToolResult(
            ok: true,
            output: "Versions, newest first (id, time, when it was kept); only an existing file can be restored:\n"
                + lines.joined(separator: "\n"))
    }

    private struct RestoreTarget {
        let real: String
        let chosen: HistoryEntry
    }

    private enum RestoreResolution {
        case target(RestoreTarget)
        case refused(ToolResult)
    }

    /// The approval gate in `execute` has already run. Fail-closed: the file is only
    /// overwritten after a copy of what is there now is safely kept, because this is
    /// the one write that replaces the user's content with old data. `write` is the
    /// seam for a write that dies halfway.
    func restoreFileVersion(
        arguments: [String: Any],
        write: (String, Data) throws -> Void = NativeToolRunner.overwriteInPlace,
        read: (URL) throws -> Data = { try Data(contentsOf: $0) }
    ) -> ToolResult {
        guard let versions else { return ToolResult(ok: false, output: "File history is unavailable") }
        let target: RestoreTarget
        switch resolveRestoreTarget(arguments, versions) {
        case .target(let resolved): target = resolved
        case .refused(let refused): return refused
        }
        // Read before the copy: the copy can push the oldest version out of a full
        // history, and that may be the very one being restored.
        let bytes: Data
        do { bytes = try read(target.chosen.version.url) } catch {
            return ToolResult(ok: false, output: "That version is no longer available")
        }
        let copy: URL
        switch versions.snapshot(target.real, trigger: .preSave) {
        case .saved(let url): copy = url
        case .tooLarge:
            return ToolResult(
                ok: false,
                output: "The current file is too large to keep a copy of (over "
                    + "\(FileVersions.defaultMaxBytes / 1024 / 1024) MB), so nothing was restored")
        case .noPrevious, .failed:
            return ToolResult(
                ok: false, output: "A copy of the current file could not be kept first, so nothing was restored")
        }
        let undo = Self.entryID(copy).map { "; to undo, restore version \($0)" } ?? ""
        do {
            try write(target.real, bytes)
            return ToolResult(ok: true, output: "Restored the file; a copy of the previous content was kept\(undo)")
        } catch {
            Log.app("restore_file_version: write failed")
            return recoverFailedRestore(target.real, from: copy, undo: undo)
        }
    }

    /// A write that fails can leave the file truncated: put the copy back once, and
    /// say whether the file is whole either way.
    private func recoverFailedRestore(_ real: String, from copy: URL, undo: String) -> ToolResult {
        let kept: Data
        do { kept = try Data(contentsOf: copy) } catch {
            return ToolResult(ok: false, output: "The restore failed while writing and the file may be incomplete\(undo)")
        }
        do {
            try Self.overwriteInPlace(real, with: kept)
            return ToolResult(ok: false, output: "The restore failed while writing; the file was put back and is intact")
        } catch {
            var intact = false
            do { intact = try Data(contentsOf: URL(fileURLWithPath: real)) == kept } catch {}
            return ToolResult(
                ok: false,
                output: intact
                    ? "The restore failed while writing; the file is intact"
                    : "The restore failed while writing and the file may be incomplete\(undo)")
        }
    }

    private func resolveRestoreTarget(_ arguments: [String: Any], _ versions: FileVersions) -> RestoreResolution {
        guard let path = arguments["path"] as? String, !path.isEmpty,
              let id = arguments["version"] as? String, !id.isEmpty else {
            return .refused(ToolResult(ok: false, output: "invalid_args: path and version are required"))
        }
        // The sheet strips these scalars from what it shows; a path that holds any
        // would show one name and restore another.
        guard ApprovalCopy.plainPreview(path, keepingLayout: false) == path else {
            return .refused(ToolResult(ok: false, output: "Path contains control or invisible characters"))
        }
        let real: String
        switch writeBarrier(path) {
        case .success(let resolved): real = resolved
        case .failure(let refused): return .refused(refused)
        }
        guard !isHidden(real) else {
            return .refused(ToolResult(ok: false, output: "Refusing to restore over a hidden entry"))
        }
        guard Self.attributes(real)?[.type] as? FileAttributeType == .typeRegular else {
            return .refused(ToolResult(
                ok: false,
                output: "That file does not exist or is not a regular file; only an existing file can be restored"))
        }
        // Matched against this file's own history by id, never built into a path: a
        // forged id, or one from another file, simply is not in the list.
        let matches = Self.historyEntries(versions, real).filter { $0.id == id }
        guard matches.count == 1, let chosen = matches.first else {
            return .refused(ToolResult(
                ok: false, output: "Unknown version for that file; call list_file_history for its ids"))
        }
        guard Self.attributes(chosen.version.url.path)?[.type] as? FileAttributeType == .typeRegular else {
            return .refused(ToolResult(ok: false, output: "That version is no longer available"))
        }
        return .target(RestoreTarget(real: real, chosen: chosen))
    }

    /// The sheet's copy of a restore: the version and the real file as this runner resolves
    /// them. Whatever the model put under those keys is dropped first, so only the runner
    /// speaks there; the parent's ticket stays parked on the model's own arguments.
    func restoreSheetJSON(_ json: String) -> String {
        var object = ToolArguments.parse(json) ?? [:]
        object["restore_when"] = nil
        object["restore_real"] = nil
        if let info = restoreApprovalInfo(object) {
            object["restore_when"] = info.when
            object["restore_real"] = info.real
        }
        do {
            return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
        } catch {
            return "{}"
        }
    }

    /// What the approval sheet shows about a restore, resolved here because the sheet's
    /// copy has no store: the chosen version's time and trigger, and where the path
    /// really lands. Nil when the call would be refused anyway.
    func restoreApprovalInfo(_ arguments: [String: Any]) -> (when: String, real: String)? {
        guard let versions, case .target(let target) = resolveRestoreTarget(arguments, versions) else { return nil }
        let version = target.chosen.version
        let trigger = version.trigger == FileVersions.Trigger.preSave ? "pre-save" : "post-save"
        return ("\(ISO8601DateFormatter().string(from: version.date)), \(trigger)", target.real)
    }

    static func overwriteInPlace(_ path: String, with data: Data) throws {
        // O_NONBLOCK: a file swapped for a FIFO must not block the open; fstat then refuses it.
        let fd = open(path, O_WRONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { throw POSIXError(.EPERM) }
        guard ftruncate(fd, 0) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        try FileHandle(fileDescriptor: fd, closeOnDealloc: false).write(contentsOf: data)
    }

    private struct HistoryEntry {
        let id: String
        let version: FileVersions.Version
    }

    /// The unique segment of a stored name: stable while newer copies arrive, unlike a position.
    private static func entryID(_ url: URL) -> String? {
        let parts = url.lastPathComponent.split(separator: "-", maxSplits: 3, omittingEmptySubsequences: false)
        return parts.count == 4 ? String(parts[2]) : nil
    }

    /// Newest first.
    private static func historyEntries(_ versions: FileVersions, _ real: String) -> [HistoryEntry] {
        versions.versions(of: real).reversed().compactMap { version in
            entryID(version.url).map { HistoryEntry(id: $0, version: version) }
        }
    }

    /// Judged below the working folder: a hidden folder above it is the user's choice.
    private func isHidden(_ real: String) -> Bool {
        var path = real
        if pathValidator.isInWorkdir(real), let workdir {
            let root = ((workdir as NSString).standardizingPath as NSString).resolvingSymlinksInPath
            if real.hasPrefix(root + "/") { path = String(real.dropFirst(root.count + 1)) }
        }
        return path.split(separator: "/").contains { $0.hasPrefix(".") }
    }
}
