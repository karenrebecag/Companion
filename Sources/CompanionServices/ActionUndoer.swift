import CompanionCore
import Foundation

/// Wave 20d B. Takes back what an action did without asking, when the user
/// presses Undo. Nothing here is reachable from a tool call: the only caller
/// is the island's button, through the composition root.
public struct ActionUndoer: Sendable {
    private let sheets: (any SpreadsheetDriving)?
    private let trash: @Sendable (URL) throws -> Void

    public init(
        sheets: (any SpreadsheetDriving)?,
        trash: @escaping @Sendable (URL) throws -> Void = { url in
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    ) {
        self.sheets = sheets
        self.trash = trash
    }

    public func undo(_ step: ActionReceipt.Undo) async -> Bool {
        switch step {
        case .trash(let path, let size, let modified):
            guard path.hasPrefix("/"), Self.unchanged(path, size: size, modified: modified) else { return false }
            do {
                try trash(URL(fileURLWithPath: path))
                return true
            } catch {
                Log.app("undo: trash failed")
                return false
            }
        case .clearCells(let app, let a1, let workbook, let expected):
            guard let sheets, let range = SheetRange(a1: a1) else { return false }
            do {
                // The same rule as the write: only the workbook that was written.
                guard try await sheets.workbook(app) == workbook,
                      try await sheets.read(app, range: range) == expected else { return false }
                let empty = Array(repeating: Array(repeating: SheetCell.empty, count: range.columns), count: range.rows)
                _ = try await sheets.write(app, range: range, cells: empty, workbook: workbook)
                return true
            } catch {
                Log.app("undo: clearing cells failed")
                return false
            }
        }
    }

    /// A regular file, still as the action left it: a directory, a link or a
    /// file the user has since edited is not ours to trash.
    private static func unchanged(_ path: String, size: Int, modified: Date) -> Bool {
        guard let attributes = NativeToolRunner.attributes(path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue == size,
              attributes[.modificationDate] as? Date == modified else { return false }
        return true
    }
}
