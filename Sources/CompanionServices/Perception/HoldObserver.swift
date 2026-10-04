import AppKit
import ApplicationServices
import CompanionCore

// Incredible's hold observations (referencia local, crate workflow-recording): while the
// voice key is held the host polls where the user is and what they copied, and reports
// the whole hold each time something changes. Nothing is observed outside a hold, and
// nothing observed is ever logged.

/// Where the user is: the frontmost app and its focused window.
package struct HoldSurface: Sendable, Equatable {
    package let app: String?
    package let title: String?
    package let url: String?

    package init(app: String?, title: String?, url: String? = nil) {
        self.app = app
        self.title = title
        self.url = url
    }
}

package protocol HoldSurfaceReading: Sendable {
    /// Nil when it cannot be read right now; that is not a move.
    func surface() -> HoldSurface?
}

/// Turns successive looks at the screen and the board into observations.
struct HoldSampler {
    private var lastSurface: HoldSurface?
    private var lastCount: Int
    private(set) var events: [HoldObservation] = []

    init(surface: HoldSurface?, changeCount: Int) {
        lastSurface = surface
        lastCount = changeCount
    }

    /// True when something new was observed.
    mutating func sample(surface: HoldSurface?, pasteboard: any PasteboardReading, atMs: Int) -> Bool {
        let before = events.count
        if let seen = surface.map(keepingTitle), seen != lastSurface {
            events.append(HoldObservation(atMs: atMs, event: .surfaceChanged(
                app: seen.app, title: seen.title, url: seen.url)))
            lastSurface = seen
        }
        let count = pasteboard.changeCount
        if count != lastCount {
            lastCount = count
            // A password manager marks what it copies; it is never read.
            if !pasteboard.concealed, let text = pasteboard.string, !text.isEmpty {
                events.append(HoldObservation(atMs: atMs, event: .copied(String(text.prefix(HoldObserver.copyLimit)))))
            }
        }
        return events.count != before
    }

    /// A title that cannot be read for one look in the same app is the last one, not a move.
    private func keepingTitle(_ surface: HoldSurface) -> HoldSurface {
        guard surface.title == nil, let last = lastSurface, last.app == surface.app else { return surface }
        return HoldSurface(app: surface.app, title: last.title, url: surface.url ?? last.url)
    }
}

/// Watches one hold at a time.
package actor HoldObserver: HoldObserving {
    /// How often it looks while the key is held.
    package static let interval = Duration.milliseconds(150)
    /// Longer than any chip or woven line can show; the rest is never kept.
    package static let copyLimit = 4096

    private let surface: any HoldSurfaceReading
    private let pasteboard: any PasteboardReading
    private let now: @Sendable () -> Int
    private let polls: Bool
    private let interval: Duration
    private var sampler: HoldSampler?
    private var generation = 0
    private var onBatch: (@Sendable (HoldObservationBatch) -> Void)?
    private var loop: Task<Void, Never>?

    /// `polls: false` leaves the looking to `tick()`, for tests.
    package init(surface: any HoldSurfaceReading, pasteboard: any PasteboardReading = SystemPasteboard(),
                 now: @escaping @Sendable () -> Int, polls: Bool = true,
                 interval: Duration = HoldObserver.interval) {
        self.surface = surface
        self.pasteboard = pasteboard
        self.now = now
        self.polls = polls
        self.interval = interval
    }

    package func start(generation: Int, onBatch: @escaping @Sendable (HoldObservationBatch) -> Void) {
        stop()
        self.generation = generation
        self.onBatch = onBatch
        // What was already there when the hold began is the starting point, not a move.
        sampler = HoldSampler(surface: surface.surface(), changeCount: pasteboard.changeCount)
        guard polls else { return }
        loop = Task { [weak self, interval] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                await self?.tick(generation: generation)
            }
        }
    }

    package func stop() {
        loop?.cancel()
        loop = nil
        sampler = nil
        onBatch = nil
    }

    package func tick() { tick(generation: generation) }

    /// A loop that outlived its hold must not report into the next one.
    private func tick(generation expected: Int) {
        guard expected == generation, var current = sampler else { return }
        let changed = current.sample(surface: surface.surface(), pasteboard: pasteboard, atMs: now())
        sampler = current
        if changed { onBatch?(HoldObservationBatch(generation: generation, events: current.events)) }
    }
}

/// The frontmost app other than Companion, and its focused window's title when
/// Accessibility allows reading it.
package struct SystemHoldSurface: HoldSurfaceReading {
    private let trusted: @Sendable () -> Bool
    private let selfBundleID: String?
    /// A hung app must not stall the observer's actor for the default six seconds.
    static let axTimeout: Float = 0.2

    package init(trusted: @escaping @Sendable () -> Bool, selfBundleID: String? = Bundle.main.bundleIdentifier) {
        self.trusted = trusted
        self.selfBundleID = selfBundleID
    }

    package func surface() -> HoldSurface? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != selfBundleID
        else { return nil }
        let title = trusted() ? FocusedWindowSensor.title(of: app.processIdentifier, timeout: Self.axTimeout) : nil
        return HoldSurface(app: app.localizedName, title: title)
    }
}
