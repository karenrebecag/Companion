import CompanionCore
import Foundation

/// Opening the realtime socket: mic and player up, the session update sent,
/// the ear started alongside the handshake, and the watchdog that fails
/// loud if the mic never actually delivers a buffer. Split out of
/// VoiceSession when it crossed the 400-line gate. What they touch is not
/// `private` any more but still actor-isolated: the actor, not the access
/// level, is what keeps this state single-threaded.
extension VoiceSession {
    func openRealtimeSession() async {
        realtime.reset()
        reconnectAttempted = false
        echoFreeOutput = echoFreeProbe()
        if echoFreeOutput { Log.app("audio: echo-free output detected") }
        guard let key = openAIKey() else {
            await failRealtimeStart()
            return
        }
        let granted = await mic.requestAccess()
        if !granted {
            await apply(.voiceStartFailed(.micDenied))
            return
        }
        do {
            try await mic.start()
        } catch {
            await apply(.voiceStartFailed(.micUnavailable))
            return
        }
        let aec = await mic.hasEchoCancellation
        do {
            try await player.start(sharedEngine: aec)
        } catch {
            await failRealtimeStart()
            return
        }
        guard let url = RealtimeCodec.url() else {
            await failRealtimeStart()
            return
        }
        // Read config from provider at session open time, allowing preferences
        // to apply without session reconstruction.
        let config = configProvider.current
        // Wave 12c: the user is already talking. The frames queue from here
        // and the ear comes up alongside the socket, not after it; the
        // first word of a hold used to fall in that gap.
        startFramePump()
        let locale = classic.earLocale(config.language)
        earTask = Task { [weak self] in await self?.beginEar(locale: locale) }
        realtime.prepareSessionUpdate(
            config: config, history: await classic.thread.historyTurns(),
            canDelegate: jobs != nil)
        sessionStartTurns = await classic.thread.memoryTurns().count
        do {
            try await transport.open(key: key, url: url)
        } catch {
            await failRealtimeStart(error)
            return
        }
        startPumps()
        await realtime.flushPendingUpdate()
        if await waitForReady() {
            await earTask?.value
            earTask = nil
            armMicSilenceWatchdog()
            return
        }
        if machine.snapshot.state == .connecting {
            // Handshake never completed: unreachable from the user's side.
            await failRealtimeStart(VoiceTransportError.timeout)
        }
    }

    /// The ear, started on the actor while the socket opens. A session that
    /// died meanwhile (offline, refused) takes the ear down with it.
    private func beginEar(locale: String) async {
        await audit.begin(locale: locale)
        let state = machine.snapshot.state
        guard state == .connecting || state == .listening else {
            await audit.end()
            return
        }
        if audit.isLive { timeline.mark(.earReady, at: now()) }
    }

    private func failRealtimeStart(_ error: Error? = nil) async {
        // Offline is not the same as "the realtime server did not answer":
        // classic still works in the second case, but with no network it would
        // trade a readable error for a mic listening in silence.
        let online = await reachability.isOnline
        let failure = online
            ? VoiceFailureMapping.failure(for: error)
            : .networkUnavailable
        await apply(.voiceStartFailed(failure))
        guard online else { return }
        if machine.snapshot.state == .error {
            await apply(.startVoice(preferRealtime: false))
        }
    }

    /// The prototype armed this at the wiring layer: an engine can start
    /// clean and still never deliver a buffer (poisoned HAL, VPIO leftovers).
    /// Waits past MicCapture's own retry window, then fails LOUD instead of
    /// leaving a mic that listens to nothing forever.
    private func armMicSilenceWatchdog() {
        micSilenceTask?.cancel()
        micSilenceTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .seconds(micSilenceTimeout))
            } catch { return }
            await self.checkMicSilence()
        }
    }

    private func checkMicSilence() async {
        let snap = machine.snapshot
        guard snap.pipeline == .realtime,
              snap.state == .listening || snap.state == .connecting,
              await !mic.receivedBuffer else { return }
        Log.app("audio: no mic buffer after \(micSilenceTimeout)s — failing loud")
        await apply(.turnFailed(.micSilent))
    }

    private func waitForReady() async -> Bool {
        if readyTimeout <= 0 { return realtime.didBecomeReady }
        let deadline = ContinuousClock.now + .seconds(readyTimeout)
        while ContinuousClock.now < deadline {
            if realtime.didBecomeReady { return true }
            if machine.snapshot.state != .connecting { return false }
            do {
                try await Task.sleep(for: .milliseconds(5))
            } catch {
                return realtime.didBecomeReady
            }
        }
        return realtime.didBecomeReady
    }
}
