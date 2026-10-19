import CompanionCore
import Foundation

/// The realtime reply as a caption, word by word as the player sounds it
/// (gap 2). The server's events say what the reply is and how much audio it
/// has; only the player knows how much of that was heard, so this polls it
/// while a caption is live and stops once the caption settles.
package actor CaptionFeed {
    /// PCM16 mono at 24 kHz.
    private static let bytesPerMs = 48.0

    package nonisolated let snapshots: AsyncStream<CaptionSnapshot>
    private let box: AudioStreamBox<CaptionSnapshot>
    private let player: any PCMPlaying
    private let now: @Sendable () -> TimeInterval
    private let interval: Duration
    private var timeline = CaptionTimeline()
    package private(set) var latest = CaptionSnapshot.empty
    private var ticking: Task<Void, Never>?
    /// Bumped by every cut: an event that suspended across one is stale.
    private var generation = 0
    /// After a cut the server can still send the tail of the cancelled
    /// response; nothing but a new response reopens the caption.
    private var cutPending = false
    private var publishedRevision = -1

    /// `interval`: about a display frame at 30 Hz, as the island's reply
    /// reveal paints; finer would only re-send the same caption. `clock`
    /// stamps `CaptionWord.saidAt`, so it is wall-clock epoch seconds, not
    /// the session's injectable clock: the island compares it with its own.
    package init(
        player: any PCMPlaying,
        clock: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 },
        interval: Duration = .milliseconds(33)
    ) {
        self.player = player
        self.now = clock
        self.interval = interval
        let box = AudioStreamBox<CaptionSnapshot>()
        self.box = box
        self.snapshots = box.stream
    }

    deinit {
        ticking?.cancel()
        box.finish()
    }

    /// Called before the runtime acts on the event, so an audio chunk is
    /// placed where the player is about to queue it.
    package func observe(_ event: RealtimeEvent) async {
        if case .responseCreated = event {
            // A chunk still waiting on the player belongs to the old response.
            self.generation += 1
            cutPending = false
        } else if cutPending {
            return
        }
        let generation = self.generation
        switch event {
        case .responseCreated:
            timeline.clear()
        case .assistantTranscriptDelta(let delta):
            timeline.appendText(delta)
        case .assistantTranscriptDone(let text):
            timeline.finishText(text)
        case .audioDelta(let pcm):
            let queued = await player.position.queuedMs
            guard generation == self.generation else { return }
            timeline.appendAudio(ms: Double(pcm.count) / Self.bytesPerMs, queuedAtMs: queued)
        case .responseDone:
            timeline.finishAudio(at: now())
        default:
            return
        }
        publish()
        keepTicking()
    }

    package var isActive: Bool { timeline.isActive }
    package var isTicking: Bool { ticking != nil }

    package func drained() async {
        guard !cutPending else { return }
        let generation = self.generation
        let played = await player.position.playedMs
        guard generation == self.generation else { return }
        timeline.drained(at: now(), playedMs: played)
        publish()
        keepTicking()
    }

    /// The voice was cut (barge-in, stop, close): the words it never said
    /// must not stay on screen.
    package func cut() {
        generation += 1
        cutPending = true
        ticking?.cancel()
        ticking = nil
        timeline.clear()
        publish()
    }

    package func tick() async {
        let generation = self.generation
        let played = await player.position.playedMs
        guard generation == self.generation else { return }
        timeline.advance(playedMs: played, now: now())
        publish()
    }

    private func publish() {
        guard timeline.revision != publishedRevision else { return }
        publishedRevision = timeline.revision
        let snapshot = timeline.snapshot
        guard snapshot != latest else { return }
        latest = snapshot
        box.yield(snapshot)
    }

    private func keepTicking() {
        guard ticking == nil, timeline.isActive else { return }
        ticking = Task { [weak self] in await self?.run() }
    }

    private func run() async {
        while !Task.isCancelled, timeline.isActive {
            await tick()
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
        }
        // A cancelled loop was replaced by `cut`; clearing here would drop
        // the loop that replaced it.
        if !Task.isCancelled { ticking = nil }
    }
}
