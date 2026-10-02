import CompanionCore
@testable import CompanionUI
import CompanionTestKit
import Testing

// K7 (brief isla-ciclo-y-legibilidad, signed by Karen): the three dotted
// slots stood in the header with no task behind them, as empty chrome.
// Incredible's task band does not show without tasks, so they appear only
// while a task runs.

@Test @MainActor func theSlotsShowOnlyWhileATaskRuns() {
    for size: IslandState.Size in [.nudge, .card, .wideCard] {
        expect(!IslandSlots.shown(size: size, jobRunning: false), "\(size): sin encargo, sin ranuras")
        expect(IslandSlots.shown(size: size, jobRunning: true), "\(size): con encargo, las tres ranuras")
    }
    expect(!IslandSlots.shown(size: .bar, jobRunning: true), "barra: no hay cabecera para las ranuras")
}
