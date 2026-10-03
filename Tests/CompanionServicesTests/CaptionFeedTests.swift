@preconcurrency import AVFoundation
import CompanionCore
@testable import CompanionServices
import Foundation
import Testing
import CompanionServicesTestSupport
import CompanionCoreTestSupport
import CompanionTestKit

/// PCM16 mono at 24 kHz is 48 bytes a millisecond.
private func audio(ms: Int) -> Data { Data(count: ms * 48) }

private func lit(_ snapshot: CaptionSnapshot) -> [Bool] { snapshot.words.map(\.spoken) }

/// The last caption a stream published, read from the test.
private final class CaptionWatch: @unchecked Sendable {
    private let lock = NSLock()
    private var value = CaptionSnapshot.empty
    var latest: CaptionSnapshot { lock.withLock { value } }

    init(_ stream: AsyncStream<CaptionSnapshot>) {
        Task { [weak self] in
            for await snapshot in stream { self?.store(snapshot) }
        }
    }

    private func store(_ snapshot: CaptionSnapshot) { lock.withLock { value = snapshot } }
}

/// A clock the test moves by hand.
private final class ManualClock: @unchecked Sendable {
    @Guarded var now: TimeInterval = 0
}

/// A whole reply, "one two" (8 units) over 800 ms: words at 0 and 400 ms.
private func feedReply(_ feed: CaptionFeed) async {
    await feed.observe(.responseCreated)
    await feed.observe(.assistantTranscriptDelta("one two"))
    await feed.observe(.audioDelta(audio(ms: 800)))
    await feed.observe(.assistantTranscriptDone("one two"))
    await feed.observe(.responseDone)
}

/// An hour between ticks: the test drives every tick itself.
private func makeFeed(_ player: ScriptedPlayer, clock: ManualClock = ManualClock()) -> CaptionFeed {
    CaptionFeed(player: player, clock: { clock.now }, interval: .seconds(3600))
}

@Suite struct CaptionFeedTests {
    @Test func wordsLightAsThePlayerSoundsThem() async {
        let player = ScriptedPlayer()
        let feed = makeFeed(player)
        await feedReply(feed)
        player.position = PlaybackPosition(playedMs: 100, queuedMs: 800)
        await feed.tick()
        #expect(lit(await feed.latest) == [true, false])
        player.position = PlaybackPosition(playedMs: 400, queuedMs: 800)
        await feed.tick()
        #expect(lit(await feed.latest) == [true, true])
    }

    @Test func aReplyQueuedBehindEarlierAudioWaitsForItsOwnAudio() async {
        let player = ScriptedPlayer()
        let feed = makeFeed(player)
        player.position = PlaybackPosition(playedMs: 0, queuedMs: 2000)
        await feedReply(feed)
        player.position = PlaybackPosition(playedMs: 1999, queuedMs: 2800)
        await feed.tick()
        #expect(lit(await feed.latest) == [false, false])
    }

    @Test func aCutClearsTheCaptionOnTheStream() async {
        let player = ScriptedPlayer()
        let feed = makeFeed(player)
        let watch = CaptionWatch(feed.snapshots)
        await feedReply(feed)
        await pumpUntil("the caption reached the stream") { watch.latest.words.count == 2 }
        await feed.cut()
        await pumpUntil("the cut reached the stream") { watch.latest.words.isEmpty }
    }

    @Test func theCaptionSettlesSixHundredMillisecondsAfterTheAudioDrains() async {
        let player = ScriptedPlayer()
        let clock = ManualClock()
        let feed = makeFeed(player, clock: clock)
        await feedReply(feed)
        player.position = PlaybackPosition(playedMs: 800, queuedMs: 800)
        await feed.drained()
        clock.now = 0.6
        await feed.tick()
        let latest = await feed.latest
        #expect(latest.settled)
        #expect(lit(latest) == [true, true])
    }

    /// Review fix 1: the server keeps talking for a moment after a cancel.
    @Test func eventsAfterACutWaitForTheNextResponse() async {
        let player = ScriptedPlayer()
        let feed = makeFeed(player)
        await feedReply(feed)
        await feed.cut()
        await feed.observe(.assistantTranscriptDelta("ghost words"))
        await feed.observe(.audioDelta(audio(ms: 400)))
        await feed.observe(.assistantTranscriptDone("ghost words"))
        await feed.observe(.responseDone)
        await feed.drained()
        #expect(await feed.latest.words.isEmpty)
        #expect(!(await feed.isActive))
        #expect(!(await feed.isTicking))
        await feed.observe(.responseCreated)
        await feed.observe(.assistantTranscriptDelta("real"))
        #expect(await feed.latest.words.map(\.text) == ["real"])
    }

