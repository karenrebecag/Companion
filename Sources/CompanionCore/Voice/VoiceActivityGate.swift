import Foundation

/// Whether a mic frame is voice, for the waveform only: Incredible 0.2.36
/// draws a dot for every column its VAD calls silence, and without a flag
/// Companion's room noise (meter 0.12, -34 dBFS) sits far over the history's
/// 0.08 level gate and draws bars. An energy gate with hysteresis and a
/// hangover, fed the meter and the frame's time (docs/research/waveform-vad-voiced.md,
/// option b1). It never reaches turn logic: a false positive is one extra bar.
package struct VoiceActivityGate: Sendable, Equatable {
    /// Not a new threshold: the hold buffer's measured speech line, over
    /// this mic's 0.12 room floor and under real speech (0.3-0.8).
    package static let openLevel = HoldAudioBuffer.speechRMSThreshold
    /// Once open, a voice that softens mid-word stays voice down to here:
    /// between the 0.12 floor and the endpointer's 0.18 voice floor.
    /// Derived, not measured; the brief's live check (section 9) confirms it.
    package static let closeLevel = 0.15
    /// pipecat's stop_secs, about two 89 ms columns, so a breath between
    /// words does not flicker to dots. Seconds, not frames: a frame's length
    /// depends on the hardware rate.
    package static let hangover: TimeInterval = 0.20

    private var open = false
    /// When the last frame at or over the close level arrived; nil when that
    /// time could not be trusted, which ends the voice on the next quiet frame.
    private var lastVoice: TimeInterval?

    package init() {}

    /// One frame at a time, in arrival order. Attack is one frame: the strip
    /// must show the start of speech, and Incredible holds nothing back either.
    package mutating func voiced(meter raw: Double, at time: TimeInterval) -> Bool {
        // As WaveformHistory does: a broken frame is a quiet one.
        let meter = raw.isFinite ? max(raw, 0) : 0
        if meter >= (open ? Self.closeLevel : Self.openLevel) {
            open = true
            lastVoice = time.isFinite ? time : nil
            return true
        }
        guard isVoiced(at: time) else {
            open = false
            lastVoice = nil
            return false
        }
        return true
    }

    /// Whether the voice is still on at `time` with no frame since the last
    /// one. The meter only reaches the gate when it changes, so one that
    /// stops (the mic ends, digital silence sits at exactly 0) must still let
    /// the hangover run out on the clock.
    package func isVoiced(at time: TimeInterval) -> Bool {
        // A clock that went backwards or broke gives no elapsed time to
        // count down; closing is what keeps the flag from sticking.
        guard open, let lastVoice, time.isFinite, time >= lastVoice else { return false }
        return time - lastVoice < Self.hangover
    }
}
