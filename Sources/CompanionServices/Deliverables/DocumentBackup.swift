import CompanionCore
import Foundation

/// The copy that comes before overwriting a user's file (sheet_write and
/// create_document share it). It copies what the path resolves to: a copied
/// symlink would track the live file and protect nothing.
enum DocumentBackup {
    /// The backup's path; throws when the copy could not be made.
    static func copy(of path: String, at date: Date = Date()) throws -> String {
        let real = (path as NSString).resolvingSymlinksInPath
        let backup = SheetBackup.path(for: real, at: date)
        try FileManager.default.copyItem(atPath: real, toPath: backup)
        return backup
    }
}
