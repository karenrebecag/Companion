import CompanionCore
import Foundation
import Observation

/// Follows the session's hold, whatever started or ended it (the key, the island's
/// pointer, a stop, an error): each hold is a new generation of observations and its
/// end stops looking. Edges are chained so a quick release never lands before its start.
@MainActor
package final class HoldObservationSync {
    private let observer: any HoldObserving
    private let companion: HoldCompanionModel
    private let words: @MainActor () -> Int
    private var holding = false
    private var generation = 0
    private var pending: Task<Void, Never>?

    package init(observer: any HoldObserving, companion: HoldCompanionModel,
                 words: @escaping @MainActor () -> Int) {
        self.observer = observer
        self.companion = companion
        self.words = words
    }

    package func update(holding now: Bool) {
        guard now != holding else { return }
        holding = now
        let previous = pending
        let observer = observer
        guard now else {
            pending = Task {
                await previous?.value
                await observer.stop()
            }
            return
        }
        generation += 1
        let generation = generation
        let deliver: @Sendable (HoldObservationBatch) -> Void = { [weak self] batch in
            Task { @MainActor in self?.deliver(batch) }
        }
        pending = Task {
            await previous?.value
            await observer.start(generation: generation, onBatch: deliver)
        }
    }

    /// Done when every start and stop asked for so far has reached the observer.
    package func settled() async {
        await pending?.value
    }

    /// Watches `projection.holding` until the returned task is cancelled.
    package func follow(_ session: SessionModel) -> Task<Void, Never> {
        let holds = Observations { session.projection.holding }
        return Task { [weak self] in
            for await holding in holds {
                guard let self else { return }
                update(holding: holding)
            }
        }
    }

    /// How far the transcript has got, so a copy is woven where the voice was.
    package nonisolated static func words(in partial: String?) -> Int {
        partial?.split(whereSeparator: \.isWhitespace).count ?? 0
    }

    private func deliver(_ batch: HoldObservationBatch) {
        // A batch that arrives after its hold ended belongs to no hold on screen.
        guard holding, batch.generation == generation else { return }
        companion.observe(batch, words: words())
    }
}
