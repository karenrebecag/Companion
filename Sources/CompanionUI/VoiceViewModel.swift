import CompanionCore
import Observation

@Observable
@MainActor
public final class VoiceViewModel {
    public private(set) var snapshot: TurnSnapshot = .idle
    public private(set) var levels = VoiceLevels(mic: 0, agent: 0)
    public private(set) var statusText: String?

    public var isActive: Bool {
        switch snapshot.state {
        case .connecting, .listening, .thinking, .speaking: true
        case .idle, .error: false
        }
    }

    private let voice: any VoiceControlling
    private let thread: any ConversationPresenting
    private let tasks = Tasks()

    public init(voice: any VoiceControlling, thread: any ConversationPresenting) {
        self.voice = voice
        self.thread = thread
    }

    public func start() {
        Task { await voice.start() }
    }

    public func advance() {
        Task { await voice.advance() }
    }

    public func hangUp() {
        Task { await voice.hangUp() }
    }

    public func toggleMute() {
        Task { await voice.toggleMute() }
    }

    public func onAppear() {
        guard tasks.snapshots == nil else { return }
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

    private func apply(_ snap: TurnSnapshot) async {
        let previous = snapshot
        snapshot = snap
        if previous.pipeline == .realtime, snap.pipeline == .classic {
            statusText = VoiceCopy.fallbackClassic
            await thread.appendStatus(VoiceCopy.fallbackClassic)
        } else if snap.state == .idle {
            statusText = nil
        }
    }
}

/// deinit is nonisolated; Task.cancel is the only safe teardown from there.
private final class Tasks: @unchecked Sendable {
    var snapshots: Task<Void, Never>?
    var levels: Task<Void, Never>?

    deinit {
        snapshots?.cancel()
        levels?.cancel()
    }
}
