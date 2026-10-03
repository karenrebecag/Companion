import Foundation

/// Wave 15c-2, reshaped by 15e: a classic hold's speech energy, plus a
/// bounded copy of its PCM for whoever asks for one. Since the cloud ear
/// left (15e) the hold's own instance keeps no PCM (`maxSeconds: 0`) — it
/// only measures energy for the silence gate; `ClassicRuntime.earlyAudio`
/// keeps up to 10 s so the ear gets what it missed while starting.
/// `ClassicRuntime` owns both (mutated from within `VoiceSession`'s
/// actor-isolated frame pump, the same exclusive-access pattern the rest of
/// its state relies on). Once full, further frames are dropped rather than
/// grown without bound (wave-15c §5, §8).
package struct HoldAudioBuffer: Sendable, Equatable {
    private var pcm = Data()
    private let capBytes: Int
    private var speechFrameCount = 0

    /// Live bug fix (HIGH, 2026-09-23): Whisper hallucinated confident text
    /// over true silence — Karen held FN without speaking and the cloud ear
    /// answered "Gracias." three times while Apple heard nothing. 0.2 RMS
    /// sits above this mic's measured ambient noise floor (0.12, see
    /// `VoiceSessionPumps.driveTurn`) and comfortably below real speech
    /// (0.3-0.8, same measurement) — a conservative gate, not a guess.
    package static let speechRMSThreshold = 0.2
    /// A single loud frame (a click, a chair creak) must not pass the gate;
    /// real speech holds several frames above threshold.
    private static let minSpeechFrames = 3

    package init(maxSeconds: Double = 60, sampleRate: Int = 24_000) {
        // 16-bit mono: 2 bytes per sample.
        capBytes = Int(maxSeconds * Double(sampleRate) * 2)
    }

    package mutating func reset() {
        pcm = Data()
        speechFrameCount = 0
    }

    package mutating func append(_ frame: MicFrame) {
        let bytes = frame.pcm16le24k
        guard !bytes.isEmpty else { return }
        if frame.rms >= Self.speechRMSThreshold { speechFrameCount += 1 }
        guard pcm.count < capBytes else { return }
        let remaining = capBytes - pcm.count
        pcm += bytes.count <= remaining ? bytes : bytes.prefix(remaining)
    }

    package var snapshot: Data { pcm }

    /// Whether this hold ever sounded like speech — `ClassicRuntime` reads
    /// it at release to tell a silent hold from one the ear came back empty on.
    package var hasSpeech: Bool { speechFrameCount >= Self.minSpeechFrames }
}
