import CompanionCore
import Foundation
import Observation

/// P3: when the voice line chip is mounted and when it is lit, as Incredible's
/// (referencia local): it comes with its turn, stays a while once the turn is over,
/// and leaves with a short fade. The clock is injected so tests drive it.
@MainActor @Observable
package final class VoiceLineModel {
    package private(set) var line: VoiceLine?
    package private(set) var visible = false

    @ObservationIgnored private let sleep: @Sendable (TimeInterval) async -> Void
    @ObservationIgnored private var clock: Task<Void, Never>?
    // Every new clock bumps this, so an old sleep that returns late never touches a newer line.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var lingering: UUID?

    package init(sleep: @escaping @Sendable (TimeInterval) async -> Void = VoiceLineModel.wallClock) {
        self.sleep = sleep
    }

    package func show(_ next: VoiceLine?) {
        guard let next else { return leave() }
        // Incredible ignores a finished turn it never showed: the island already carried it.
        if next.settled, line?.turn != next.turn { return }
        // A finished turn already leaving goes; lighting it again would flash and vanish.
        if next.settled, !visible { return }
        if next == line, visible { return }
        let alreadyLingering = lingering == next.turn
        line = next
        visible = true
        if !next.settled {
            stopClock()
        } else if !alreadyLingering {
            linger(next.turn)
        }
    }

    /// A cancelled clock wakes early; the generation check then drops it.
    package static let wallClock: @Sendable (TimeInterval) async -> Void = { delay in
        do { try await Task.sleep(for: .seconds(delay)) } catch { return }
    }

    private func leave() {
        guard line != nil, visible else { return }
        visible = false
        let mine = restartClock()
        clock = Task { [weak self, sleep] in
            await sleep(VoiceLine.leave)
            self?.unmount(ifStill: mine)
        }
    }

    private func linger(_ turn: UUID) {
        let mine = restartClock()
        lingering = turn
        clock = Task { [weak self, sleep] in
            await sleep(VoiceLine.lingerAfterSettle)
            guard let self, self.generation == mine else { return }
            self.visible = false
            await sleep(VoiceLine.leave)
            self.unmount(ifStill: mine)
        }
    }

    private func unmount(ifStill mine: Int) {
        guard generation == mine else { return }
        line = nil
        lingering = nil
    }

    @discardableResult private func restartClock() -> Int {
        stopClock()
        return generation
    }

    private func stopClock() {
        clock?.cancel()
        clock = nil
        lingering = nil
        generation += 1
    }
}
