import Foundation

/// Silences what else is playing (music, video) while the user talks.
/// Both calls are idempotent: the adapter owns whatever it took over and
/// gives it back, no matter how many times it is asked. Adapters must not
/// block the main actor: the coordinator's worker inherits it, so a blocking
/// call here freezes the UI for as long as it blocks.
package protocol OtherAudioMuting: Sendable {
    func mute() async
    func unmute() async
}

package enum OtherAudioMuteDecision {
    /// `.listening` is the whole hold, dictation included (a dictation hold
    /// is the same kind with the field name attached): the user is talking
    /// and Companion is listening. `.processing(.pending)` already means
    /// "she let go, waiting for the words", so the sound comes back there
    /// instead of staying down through thinking and speaking.
    package static func shouldMute(enabled: Bool, kind: SessionKind) -> Bool {
        enabled && kind == .listening
    }
}

/// Turns the session's kind and the preference into `mute()`/`unmute()` on
/// the transitions only. Calls travel through one stream so they reach the
/// port in the order they were decided, however slow the adapter is.
// HACK: the queue does not coalesce, so a slow mute() delays the unmute
// behind it. Coalesce to the latest wanted state if the real adapter takes
// more than ~100 ms per call.
@MainActor
package final class OtherAudioMuteCoordinator {
    private let isEnabled: @Sendable () -> Bool
    private let continuation: AsyncStream<Bool>.Continuation
    private let worker: Task<Void, Never>
    private var kind: SessionKind = .idle
    private var muted = false
    private var isShutDown = false

    package init(muter: any OtherAudioMuting, isEnabled: @escaping @Sendable () -> Bool) {
        self.isEnabled = isEnabled
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self)
        self.continuation = continuation
        worker = Task {
            for await wantMuted in stream {
                if wantMuted { await muter.mute() } else { await muter.unmute() }
            }
        }
    }

    package func observe(_ kind: SessionKind) {
        self.kind = kind
        reconcile()
    }

    /// The Settings switch flipped: restores at once if it went off mid-turn.
    package func preferenceDidChange() {
        reconcile()
    }

    /// Stops accepting changes and waits for the calls already decided.
    /// Quit path: queues the final unmute if the sound is down and closes the
    /// stream, so nothing observed afterwards can silence it again.
    package func shutdown() {
        guard !isShutDown else { return }
        if muted {
            muted = false
            continuation.yield(false)
        }
        isShutDown = true
        continuation.finish()
    }

    package func finish() async {
        continuation.finish()
        await worker.value
    }

    private func reconcile() {
        guard !isShutDown else { return }
        let want = OtherAudioMuteDecision.shouldMute(enabled: isEnabled(), kind: kind)
        guard want != muted else { return }
        muted = want
        continuation.yield(want)
    }
}
