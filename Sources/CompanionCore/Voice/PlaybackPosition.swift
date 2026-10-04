import Foundation

/// Where the voice's playback is, in milliseconds of audio since the player
/// last started or flushed. `playedMs` counts only audio actually rendered:
/// what is queued but not yet heard, and silence while nothing was queued,
/// are both left out — captions light a word when it is heard, not sent.
package struct PlaybackPosition: Sendable, Equatable {
    package var playedMs: Double
    package var queuedMs: Double

    package init(playedMs: Double, queuedMs: Double) {
        self.playedMs = playedMs
        self.queuedMs = queuedMs
    }

    package static let zero = PlaybackPosition(playedMs: 0, queuedMs: 0)
}

/// Turns a player clock into a `PlaybackPosition`. A player node's clock
/// keeps running while it has nothing to play (before the first buffer,
/// during an underrun), so its sample time alone overstates what was heard;
/// the gap is measured when the next buffer is queued after it.
package struct PlaybackCounter: Sendable, Equatable {
    /// The realtime voice's PCM rate.
    package static let sampleRate: Double = 24_000

    private var queuedFrames: Int64 = 0
    private var silentFrames: Int64 = 0

    package init() {}

    /// A flush or stop rewinds the player's clock to zero.
    package mutating func reset() {
        self = PlaybackCounter()
    }

    /// `playerSample` is the player clock now, nil before it first renders.
    package mutating func schedule(frames: Int64, playerSample: Int64?) {
        // Past the end of everything queued, the player has been idle: the
        // new buffer starts now, not where the last one ended.
        if let playerSample, playerSample > silentFrames + queuedFrames {
            silentFrames = playerSample - queuedFrames
        }
        queuedFrames += frames
    }

    package func position(playerSample: Int64?) -> PlaybackPosition {
        let played = playerSample.map { min(max($0 - silentFrames, 0), queuedFrames) } ?? 0
        return PlaybackPosition(playedMs: Self.ms(played), queuedMs: Self.ms(queuedFrames))
    }

    private static func ms(_ frames: Int64) -> Double {
        Double(frames) * 1000 / sampleRate
    }
}
