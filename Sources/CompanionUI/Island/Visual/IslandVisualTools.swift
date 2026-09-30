import AppKit
import CompanionCore

enum IslandVisualTools {
    /// The data as CSV rather than the fence's JSON: it pastes into Numbers
    /// or Sheets as the table behind the drawing, while the JSON is the
    /// wire format between the model and the client, not something to read.
    static func copy(_ block: ChartBlock, to board: NSPasteboard = .general) {
        guard !block.labels.isEmpty, !block.series.isEmpty else { return }
        board.clearContents()
        board.setString(block.csv, forType: .string)
    }
}
