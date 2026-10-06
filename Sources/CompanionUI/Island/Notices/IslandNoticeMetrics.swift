import SwiftUI

// Wave 16m-4: the update offer keeps its own wide shape (16m-6): it is a
// size of the island's state machine (`.wideCard`), not of the card. Its
// actions now stack under the words like every notice's.

package nonisolated enum IslandNoticeMetrics {
    /// The update offer's room: 522 measured on Incredible, so its shape is 554.
    package static let updateWidth: CGFloat = 522
}

/// The offer the island makes about a new release: only while one exists and
/// this session has not waved it away. Dismissing a version never silences a
/// newer one.
enum IslandUpdate {
    static func visibleTag(available: UpdateState.Available?, dismissed: String?) -> String? {
        guard let tag = available?.tag, tag != dismissed else { return nil }
        return tag
    }
}
