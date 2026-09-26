import CompanionCore
import Foundation

/// A classic hold's two audio buffers (15c-7 energy, 15e-1 early audio).
/// Code review 2026-09-24 (medio): the frame pump writes them on the
/// session actor while `ClassicRuntime.submit` and `requestListen` run off
/// it, so a read-and-reset was two steps another thread could split — the
/// early audio reached the ear twice. One lock makes each take a single step.
final class ClassicHoldAudio: @unchecked Sendable {
    private let lock = NSLock()
    /// Energy only: nothing reads the hold's own PCM at release (15e-4).
    private var energy = HoldAudioBuffer(maxSeconds: 0)
    /// What the mic heard while the ear was still starting, capped at 10 s.
    private var early = HoldAudioBuffer(maxSeconds: 10)

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        energy.reset()
        early.reset()
    }

    /// A frame from before the ear was up: measured, and kept for the ear.
    func hearBeforeEar(_ frame: MicFrame) {
        lock.lock()
        defer { lock.unlock() }
        energy.append(frame)
        early.append(frame)
    }

    /// A frame the ear itself receives: measured only.
    func hearLive(_ frame: MicFrame) {
        lock.lock()
        defer { lock.unlock() }
        energy.append(frame)
    }

    /// The early audio, handed over at most once.
    func takeEarly() -> Data {
        lock.lock()
        defer { lock.unlock() }
        let pcm = early.snapshot
        early.reset()
        return pcm
    }

    /// Whether the hold sounded like speech, read once at release.
    func takeSpeech() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let speech = energy.hasSpeech
        energy.reset()
        return speech
    }

    var hasSpeech: Bool {
        lock.lock()
        defer { lock.unlock() }
        return energy.hasSpeech
    }

    /// PCM bytes held right now, across both buffers.
    var keptBytes: Int {
        lock.lock()
        defer { lock.unlock() }
        return energy.snapshot.count + early.snapshot.count
    }
}
