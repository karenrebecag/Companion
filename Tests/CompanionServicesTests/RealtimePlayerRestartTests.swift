@preconcurrency import AVFoundation
import CompanionCore
@testable import CompanionServices
import CompanionTestKit
import Foundation
import Testing

// A mic restart re-attaches the player. Buffers still queued on the old node
// never report back (their epoch is gone), so the turn only leaves .speaking
// if the restart itself says the player drained.

private func offlinePlayer() -> RealtimePlayer {
    RealtimePlayer(makeEngine: {
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!
        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        } catch {
            Issue.record("offline rendering unavailable: \(error)")
        }
        return engine
    })
}

private let someAudio = Data(repeating: 0x10, count: 4_800)

/// True when `drained` yields within `seconds`; the wait is cancelled on expiry.
private func drainedWithin(_ player: RealtimePlayer, seconds: Double) -> Task<Bool, Never> {
    let watcher = Task { () -> Bool in
        for await _ in player.drained { return true }
        return false
    }
    Task {
        try? await Task.sleep(for: .seconds(seconds))
        watcher.cancel()
    }
    return watcher
}

@Suite struct RealtimePlayerRestartTests {
    @Test func restartingWithAudioStillQueuedReportsTheDrain() async throws {
        let player = offlinePlayer()
        try await player.start(sharedEngine: false)
        await player.play(someAudio)
        #expect(await player.hasPending)
        let drained = drainedWithin(player, seconds: 2)
        try await player.start(sharedEngine: false)
        #expect(await drained.value, "reinicio con audio en cola: avisa que se vació")
        #expect(!(await player.hasPending))
    }

    @Test func restartingWithNothingQueuedStaysQuiet() async throws {
        let player = offlinePlayer()
        try await player.start(sharedEngine: false)
        let drained = drainedWithin(player, seconds: 0.3)
        try await player.start(sharedEngine: false)
        #expect(!(await drained.value), "reinicio sin audio: no inventa un vaciado")
    }
}
