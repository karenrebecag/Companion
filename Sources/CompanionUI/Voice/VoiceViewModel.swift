import CompanionCore
import Observation

@Observable
@MainActor
package final class VoiceViewModel {
    package private(set) var snapshot: TurnSnapshot = .idle
    package private(set) var levels = VoiceLevels(mic: 0, agent: 0)
    package private(set) var statusText: String?
    /// Adapts the controls: button to interrupt on speakers, clean flow on
    /// headphones. Defaults to tapOnly until the route watcher reports.
    package private(set) var interruptCapability: InterruptCapability = .tapOnly
    package private(set) var echoFreeOutput = false

    package var isActive: Bool {
        switch snapshot.state {
        case .connecting, .listening, .thinking, .speaking: true
        case .idle, .error: false
        }
    }

    private let voice: any VoiceControlling
    private let thread: any ConversationPresenting
    /// The session reducer hears every snapshot (Wave 12a). A forward, not a
    /// second source: the session never reads `snapshot` from here.
    private let session: SessionModel?
    private let tasks = Tasks()

    package init(
        voice: any VoiceControlling,
        thread: any ConversationPresenting,
        outputRoute: (any OutputRouteObserving)? = nil,
        onSnapshot: (@Sendable (TurnSnapshot) -> Void)? = nil,
        session: SessionModel? = nil
    ) {
        self.voice = voice
        self.thread = thread
        self.outputRoute = outputRoute
        self.onSnapshot = onSnapshot
        self.session = session
    }

    /// External observers (ambience) tap here: the snapshot stream has one
    /// consumer and must not be iterated twice.
    private let onSnapshot: (@Sendable (TurnSnapshot) -> Void)?

    private let outputRoute: (any OutputRouteObserving)?

    package func start() {
        Task { await voice.start() }
    }

    package func advance() {
        Task { await voice.advance() }
    }

    package func hangUp() {
        Task { await voice.hangUp() }
    }

    package func setVolume(_ volume: Double) {
        Task { await voice.setVolume(volume) }
    }

    package func setSpeed(_ speed: Double) {
        Task { await voice.setSpeed(speed) }
    }

    package func toggleMute() {
        Task { await voice.toggleMute() }
    }

    package func push(_ attachment: AttachmentRef) {
        Task { await voice.push(attachment: attachment) }
    }

    package func onAppear() {
        guard tasks.snapshots == nil else { return }
        if let outputRoute {
            tasks.route = Task { [weak self] in
                for await echoFree in outputRoute.echoFreeUpdates {
                    await self?.applyRoute(echoFree: echoFree)
                }
            }
        }
        tasks.snapshots = Task { [weak self] in
            guard let self else { return }
            for await snap in self.voice.snapshots {
                await self.apply(snap)
            }
        }
        tasks.levels = Task { [weak self] in
            guard let self else { return }
            for await value in self.voice.levels {
                self.levels = value
            }
        }
    }

    private func applyRoute(echoFree: Bool) {
        echoFreeOutput = echoFree
        // AEC state feeds in through the snapshot pipeline eventually; for the
        // UI decision, echo-free output alone already enables talk-over.
        interruptCapability = InterruptCapability.decide(
            echoFreeOutput: echoFree, aecActive: false)
    }

    private func apply(_ snap: TurnSnapshot) async {
        onSnapshot?(snap)
        session?.send(.voice(snap))
        let previous = snapshot
        snapshot = snap

        // One event, one line. This is the only place a voice failure reaches
        // the thread: Services used to append its own hardcoded wording too,
        // so a single failure showed up twice, phrased differently.
        if previous.pipeline == .realtime, snap.pipeline == .classic {
            // Falling back is the useful headline; the raw reason underneath
            // it would just be the same news told twice.
            statusText = VoiceCopy.fallbackClassic
            await thread.appendStatus(VoiceCopy.fallbackClassic)
        } else if let failure = snap.failure, previous.failure != failure {
            // Keyed on the failure changing, not on the state: recovery keeps
            // the session listening while still reporting why it stumbled.
            let message = VoiceCopy.failure(failure)
            statusText = message
            await thread.appendStatus(message)
        }

        // Clear status when returning to idle.
        if snap.state == .idle {
            statusText = nil
        }
    }
}

/// deinit is nonisolated; Task.cancel is the only safe teardown from there.
private final class Tasks: @unchecked Sendable {
    var snapshots: Task<Void, Never>?
    var levels: Task<Void, Never>?
    var route: Task<Void, Never>?

    deinit {
        snapshots?.cancel()
        levels?.cancel()
        route?.cancel()
    }
}
