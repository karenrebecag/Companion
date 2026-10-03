import CompanionCore
import Testing

private actor RecordingMuter: OtherAudioMuting {
    private(set) var calls: [String] = []
    func mute() { calls.append("mute") }
    func unmute() { calls.append("unmute") }
}

private final class Flag: @unchecked Sendable {
    nonisolated(unsafe) var value: Bool
    init(_ value: Bool) { self.value = value }
}

@MainActor
private func run(
    enabled: Bool, kinds: [SessionKind]
) async -> [String] {
    let muter = RecordingMuter()
    let flag = Flag(enabled)
    let coordinator = OtherAudioMuteCoordinator(muter: muter, isEnabled: { flag.value })
    for kind in kinds { coordinator.observe(kind) }
    await coordinator.finish()
    return await muter.calls
}

@Suite struct OtherAudioMuteDecisionTests {
    @Test func onlyListeningWithThePreferenceOnSilences() {
        let kinds: [SessionKind] = [
            .idle, .hover, .listening, .processing(.pending), .processing(.thinking),
            .processing(.speaking), .processing(.toolExecuting),
            .processing(.subAgentRunning), .processing(.completed),
        ]
        for kind in kinds {
            #expect(OtherAudioMuteDecision.shouldMute(enabled: true, kind: kind) == (kind == .listening),
                    "enabled, \(kind)")
            #expect(!OtherAudioMuteDecision.shouldMute(enabled: false, kind: kind), "disabled, \(kind)")
        }
    }
}

@Suite @MainActor struct OtherAudioMuteCoordinatorTests {
    @Test func preferenceOffNeverMutes() async {
        let calls = await run(
            enabled: false,
            kinds: [.idle, .listening, .processing(.pending), .listening, .idle])
        #expect(calls.isEmpty)
    }

    @Test func mutesOnEnteringListeningAndRestoresOnEveryRoadOut() async {
        let exits: [SessionKind] = [
            .processing(.pending), .processing(.thinking), .processing(.speaking),
            .processing(.completed), .idle, .hover,
        ]
        for exit in exits {
            let calls = await run(enabled: true, kinds: [.idle, .listening, exit])
            #expect(calls == ["mute", "unmute"], "exit via \(exit)")
        }
    }

    @Test func repeatedTransitionsCallEachSideOnce() async {
        let calls = await run(
            enabled: true,
            kinds: [.listening, .listening, .listening, .processing(.pending),
                    .processing(.pending), .idle, .idle])
        #expect(calls == ["mute", "unmute"])
    }

    @Test func eachListeningTurnMutesAgain() async {
        let calls = await run(
            enabled: true,
            kinds: [.listening, .idle, .listening, .processing(.pending)])
        #expect(calls == ["mute", "unmute", "mute", "unmute"])
    }

    @Test func turningThePreferenceOffWhileListeningRestoresAtOnce() async {
        let muter = RecordingMuter()
        let flag = Flag(true)
        let coordinator = OtherAudioMuteCoordinator(muter: muter, isEnabled: { flag.value })
        coordinator.observe(.listening)
        flag.value = false
        coordinator.preferenceDidChange()
        coordinator.observe(.listening)
        await coordinator.finish()
        #expect(await muter.calls == ["mute", "unmute"])
    }

    @Test func turningThePreferenceOnWhileListeningMutes() async {
        let muter = RecordingMuter()
        let flag = Flag(false)
        let coordinator = OtherAudioMuteCoordinator(muter: muter, isEnabled: { flag.value })
        coordinator.observe(.listening)
        flag.value = true
        coordinator.preferenceDidChange()
        await coordinator.finish()
        #expect(await muter.calls == ["mute"])
    }

    @Test func preferenceChangeAtRestCallsNothing() async {
        let muter = RecordingMuter()
        let flag = Flag(false)
        let coordinator = OtherAudioMuteCoordinator(muter: muter, isEnabled: { flag.value })
        flag.value = true
        coordinator.preferenceDidChange()
        flag.value = false
        coordinator.preferenceDidChange()
        await coordinator.finish()
        #expect(await muter.calls.isEmpty)
    }

    @Test func shutdownWhileMutedQueuesAFinalUnmute() async {
        let muter = RecordingMuter()
        let coordinator = OtherAudioMuteCoordinator(muter: muter, isEnabled: { true })
        coordinator.observe(.listening)
        coordinator.shutdown()
        await coordinator.finish()
        #expect(await muter.calls == ["mute", "unmute"])
    }

    @Test func shutdownWhenNotMutedCallsNothing() async {
        let muter = RecordingMuter()
        let coordinator = OtherAudioMuteCoordinator(muter: muter, isEnabled: { true })
        coordinator.observe(.idle)
        coordinator.shutdown()
        await coordinator.finish()
        #expect(await muter.calls.isEmpty)
    }

    @Test func observeAfterShutdownCannotMute() async {
        let muter = RecordingMuter()
        let coordinator = OtherAudioMuteCoordinator(muter: muter, isEnabled: { true })
        coordinator.shutdown()
        coordinator.observe(.listening)
        coordinator.preferenceDidChange()
        await coordinator.finish()
        #expect(await muter.calls.isEmpty)
    }

    @Test func aSlowMuteDoesNotReorderTheCalls() async {
        let muter = GatedMuter()
        let coordinator = OtherAudioMuteCoordinator(muter: muter, isEnabled: { true })
        coordinator.observe(.listening)
        coordinator.observe(.idle)
        coordinator.observe(.listening)
        await muter.release()
        await coordinator.finish()
        #expect(await muter.calls == ["mute", "unmute", "mute"])
    }
}

/// `mute()` parks on a continuation until the test releases it, like an
/// adapter whose Core Audio call is slow.
private actor GatedMuter: OtherAudioMuting {
    private(set) var calls: [String] = []
    private var gate: CheckedContinuation<Void, Never>?
    private var released = false

    func mute() async {
        if !released {
            await withCheckedContinuation { gate = $0 }
        }
        calls.append("mute")
    }

    func unmute() { calls.append("unmute") }

    func release() async {
        released = true
        gate?.resume()
        gate = nil
    }
}
