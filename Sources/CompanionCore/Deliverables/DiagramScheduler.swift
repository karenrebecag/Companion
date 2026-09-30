import Foundation

/// The renderer's queue, apart from any web view so it can be tested with a
/// fake draw (16m-5b review): one draw at a time; identical requests in
/// flight share one draw; a caller that leaves cancels the draw only when
/// nobody else is waiting for it; a draw that never answers costs its
/// deadline and no more; and a run of timeouts turns the renderer off.
@MainActor
package final class DiagramScheduler: DiagramRendering {
    package typealias Draw = @MainActor (DiagramBlock, Double) async -> DiagramOutcome

    /// Most drawings kept; the popup can be reopened without a second render.
    package static let cacheLimit = 8
    /// A page that times out this many times in a row is not going to work
    /// this session; the popup shows code at once instead of waiting 10 s each.
    // HACK: never turns back on until the app restarts. Add a cool-down when
    // a real slow start (cold WebKit) is seen to trip it.
    package static let timeoutsBeforeShutdown = 3

    package var timeout: Duration
    private let draw: Draw
    private var cache: [(key: String, outcome: DiagramOutcome)] = []
    private var flights: [String: Flight] = [:]
    private var queue: Task<Void, Never>?
    private var consecutiveTimeouts = 0

    @MainActor private final class Flight {
        var task: Task<DiagramOutcome, Never>?
        var waiters = 1
    }

    package init(timeout: Duration = DiagramPage.renderTimeout, draw: @escaping Draw) {
        self.timeout = timeout
        self.draw = draw
    }

    package func render(_ block: DiagramBlock, width: Double) async -> DiagramOutcome {
        let key = "\(Int(width))|\(block.source)"
        if let hit = cache.first(where: { $0.key == key }) { return hit.outcome }
        guard consecutiveTimeouts < Self.timeoutsBeforeShutdown else { return .failed(.unavailable) }
        let flight = join(key, block, width)
        return await withTaskCancellationHandler {
            await flight.task?.value ?? .failed(.unavailable)
        } onCancel: {
            Task { @MainActor in self.leave(key, flight) }
        }
    }

    private func join(_ key: String, _ block: DiagramBlock, _ width: Double) -> Flight {
        if let existing = flights[key] {
            existing.waiters += 1
            return existing
        }
        let previous = queue
        let flight = Flight()
        let task = Task { @MainActor [weak self] () -> DiagramOutcome in
            await previous?.value
            // Everyone who asked has left while it waited its turn.
            guard let self, !Task.isCancelled else { return .failed(.unavailable) }
            return await self.run(key, flight, block, width)
        }
        flight.task = task
        flights[key] = flight
        queue = Task { _ = await task.value }
        return flight
    }

    private func leave(_ key: String, _ flight: Flight) {
        flight.waiters -= 1
        guard flight.waiters <= 0 else { return }
        flight.task?.cancel()
        if flights[key] === flight { flights[key] = nil }
    }

    private func run(_ key: String, _ flight: Flight, _ block: DiagramBlock, _ width: Double) async -> DiagramOutcome {
        // Flights queued behind the ones that timed out look again: the
        // renderer may have shut down while they waited.
        guard consecutiveTimeouts < Self.timeoutsBeforeShutdown else {
            release(key, flight)
            return .failed(.unavailable)
        }
        let draw = self.draw
        let result = await DiagramTimeout.run(after: timeout) { await draw(block, width) }
        release(key, flight)
        guard let outcome = result else {
            // Cancelled callers are not the page's fault.
            if Task.isCancelled { return .failed(.unavailable) }
            consecutiveTimeouts += 1
            return .failed(.timeout)
        }
        consecutiveTimeouts = 0
        switch outcome {
        case .image, .failed(.invalid): remember(key, outcome)
        // An unavailable page may recover; only a settled answer is kept.
        case .failed: break
        }
        return outcome
    }

    /// By identity: a cancelled flight that ends late must not delete the
    /// flight a later caller opened for the same key.
    private func release(_ key: String, _ flight: Flight) {
        if flights[key] === flight { flights[key] = nil }
    }

    private func remember(_ key: String, _ outcome: DiagramOutcome) {
        cache.removeAll { $0.key == key }
        cache.append((key, outcome))
        if cache.count > Self.cacheLimit { cache.removeFirst(cache.count - Self.cacheLimit) }
    }
}
