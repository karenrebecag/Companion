import CompanionCore
import Testing

/// Frames at 24 kHz: 2400 is 100 ms.
@Suite struct PlaybackCounterTests {
    @Test func nothingIsPlayedBeforeThePlayerRenders() {
        var counter = PlaybackCounter()
        counter.schedule(frames: 2400, playerSample: nil)
        #expect(counter.position(playerSample: nil) == PlaybackPosition(playedMs: 0, queuedMs: 100))
    }

    @Test func playedFollowsThePlayerClockUpToWhatWasQueued() {
        var counter = PlaybackCounter()
        counter.schedule(frames: 2400, playerSample: 0)
        #expect(counter.position(playerSample: 1200).playedMs == 50)
        // The clock keeps running past the end of the audio: nothing more
        // was heard than what was queued.
        #expect(counter.position(playerSample: 9000).playedMs == 100)
    }

    /// The player clock ran 200 ms with nothing to play (the wait for the
    /// first buffer, or an underrun): that silence is not audio heard.
    @Test func timeWithNothingQueuedIsNotCountedAsPlayed() {
        var counter = PlaybackCounter()
        counter.schedule(frames: 2400, playerSample: 4800)
        #expect(counter.position(playerSample: 6000).playedMs == 50)
        counter.schedule(frames: 2400, playerSample: 12000)
        #expect(counter.position(playerSample: 12000).playedMs == 100)
        #expect(counter.position(playerSample: 13200) == PlaybackPosition(playedMs: 150, queuedMs: 200))
    }

    @Test func audioQueuedWhilePlayingAddsNoGap() {
        var counter = PlaybackCounter()
        counter.schedule(frames: 2400, playerSample: 0)
        counter.schedule(frames: 2400, playerSample: 1200)
        #expect(counter.position(playerSample: 3600).playedMs == 150)
    }

    /// A flush rewinds the player's clock to zero; the count restarts with it.
    @Test func aResetStartsTheCountAgainFromZero() {
        var counter = PlaybackCounter()
        counter.schedule(frames: 2400, playerSample: 4800)
        counter.reset()
        #expect(counter.position(playerSample: 0) == .zero)
        counter.schedule(frames: 2400, playerSample: 0)
        #expect(counter.position(playerSample: 1200) == PlaybackPosition(playedMs: 50, queuedMs: 100))
    }
}
