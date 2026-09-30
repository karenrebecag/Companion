import CompanionCore
@testable import CompanionServices
import Foundation
import Testing

// A dropped socket is a NEW server session: it starts on the server's
// defaults and nobody reads its events unless the pump loops again.

/// The runtime's state as the session's actor sees it. The runtime is
/// confined to that actor, so a test reading `session.realtime` from the main
/// thread races the pump writing it; this hops onto the actor to read.
struct RealtimeSnapshot {
    var ready, micEnabled, transportDown, pendingResponse, responseActive: Bool
    var agentSpeech: String
}

extension VoiceSession {
    func realtimeSnapshot() -> RealtimeSnapshot {
        RealtimeSnapshot(
            ready: realtime.didBecomeReady, micEnabled: realtime.micEnabled,
            transportDown: realtime.transportDown,
            pendingResponse: realtime.pendingResponse,
            responseActive: realtime.responseActive,
            agentSpeech: realtime.agentSpeech)
    }

    /// Runs on the actor, like the production callers of these methods.
    func probeAppend(_ frame: MicFrame) async { await realtime.append(frame) }
    func probeRequestResponse() async { await realtime.requestResponse() }
}

private func sessionUpdates(_ h: VoiceHarness) -> [String] {
    h.transport.sent.filter { $0.contains("\"session.update\"") }
}

/// Starts realtime, waits for the first update, then drops the socket and
/// waits for the one reconnect the session allows.
@MainActor private func startAndDrop(_ h: VoiceHarness) async {
    await h.session.start()
    await pumpUntil("listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .realtime
    }
    await pumpUntil("first update") { sessionUpdates(h).count == 1 }
    await h.transport.simulateStreamEnd()
    await pumpUntil("reconnected", timeout: 5) { h.transport.openCount == 2 }
}

@Test @MainActor func reconnectKeepsReadingServerEvents() async {
    let h = makeVoiceHarness(online: true)
    await startAndDrop(h)

    h.transport.yield(.speechStarted)
    await pumpUntil("new stream is consumed") { h.watch.latest.speechOpen }
}

@Test @MainActor func reconnectResendsSessionConfigWithCurrentHistory() async {
    let h = makeVoiceHarness(online: true, jobs: ApprovingSubmitter())
    await h.session.start()
    await pumpUntil("first update") { sessionUpdates(h).count == 1 }
    await pumpUntil("listening") { h.watch.latest.state == .listening }
    h.thread.history = [Turn(role: .user, content: "zebra-marker-said-before-the-drop")]

    await h.transport.simulateStreamEnd()
    await pumpUntil("update on the new connection", timeout: 5) {
        sessionUpdates(h).count == 2
    }
    // A later event proves the pump passed the new connection's own
    // session.created, which would flush a second time if it could.
    h.transport.yield(.speechStarted)
    await pumpUntil("new stream is consumed") { h.watch.latest.speechOpen }

    let updates = sessionUpdates(h)
    expectEq(updates.count, 2, "exactly one update per connection")
    guard updates.count == 2 else { return }
    expect(!updates[0].contains("zebra-marker"), "first update predates the turn")
    expect(updates[1].contains("instructions"), "instructions are re-sent")
    expect(updates[1].contains("\"delegate\""), "tools are re-sent")
    expect(updates[1].contains("zebra-marker-said-before-the-drop"),
           "history is re-seeded from the thread")
}

@Test @MainActor func reconnectKeepsAMutedMicMuted() async {
    let h = makeVoiceHarness(online: true)
    await h.session.start()
    await pumpUntil("listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .realtime
    }
    await h.session.toggleMute()
    await pumpUntil("muted") { h.watch.latest.muted }
    expect(await h.session.realtimeSnapshot().micEnabled == false, "mic gated while muted")

    await h.transport.simulateStreamEnd()
    await pumpUntil("reconnected", timeout: 5) { h.transport.openCount == 2 }
    // The second update goes out right after the per-connection reset, so
    // seeing it means the reset already ran.
    await pumpUntil("new connection handled", timeout: 5) {
        sessionUpdates(h).count == 2
    }

    expect(h.watch.latest.muted, "machine still muted")
    expect(await h.session.realtimeSnapshot().micEnabled == false,
           "reconnect must not re-open a muted mic")
}

