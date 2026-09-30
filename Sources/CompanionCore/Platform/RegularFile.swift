import Foundation

/// A file she picked is a regular file: a directory measures a few bytes and
/// copies as a whole tree, and a symlink is a path that no longer says what is
/// behind it. One rule for the attachment store and the feedback modal.
public enum RegularFile {
    /// False also when the file cannot be read: callers treat both as "not a
    /// file she can attach".
    public static func isRegular(_ url: URL) -> Bool {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        } catch {
            return false
        }
        return values.isRegularFile == true && values.isSymbolicLink != true
    }
}
