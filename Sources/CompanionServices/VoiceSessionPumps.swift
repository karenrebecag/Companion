import CompanionCore
import Foundation

/// The pumps: every stream that feeds the session — server events, mic
/// frames, player drain and levels, synthesizer events. Split out of
/// VoiceSession when it crossed the 400-line gate. What they touch is not
/// `private` any more but still actor-isolated: the actor, not the access
/// level, is what keeps this state single-threaded.
extension VoiceSession {
    func startPumps() {
        if eventTask == nil {
            eventTask = Task { [weak self] in await self?.pumpEvents() }
        }
        if frameTask == nil {
            frameTask = Task { [weak self] in await self?.pumpFrames() }
        }
        if drainTask == nil {
            drainTask = Task { [weak self] in await self?.pumpDrained() }
        }
        if playerLevelTask == nil {
            playerLevelTask = Task { [weak self] in
                await self?.pumpPlayerLevels()
            }
        }
        if speechTask == nil {
            speechTask = Task { [weak self] in await self?.pumpSpeech() }
        }
    }

    func pumpEvents() async {
        for await event in transport.events() {
            if Task.isCancelled { return }
            if event == .sessionUpdated, !realtime.didBecomeReady {
                await apply(.realtimeSessionReady)
                realtime.didBecomeReady = true
            }
            let follow = await realtime.handle(
                event, state: machine.snapshot.state)
            for next in follow { await apply(next) }
        }
        // Stream ended unexpectedly while session was active.
        // FIX 2: Detect when stream ends without explicit close.
        // FIX 3: Attempt reconnect once if network available.
        // Only handle stream end if still in active realtime states (not already failed/idle).
        let state = machine.snapshot.state
        if state == .listening || state == .speaking {
            let online = await reachability.isOnline
            if online && !reconnectAttempted {
                reconnectAttempted = true
                Log.app("voice: reconnect attempt after stream ended")
                await reconnectRealtimeSession()
            } else {
                await apply(.turnFailed(.sessionDropped))
            }
        }
    }

    func reconnectRealtimeSession() async {
        guard let key = openAIKey() else {
            await apply(.turnFailed(.sessionDropped))
            return
        }
        guard let url = RealtimeCodec.url() else {
            await apply(.turnFailed(.sessionDropped))
            return
        }
        do {
            try await transport.open(key: key, url: url)
            // Reconnection succeeded: reset flag and resume pumps.
            reconnectAttempted = false
            startPumps()
        } catch {
            // Reconnection failed: degrade to error state.
            Log.app("voice: reconnect failed")
            await apply(.turnFailed(.sessionDropped))
        }
    }

    func pumpFrames() async {
        for await frame in mic.frames {
            if Task.isCancelled { return }
            lastMic = frame.rms
            levelBox.yield(VoiceLevels(mic: lastMic, agent: lastAgent))
            switch machine.snapshot.pipeline {
            case .classic:
                await transcriber.append(frame)
            case .realtime:
                // Echo-free output (headphones/bluetooth) is as good as AEC:
                // there is no room echo to cancel, so the server may hear the
                // user over the agent and voice barge-in works without VPIO.
                let aec = await mic.hasEchoCancellation || echoFreeOutput
                let snap = machine.snapshot
                guard realtime.shouldForward(
                    frame,
                    muted: snap.muted,
                    aec: aec,
                    state: snap.state,
                    echoGuarded: machine.isEchoGuarded(at: now())
                ) else { continue }
                await realtime.append(frame)
            case nil:
                continue
            }
        }
    }

    func pumpDrained() async {
        for await _ in player.drained {
            if Task.isCancelled { return }
            await apply(.playerDrained)
        }
    }

    func pumpPlayerLevels() async {
        for await value in player.levels {
            if Task.isCancelled { return }
            lastAgent = value
            levelBox.yield(VoiceLevels(mic: lastMic, agent: lastAgent))
        }
    }

    func pumpSpeech() async {
        for await event in synthesizer.events {
            if Task.isCancelled { return }
            switch event {
            case .finished:
                await apply(.speechFinished)
            case .failed:
                await apply(.speechFailed)
            case .level(let value):
                lastAgent = value
                levelBox.yield(VoiceLevels(mic: lastMic, agent: lastAgent))
            case .chunkStarted:
                break
            }
        }
    }
}