@Test @MainActor func aReconnectThatNeverBecomesReadyIsNotRetried() async {
    let h = makeVoiceHarness(online: true)
    await h.session.start()
    await pumpUntil("listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .realtime
    }
    // The second connection opens but dies before session.updated: the one
    // retry is spent, or the pump would reopen in a hot loop.
    h.transport.autoEvents = []
    await h.transport.simulateStreamEnd()
    await pumpUntil("reconnected", timeout: 5) { h.transport.openCount == 2 }
    await h.transport.simulateStreamEnd()

    await pumpUntil("gives up", timeout: 5) { h.watch.latest.state == .error }
    expectEq(h.transport.openCount, 2, "no third open")
}

@Test @MainActor func connectionResetKeepsMicButClearsConnectionState() async {
    let runtime = RealtimeRuntime(
        transport: ScriptedVoiceTransport(), player: ScriptedPlayer(),
        thread: ScriptedThread())
    runtime.micEnabled = false
    runtime.didBecomeReady = true
    _ = await runtime.handle(.assistantTranscriptDelta("hola"), state: .speaking)
    runtime.prepareSessionUpdate(config: Config(ownerFirstName: "Karen"), history: [])
    await runtime.flushPendingUpdate()
    _ = await runtime.handle(.responseCreated, state: .speaking)
    await runtime.requestResponse()
    runtime.prepareSessionUpdate(config: Config(ownerFirstName: "Karen"), history: [])
    expect(runtime.voiceSent && runtime.pendingResponse, "precondition: connection state is dirty")

    runtime.resetConnection()
    expect(!runtime.voiceSent, "voice lock cleared")
    expect(!runtime.pendingResponse, "queued response cleared")

    expect(!runtime.micEnabled, "mic mirror survives")
    expect(!runtime.didBecomeReady, "ready flag cleared")
    expectEq(runtime.agentSpeech, "", "agent speech cleared")
    expect(!runtime.responseActive, "response flag cleared")
    expect(runtime.pendingUpdate == nil, "stale update dropped")
}

/// The runtime's state is confined to the caller's actor, so two flushes
/// issued from that actor send once. From a bare `addTask` or `Task.detached`
/// closure the calls would hop to the generic executor with or without `nonsending`, and the
/// test would prove nothing: hence `@MainActor` on each closure. TSan is the
/// oracle for the data race; the count catches the double send.
@Test @MainActor func concurrentFlushesFromAnActorSendOneUpdate() async {
    var doubled = 0
    for _ in 0..<1000 {
        let transport = ScriptedVoiceTransport()
        let runtime = RealtimeRuntime(
            transport: transport, player: ScriptedPlayer(), thread: ScriptedThread())
        runtime.prepareSessionUpdate(config: Config(ownerFirstName: "Karen"), history: [])
        let first = Task { @MainActor in await runtime.flushPendingUpdate() }
        let second = Task { @MainActor in await runtime.flushPendingUpdate() }
        await first.value
        await second.value
        if transport.sent.filter({ $0.contains("\"session.update\"") }).count != 1 {
            doubled += 1
        }
    }
    expectEq(doubled, 0, "iterations that sent the update other than once")
}

/// Same contract as the runtime's: the audit's frame tally is written before
/// its first suspension, so two calls from the session's actor must queue
/// on that actor instead of overlapping on the generic executor. The oracle
/// is TSan alone: the fake's locked counter cannot see the race, so this
/// passes without `--sanitize=thread` even on broken code.
@Test @MainActor func concurrentAuditHearsFromAnActorKeepEveryFrame() async {
    let ear = ScriptedTranscriber()
    let audit = VoiceAudit(native: ear)
    await audit.begin(locale: "en-US")
    let frame = MicFrame(pcm16le24k: Data([1, 2]), rms: 0.5)
    for _ in 0..<500 {
        let first = Task { @MainActor in
            await audit.hear(frame, forwarded: true, reason: nil)
        }
        let second = Task { @MainActor in
            await audit.hear(frame, forwarded: true, reason: nil)
        }
        await first.value
        await second.value
    }
    expectEq(ear.appended.count, 1000, "every frame reached the ear")
}

