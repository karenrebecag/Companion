import CompanionCore
import Observation

@Observable
@MainActor
public final class VoiceViewModel {
    public private(set) var snapshot: TurnSnapshot = .idle
    public private(set) var levels = VoiceLevels(mic: 0, agent: 0)
    public private(set) var statusText: String?
    /// Adapts the controls: button to interrupt on speakers, clean flow on
    /// headphones. Defaults to tapOnly until the route watcher reports.
    public private(set) var interruptCapability: InterruptCapability = .tapOnly
    public private(set) var echoFreeOutput = false

    public var isActive: Bool {
        switch snapshot.state {
        case .connecting, .listening, .thinking, .speaking: true
        case .idle, .error: false
        }
    }

    private let voice: any VoiceControlling
    private let thread: any ConversationPresenting
    private let tasks = Tasks()

    public init(
        voice: any VoiceControlling,
        thread: any ConversationPresenting,
        outputRoute: (any OutputRouteObserving)? = nil,
        onSnapshot: (@Sendable (TurnSnapshot) -> Void)? = nil
    ) {
        self.voice = voice
        self.thread = thread
        self.outputRoute = outputRoute
        self.onSnapshot = onSnapshot
    }

    /// External observers (ambience) tap here: the snapshot stream has one
    /// consumer and must not be iterated twice.
    private let onSnapshot: (@Sendable (TurnSnapshot) -> Void)?

    private let outputRoute: (any OutputRouteObserving)?

    public func start() {
        Task { await voice.start() }
    }

    public func advance() {
        Task { await voice.advance() }
    }

    public func hangUp() {
        Task { await voice.hangUp() }
    }

    public func setVolume(_ volume: Double) {
        Task { await voice.setVolume(volume) }
    }

    public func setSpeed(_ speed: Double) {
        Task { await voice.setSpeed(speed) }
    }

    public func toggleMute() {
        Task { await voice.toggleMute() }
    }

    public func push(_ attachment: AttachmentRef) {
        Task { await voice.push(attachment: attachment) }
    }

    public func onAppear() {
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
        let previous = snapshot
        snapshot = snap

        // Handle pipeline fallback from realtime to classic.
        if previous.pipeline == .realtime, snap.pipeline == .classic {
            statusText = VoiceCopy.fallbackClassic
            await thread.appendStatus(VoiceCopy.fallbackClassic)
        }

        // Handle error state with a failure reason.
        if snap.state == .error, let failure = snap.failure {
            let message = VoiceCopy.failure(failure)
            // Only update statusText and emit if this is a new error or a different failure reason.
            if previous.state != .error || previous.failure != failure {
                statusText = message
                await thread.appendStatus(message)
            }
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
