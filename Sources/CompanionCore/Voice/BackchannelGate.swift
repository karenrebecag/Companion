import Foundation

/// With echo-free output the mic keeps streaming while the agent talks, so the
/// server's VAD hears every "ajá" and cuts the reply. The prototype solved the
/// same problem on the transcript side (two words minimum — a "mmm" does not
/// interrupt); here it has to be solved BEFORE sending, because once the audio
/// reaches the server the barge-in already happened.
///
/// Rule: while the agent speaks, the user must sustain voice for a moment
/// before their audio is forwarded. A backchannel is short; a real
/// interruption keeps going.
public struct BackchannelGate: Sendable, Equatable {
    /// Frames of ~85 ms at 24 kHz: six of them are roughly half a second.
    public static let defaultRequiredFrames = 6
    public static let defaultThreshold = 0.08

    private let requiredFrames: Int
    private let threshold: Double
    private var voiced = 0
    private var open = false

    public init(
        requiredFrames: Int = defaultRequiredFrames,
        threshold: Double = defaultThreshold
    ) {
        self.requiredFrames = requiredFrames
        self.threshold = threshold
    }

    /// Called per mic frame while the agent is speaking.
    public mutating func allowsWhileSpeaking(rms: Double) -> Bool {
        if open { return true }
        if rms >= threshold {
            voiced += 1
            // Once the user has clearly committed, let everything through so
            // the interruption itself is not clipped.
            if voiced >= requiredFrames {
                open = true
                return true
            }
        } else {
            // A gap resets the run: three separate grunts are not a sentence.
            voiced = 0
        }
        return false
    }

    /// The agent stopped (or the turn ended): next reply starts guarded again.
    public mutating func reset() {
        voiced = 0
        open = false
    }
}