// MARK: - Session lifecycle around a reconnect

/// Waits for the `n`th open to have its config out and be ready. `updates`
/// differs from `n` only when an open was held and never configured.
@MainActor private func connectionReady(
    _ h: VoiceHarness, _ n: Int, updates: Int? = nil
) async {
    await pumpUntilAsync("connection \(n) ready", timeout: 5) {
        guard h.transport.openCount == n, sessionUpdates(h).count == updates ?? n
        else { return false }
        return await h.session.realtimeSnapshot().ready
    }
}

@MainActor private func startListening(_ h: VoiceHarness) async {
    await h.session.start()
    await pumpUntil("listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .realtime
    }
    await connectionReady(h, 1)
}

@Test @MainActor func aHangUpDuringAReconnectLeavesTheSessionIdle() async {
    let h = makeVoiceHarness(online: true)
    await startListening(h)
    h.transport.holdNextOpen = true
    // A failing path must not leave the held open suspended forever.
    defer { h.transport.releaseOpen() }
    await h.transport.simulateStreamEnd()
    await pumpUntil("open entered", timeout: 5) { h.transport.openEntered }

    await h.session.hangUp()
    await pumpUntil("hung up") { h.watch.latest.state == .idle }
    let closesAtHangUp = h.transport.closeCount
    h.transport.releaseOpen()

    // The socket that finished opening after the hang-up is closed again.
    await pumpUntil("late socket closed", timeout: 2) {
        h.transport.closeCount > closesAtHangUp
    }
    expectEq(h.watch.latest.state, .idle, "no failure after the hang-up")
    expectEq(sessionUpdates(h).count, 1, "nothing is configured on a dead session")
}

@Test @MainActor func aLateReconnectNeverTouchesANewSession() async {
    let h = makeVoiceHarness(online: true)
    await startListening(h)
    h.transport.holdNextOpen = true
    // A failing path must not leave the held open suspended forever.
    defer { h.transport.releaseOpen() }
    await h.transport.simulateStreamEnd()
    await pumpUntil("open entered", timeout: 5) { h.transport.openEntered }

    await h.session.hangUp()
    await pumpUntil("hung up") { h.watch.latest.state == .idle }
    await h.session.start()
    await pumpUntil("new session listening") {
        h.watch.latest.state == .listening && h.watch.latest.pipeline == .realtime
    }
    await connectionReady(h, 3, updates: 2)
    h.transport.releaseOpen()
    await pumpUntil("held open returned", timeout: 5) { h.transport.openReturned == 3 }

    h.transport.yield(.speechStarted)
    await pumpUntil("new session still served") { h.watch.latest.speechOpen }
    expectEq(sessionUpdates(h).count, 2, "the stale reconnect sent no update of its own")
    expect(h.watch.latest.state != .error, "the stale reconnect did not fail the new session")
    expect(await h.session.realtimeSnapshot().ready, "new session's ready flag was not reset")
}

// MARK: - Send failures

@Test @MainActor func aPausedTransportResumesOnReconnect() async {
    let h = makeVoiceHarness(online: true)
    await startListening(h)
    let frame = MicFrame(pcm16le24k: Data([1, 2]), rms: 0.5)

    h.transport.sendFails = true
    await h.session.probeAppend(frame)
    let attemptsAfterFailure = h.transport.sendAttempts
    await h.session.probeAppend(frame)
    await h.session.probeAppend(frame)
    expectEq(h.transport.sendAttempts, attemptsAfterFailure,
             "sends after the failure are dropped, not retried")

    h.transport.sendFails = false
    await h.transport.simulateStreamEnd()
    await pumpUntilAsync("config on the new connection", timeout: 5) {
        sessionUpdates(h).count == 2
    }
    expect(!(await h.session.realtimeSnapshot().transportDown), "the pause ended with the old socket")
}

// MARK: - Reconnect budget

