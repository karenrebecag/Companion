import AppKit
import SwiftUI

// Wave 16m-4: the dictation result's type, measured on Incredible's overlay
// CSS (docs/research/incredible-isla-componentes.md §4). Its layout is the
// island's grid. Pinned in Island16m4Tests.

package enum IslandDictationMetrics {
    /// The label and the words, 10 apart; the row sits on the island's grid.
    package static let gap: CGFloat = 10
    /// The words: 15 / 500 (drawn `.medium`), line 1.38, -0.01em.
    package static let textSize: CGFloat = 15
    package static let textLeading: CGFloat = 1.38
    package static let textTracking: CGFloat = -0.01
    /// Not measured: a long dictation would otherwise push the island past
    /// its canvas. Copy always takes the whole text; only the drawing clips.
    package static let maxLines = 6
    /// Arc's copy button confirms with a success check.
    package static let copiedTint = ArcTone.success
    /// How long "Copied" stays on the button. Not measured.
    package static let copiedFor: Double = 1.5
}

/// What the card's buttons do that is not a session event.
enum IslandDictation {
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    /// The whole text, never the clipped drawing: a copy that lost the tail
    /// of a long dictation would be a silent data loss.
    static func copy(_ text: String, to board: NSPasteboard = .general) {
        // Transient, not concealed: clipboard managers skip it, so the words
        // do not linger in a history, and the user can still paste them.
        board.clearContents()
        board.declareTypes([.string, transientType], owner: nil)
        board.setString(text, forType: .string)
        board.setData(Data(), forType: transientType)
    }
}
