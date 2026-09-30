import Foundation

/// Security review 2026-09-25 (CRITICAL-1): builds before the no-store
/// session left API keys and request bodies in the bundle's URL cache. This
/// removes that file set and nothing else — the app cleaning its own
/// Caches folder, never a path outside it.
package enum LegacyURLCachePurge {
    package struct Refusal: Error, Equatable {
        package let reason: String
    }

    static let legacyNames = ["Cache.db", "Cache.db-wal", "Cache.db-shm", "fsCachedData"]

    /// Returns how many legacy items were removed. A bundle id that is not a
    /// single plain path component is refused: it could point the removal
    /// outside the bundle's own folder.
    package static func purge(
        cachesDirectory: URL, bundleID: String,
        fileManager: FileManager = .default
    ) throws -> Int {
        guard isPlainComponent(bundleID) else {
            throw Refusal(reason: "bundle id is not a single path component")
        }
        let folder = cachesDirectory.appendingPathComponent(bundleID, isDirectory: true)
        guard isRealDirectory(folder, fileManager: fileManager) else { return 0 }
        var removed = 0
        for name in legacyNames {
            let item = folder.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: item.path)
                || isSymlink(item, fileManager: fileManager)
            else { continue }
            try fileManager.removeItem(at: item)
            removed += 1
        }
        return removed
    }

    /// Launch hook: empties the in-process shared cache, swaps it for one
    /// that can hold nothing (so no stray `URLCache.shared` use can write
    /// again), then removes the files on disk.
    package static func runAtLaunch(bundleID: String?) {
        URLCache.shared.removeAllCachedResponses()
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, directory: nil)
        guard let bundleID,
              let caches = FileManager.default.urls(
                for: .cachesDirectory, in: .userDomainMask).first
        else { return }
        do {
            if try purge(cachesDirectory: caches, bundleID: bundleID) > 0 {
                Log.app("cache: legacy url cache purged")
            }
        } catch {
            Log.app("cache: legacy url cache purge failed (\(type(of: error)))")
        }
    }

    private static func isPlainComponent(_ id: String) -> Bool {
        !id.isEmpty && id != "." && id != ".." && !id.contains("/")
    }

    private static func isRealDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        if isSymlink(url, fileManager: fileManager) { return false }
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func isSymlink(_ url: URL, fileManager: FileManager) -> Bool {
        do {
            let attrs = try fileManager.attributesOfItem(atPath: url.path)
            return attrs[.type] as? FileAttributeType == .typeSymbolicLink
        } catch {
            return false
        }
    }
}