    /// A cut that lands while an audio chunk waits on the player.
    @Test func aCutDuringASuspendedAudioChunkLeavesNothingBehind() async {
        let player = GatedPlayer()
        let feed = CaptionFeed(player: player, clock: { 0 }, interval: .seconds(3600))
        await feed.observe(.responseCreated)
        await feed.observe(.assistantTranscriptDelta("one two"))
        player.hold()
        let chunk = Task { await feed.observe(.audioDelta(audio(ms: 800))) }
        await pumpUntilAsync("the chunk waits on the player") { player.waiting }
        await feed.cut()
        player.release()
        await chunk.value
        #expect(await feed.latest.words.isEmpty)
        #expect(!(await feed.isActive))
    }

    /// Review batch 5: a chunk suspended while the next response began belongs
/// to the old one, not to the new caption.
@Test func aChunkSuspendedAcrossANewResponseDoesNotJoinIt() async {
    let player = GatedPlayer()
    let feed = CaptionFeed(player: player, clock: { 0 }, interval: .seconds(3600))
    await feed.observe(.responseCreated)
    await feed.observe(.assistantTranscriptDelta("old"))
    player.hold()
    let chunk = Task { await feed.observe(.audioDelta(audio(ms: 800))) }
    await pumpUntilAsync("the chunk waits on the player") { player.waiting }
    await feed.observe(.responseCreated)
    player.release()
    await chunk.value
    await feed.observe(.assistantTranscriptDelta("new"))
    player.play(at: 500)
    await feed.tick()
    #expect(await feed.latest.words.map(\.spoken) == [false])
}

/// Review batch 6: AVAudioEngine's offline rendering mode needs no audio
/// device, so the real player can be driven here.
@Test func aFlushRewindsTheRealPlayersPosition() async throws {
    let player = RealtimePlayer(makeEngine: {
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        } catch {
            Issue.record("offline rendering unavailable: \(error)")
        }
        return engine
    })
    try await player.start(sharedEngine: false)
    await player.play(audio(ms: 100))
    #expect(await player.position.queuedMs == 100)
    await player.flush()
    #expect(await player.position == .zero)
}

/// Reply 1 played out and settled; reply 2 is queued behind it and
    /// stays dim until its own audio plays.
    @Test func backToBackRepliesEachWaitForTheirOwnAudio() async {
        let player = ScriptedPlayer()
        let clock = ManualClock()
        let feed = makeFeed(player, clock: clock)
        await feedReply(feed)
        player.position = PlaybackPosition(playedMs: 800, queuedMs: 800)
        await feed.drained()
        clock.now = 0.6
        await feed.tick()
        #expect(await feed.latest.settled)
        await feed.observe(.responseCreated)
        await feed.observe(.assistantTranscriptDelta("three four"))
        await feed.observe(.audioDelta(audio(ms: 800)))
        await feed.tick()
        #expect(lit(await feed.latest) == [false, false])
        player.position = PlaybackPosition(playedMs: 900, queuedMs: 1600)
        await feed.tick()
        #expect(lit(await feed.latest) == [true, false])
    }

    /// The settle tick and the next response arrive together: the new
    /// reply is not settled by the old one's clock.
    @Test func aSettleDueAsTheNextResponseArrivesSettlesNothingNew() async {
        let player = ScriptedPlayer()
        let clock = ManualClock()
        let feed = makeFeed(player, clock: clock)
        await feedReply(feed)
        player.position = PlaybackPosition(playedMs: 800, queuedMs: 800)
        await feed.drained()
        clock.now = 0.6
        await feed.observe(.responseCreated)
        await feed.observe(.assistantTranscriptDelta("next"))
        await feed.tick()
        let latest = await feed.latest
        #expect(!latest.settled)
        #expect(latest.words.map(\.text) == ["next"])
    }

    /// A flush rewinds the player to zero; the next reply anchors there.
    @Test func afterACutAndAPlayerResetTheNextReplyWaitsToBePlayed() async {
        let player = ScriptedPlayer()
        let feed = makeFeed(player)
        await feedReply(feed)
        player.position = PlaybackPosition(playedMs: 100, queuedMs: 800)
        await feed.tick()
        #expect(lit(await feed.latest) == [true, false])
        await feed.cut()
        player.position = .zero
        await feedReply(feed)
        await feed.tick()
        #expect(lit(await feed.latest) == [false, false])
        player.position = PlaybackPosition(playedMs: 50, queuedMs: 800)
        await feed.tick()
        #expect(lit(await feed.latest) == [true, false])
    }

    @Test func fiveSecondsWithoutAudioProgressSettlesThroughTheFeed() async {
        let player = ScriptedPlayer()
        let clock = ManualClock()
        let feed = makeFeed(player, clock: clock)
        await feedReply(feed)
        player.position = PlaybackPosition(playedMs: 100, queuedMs: 800)
        await feed.tick()
        clock.now = CaptionTimeline.idleSettle
        await feed.tick()
        #expect(await feed.latest.settled)
    }

    /// Review fix 6: `saidAt` is wall-clock epoch seconds, the clock the
    /// island's TimelineView paints on, whatever clock the session uses.
    @Test func theDefaultClockIsWallClockEpochSeconds() async {
        let player = ScriptedPlayer()
        let feed = CaptionFeed(player: player, interval: .seconds(3600))
        await feedReply(feed)
        player.position = PlaybackPosition(playedMs: 100, queuedMs: 800)
        await feed.tick()
        let said = await feed.latest.words[0].saidAt ?? 0
        #expect(abs(said - Date().timeIntervalSince1970) < 5)
    }
}