@Test @MainActor func reconnectsAreBoundedPerWindow() async {
    let h = makeVoiceHarness(online: true)
    await startListening(h)
    for n in 2...4 {
        await h.transport.simulateStreamEnd()
        await connectionReady(h, n)
    }

    await h.transport.simulateStreamEnd()
    await pumpUntil("budget spent", timeout: 5) { h.watch.latest.state == .error }
    expectEq(h.transport.openCount, 4, "no fourth reconnect inside the window")
}

@Test @MainActor func theReconnectBudgetRefillsAsTimePasses() async {
    let h = makeVoiceHarness(online: true)
    await startListening(h)
    for n in 2...4 {
        await h.transport.simulateStreamEnd()
        await connectionReady(h, n)
    }
    h.clock.now += 61

    await h.transport.simulateStreamEnd()
    await connectionReady(h, 5)
    expect(h.watch.latest.state != .error, "an old reconnect no longer counts")
}

@Test @MainActor func aSecondDropAfterReadyReconnectsAgain() async {
    let h = makeVoiceHarness(online: true)
    await startListening(h)
    await h.transport.simulateStreamEnd()
    await connectionReady(h, 2)
    await h.transport.simulateStreamEnd()
    await connectionReady(h, 3)

    expectEq(h.transport.openCount, 3, "a ready connection earns its retry")
    expectEq(sessionUpdates(h).count, 3, "every connection gets its config")
}

// MARK: - Stale approvals

private actor ParkingApprovals: ApprovalsProvider {
    private var pending: [String: CheckedContinuation<ApprovalResponse, Never>] = [:]
    func request(_ approval: ApprovalRequest) async -> ApprovalResponse {
        await withCheckedContinuation { pending[approval.requestId] = $0 }
    }
    func resolve(requestId: String, approved: Bool) async -> Bool {
        guard let waiter = pending.removeValue(forKey: requestId) else { return false }
        waiter.resume(returning: ApprovalResponse(requestId: requestId, approved: approved))
        return true
    }
}

@Test @MainActor func aReconnectDropsMCPApprovalsOfTheDeadConnection() async {
    let approvals = ParkingApprovals()
    let h = makeVoiceHarness(online: true, approvals: approvals)
    await startListening(h)
    let request = ApprovalRequest(
        requestId: "m1", toolName: "docs/search", summary: "search",
        inputJSON: "{}", isMCP: true)
    let deciding = Task { await h.session.noteMCPApproval(request) }
    await pumpUntilAsync("parked", timeout: 5) {
        await h.session.pendingMCPApprovals.count == 1
    }

    await h.transport.simulateStreamEnd()
    await connectionReady(h, 2)

    expect(await h.session.pendingMCPApprovals.isEmpty,
           "an id from the old connection must not be answerable on the new one")
    // Frees the parked decision so a failing run ends instead of hanging.
    _ = await approvals.resolve(requestId: "m1", approved: false)
    await deciding.value
}

// MARK: - A drop mid-speech

@Test @MainActor func aDropMidSpeechClearsTheDeadResponseAndResumes() async {
    let h = makeVoiceHarness(online: true)
    await startListening(h)
    h.transport.yield(.responseCreated)
    h.transport.yield(.assistantTranscriptDelta("hola"))
    h.transport.yield(.audioDelta(Data([1, 2])))
    await pumpUntil("speaking") { h.watch.latest.state == .speaking }
    await pumpUntilAsync("response in flight") { await h.session.realtimeSnapshot().agentSpeech == "hola" }
    await h.session.probeRequestResponse()
    expect(await h.session.realtimeSnapshot().pendingResponse, "precondition: a response is queued")

    await h.transport.simulateStreamEnd()
    await connectionReady(h, 2)

    let after = await h.session.realtimeSnapshot()
    expect(!after.responseActive, "dead response cleared")
    expect(!after.pendingResponse, "queued response cleared")
    expectEq(after.agentSpeech, "", "echo reference cleared")
    let before = h.transport.sent.filter { $0.contains("response.create") }.count
    await h.session.probeRequestResponse()
    expectEq(h.transport.sent.filter { $0.contains("response.create") }.count, before + 1,
             "a new request is sent, not queued forever")
    expectEq(sessionUpdates(h).count, 2, "config re-sent")
    h.transport.yield(.speechStarted)
    await pumpUntil("pump resumed") { h.watch.latest.speechOpen }
}
