import Foundation

/// Wave 20d B. What an action that ran without the sheet leaves on the
/// island: what happened and the one mechanical way back. The undo is data
/// the runner filled from the target it just changed; the model never sees or
/// presses it.
public struct UndoReceipt: Sendable, Equatable, Identifiable {
    /// Seconds the way back stays offered.
    public static let undoWindow: TimeInterval = 5

    public enum Undo: Sendable, Equatable {
        /// A file the action created: it goes to the Trash, never `rm`. Size and
        /// date are what it was when the action finished; a file that changed
        /// since is the user's now and stays.
        case trash(path: String, size: Int, modified: Date)
        /// Cells that were empty before the write: they are emptied again, but
        /// only while they still show what the write left (`expected`).
        case clearCells(app: SheetApp, range: String, workbook: String, expected: [[String]])
    }

    /// The UI words it (a receipt in Services has no language): what was done
    /// to `subject`, a file name or a range.
    public enum Kind: Sendable, Equatable {
        case created, wrote, undone, couldNotUndo
    }

    /// One receipt at a time: a newer action replaces the offer to undo the
    /// older one, which is the safe direction for a five-second window.
    public let id: UUID
    public let kind: Kind
    public let subject: String
    public let undo: Undo?

    public init(id: UUID = UUID(), kind: Kind, subject: String, undo: Undo? = nil) {
        self.id = id
        self.kind = kind
        self.subject = subject
        self.undo = undo
    }
}