/// A player whose position can be held, to land a cut mid-chunk.
private final class GatedPlayer: PCMPlaying, @unchecked Sendable {
    private let lock = NSLock()
    private var held = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var playedMs: Double = 0
    var waiting: Bool { lock.withLock { waiter != nil } }
    func play(at ms: Double) { lock.withLock { playedMs = ms } }

    func hold() { lock.withLock { held = true } }
    func release() {
        let resume = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            held = false
            defer { waiter = nil }
            return waiter
        }
        resume?.resume()
    }

    var position: PlaybackPosition {
        get async {
            await withCheckedContinuation { continuation in
                let parked = lock.withLock { () -> Bool in
                    guard held else { return false }
                    waiter = continuation
                    return true
                }
                if !parked { continuation.resume() }
            }
            let played = lock.withLock { playedMs }
            return PlaybackPosition(playedMs: played, queuedMs: 0)
        }
    }
    func start(sharedEngine: Bool) async throws {}
    func play(_ pcm16le24k: Data) async {}
    func flush() async {}
    func stop() async {}
    func setVolume(_ volume: Double) async {}
    var hasPending: Bool { get async { false } }
    var drained: AsyncStream<Void> { AsyncStream { $0.finish() } }
    var levels: AsyncStream<Double> { AsyncStream { $0.finish() } }
}

/// The session wires the feed: the server's reply reaches the caption, and a
/// barge-in takes it down with the audio.
@Suite struct VoiceSessionCaptionTests {
    @Test @MainActor func aRealtimeReplyShowsAsACaptionAndABargeInClearsIt() async {
        let h = makeVoiceHarness()
        // Through the port, as the view model reads it: a default on the
        // protocol must not shadow the session's own stream.
        let voice: any VoiceControlling = h.session
        let watch = CaptionWatch(voice.captions)
        await h.session.start()
        await pumpUntil("listening") { h.watch.latest.state == .listening }
        h.transport.yield(.responseCreated)
        h.transport.yield(.assistantTranscriptDelta("hola mundo"))
        h.transport.yield(.audioDelta(audio(ms: 400)))
        await pumpUntil("speaking") { h.watch.latest.state == .speaking }
        await pumpUntil("the reply is a caption") { watch.latest.words.map(\.text) == ["hola", "mundo"] }

        await h.session.interrupt()

        await pumpUntil("the barge-in clears the caption") { watch.latest.words.isEmpty }
    }

    @MainActor private func liveCaption(_ h: VoiceHarness) async -> CaptionWatch {
        let watch = CaptionWatch(h.session.captions)
        await h.session.start()
        await pumpUntil("listening") { h.watch.latest.state == .listening }
        h.transport.yield(.responseCreated)
        h.transport.yield(.assistantTranscriptDelta("hola mundo"))
        h.transport.yield(.audioDelta(audio(ms: 400)))
        await pumpUntil("the reply is a caption") { watch.latest.words.count == 2 }
        // The words can show before the audio chunk is anchored: a test that
        // then moves the fake player's position would anchor the chunk at the
        // moved position, and the reply would never reach its end.
        await pumpUntil("the audio is queued") { !h.player.played.isEmpty }
        return watch
    }

    @Test(arguments: ["hangUp", "interrupt"]) @MainActor
    func closingOrStoppingTheVoiceClearsTheCaption(_ how: String) async {
        let h = makeVoiceHarness()
        let watch = await liveCaption(h)
        if how == "hangUp" { await h.session.hangUp() } else { await h.session.interrupt() }
        await pumpUntil("\(how) clears the caption") { watch.latest.words.isEmpty }
    }

    /// Review fix 3: a socket that ends without a close.
    @Test @MainActor func aDroppedStreamClearsTheCaption() async {
        let h = makeVoiceHarness()
        let watch = await liveCaption(h)
        await h.transport.simulateStreamEnd()
        await pumpUntil("the drop clears the caption") { watch.latest.words.isEmpty }
    }

    @Test @MainActor func aSessionErrorClearsTheCaption() async {
        let h = makeVoiceHarness()
        let watch = await liveCaption(h)
        h.transport.yield(.serverError("session expired"))
        await pumpUntil("the error clears the caption") { watch.latest.words.isEmpty }
    }

    /// The player drains after the response is done: the caption settles.
    @Test @MainActor func aDrainAfterTheResponseSettlesTheCaption() async {
        let h = makeVoiceHarness()
        let watch = await liveCaption(h)
        h.transport.yield(.assistantTranscriptDone("hola mundo"))
        h.transport.yield(.responseDone)
        h.player.position = PlaybackPosition(playedMs: 400, queuedMs: 400)
        h.player.yieldDrained()
        await pumpUntil("the caption settles", timeout: 5) { watch.latest.settled }
    }
}
