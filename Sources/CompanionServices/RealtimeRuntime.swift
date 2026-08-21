import CompanionCore
import Foundation

/// Port protocols (VoiceTransport, PCMPlaying, ConversationPresenting) may not
/// conform to Sendable but are safely isolated by exclusive access in VoiceSession.
final class RealtimeRuntime: @unchecked Sendable {
    /// Told to the model, not to the user: it keeps talking while the
    /// specialist works.
    static let functionAccepted =
        "El encargo está en marcha; avisa que lo estás trabajando."

    static let functionRefusal =
        "Los encargos estarán disponibles en una próxima versión."

    let transport: any VoiceTransport
    let player: any PCMPlaying
    let thread: any ConversationPresenting
    /// Set by VoiceSession when a specialist is available.
    var onDelegate: (@Sendable (Handoff) -> Void)?

    var micEnabled = true
    var didBecomeReady = false
    private var pendingUpdate: String?
    private var voiceSent = false
    private var backchannel = BackchannelGate()
    private var transportDown = false

    init(
        transport: any VoiceTransport,
        player: any PCMPlaying,
        thread: any ConversationPresenting
    ) {
        self.transport = transport
        self.player = player
        self.thread = thread
    }

    func reset() {
        micEnabled = true
        didBecomeReady = false
        pendingUpdate = nil
        voiceSent = false
        transportDown = false
    }

    func prepareSessionUpdate(
        config: Config, history: [Turn], canDelegate: Bool = false
    ) {
        let voice: VoiceID? = voiceSent ? nil : config.voice.voice
        // Without the tool declared AND the prompt saying the specialist
        // exists, the model answers "I cannot create files" — it never learns
        // it can hand work over. Wave 3 shipped tools: [] on purpose; Wave 4
        // wired the call but never turned the tool back on.
        pendingUpdate = RealtimeCodec.sessionUpdate(
            instructions: Self.instructions(
                config: config, history: history, canDelegate: canDelegate),
            tools: canDelegate ? [ToolSpec.delegate] : [],
            voice: voice,
            speed: config.voice.speed,
            turnDetection: config.voice.turnDetection)
    }

    func flushPendingUpdate() async {
        guard let json = pendingUpdate else { return }
        pendingUpdate = nil
        voiceSent = true
        await send(json)
    }

    func send(_ json: String) async {
        // One dead socket used to produce a log line per audio frame — ten per
        // second of pure noise. Once the transport is down, stop pushing until
        // a new session resets this.
        guard !transportDown else { return }
        do {
            try await transport.send(json)
        } catch {
            transportDown = true
            Log.app("voice: realtime send failed (\(error)); pausing sends")
        }
    }

    func append(_ frame: MicFrame) async {
        await send(RealtimeCodec.appendAudio(frame.pcm16le24k))
    }

    func commitAndRespond() async {
        await send(RealtimeCodec.commitAudio())
        await send(RealtimeCodec.responseCreate())
    }

    func clearInputAudio() async {
        await send(RealtimeCodec.clearAudio())
    }

    func cancelAgent() async {
        await send(RealtimeCodec.responseCancel())
        await player.flush()
    }

    func close(mic: any MicCapturing) async {
        reset()
        await transport.close()
        await player.stop()
        await mic.stop()
    }

    func shouldForward(
        _ frame: MicFrame,
        muted: Bool,
        aec: Bool,
        state: TurnState,
        echoGuarded: Bool
    ) -> Bool {
        if frame.pcm16le24k.isEmpty || !micEnabled || muted { return false }
        guard state == .speaking else {
            backchannel.reset()
            return !echoGuarded
        }
        // Talking over is only possible with AEC or echo-free output; even
        // then, a short "ajá" must not cut the agent off.
        guard aec else { return false }
        return backchannel.allowsWhileSpeaking(rms: frame.rms)
    }

    func handle(
        _ event: RealtimeEvent,
        state: TurnState
    ) async -> [TurnEvent] {
        Log.app("voice: server \(event.traceName)")
        switch event {
        case .sessionCreated:
            await flushPendingUpdate()
            return []
        case .sessionUpdated:
            return []
        case .speechStarted:
            return [.serverSpeechStarted]
        case .speechStopped:
            return [.serverSpeechStopped]
        case .userTranscript(let text):
            await thread.appendUser(text)
            return []
        case .assistantTranscriptDelta(let delta):
            await thread.showStream(delta)
            return []
        case .assistantTranscriptDone(let text):
            await thread.finishStream()
            await thread.appendAssistant(text)
            return [.replyCompleted]
        case .audioDelta(let pcm):
            await player.play(pcm)
            return state == .speaking ? [] : [.agentAudioStarted]
        case .agentAudioStarted:
            return [.agentAudioStarted]
        case .agentAudioStopped:
            return [.agentAudioStopped]
        case .responseDone:
            let pending = await player.hasPending
            return [.responseCompleted(hasPendingAudio: pending)]
        case .functionCall(let name, let arguments, let callId):
            // Answer the server immediately so the voice keeps flowing; the
            // job runs in the background and its result is announced later.
            guard let onDelegate,
                  let handoff = Handoff.parse(
                      toolName: name, arguments: arguments)
            else {
                await send(
                    RealtimeCodec.functionOutput(
                        callId: callId, output: Self.functionRefusal))
                await send(RealtimeCodec.responseCreate())
                return [.functionOutputSent]
            }
            await send(
                RealtimeCodec.functionOutput(
                    callId: callId, output: Self.functionAccepted))
            await send(RealtimeCodec.responseCreate())
            onDelegate(handoff)
            return [.functionOutputSent]
        case .serverError(let message):
            Log.app("voice: realtime error \(message)")
            if message.lowercased().contains("session") {
                return [.turnFailed(.sessionDropped)]
            }
            return []
        case .ignored:
            return []
        case .unknown:
            // FIX 5: Unknown events are logged with type name via traceName, not generic "ignored".
            return []
        }
    }

    static func instructions(
        config: Config, history: [Turn], canDelegate: Bool = false
    ) -> String {
        var text = ChatPrompt.system(
            ownerFirstName: config.ownerFirstName,
            delegateEnabled: canDelegate,
            about: config.ownerAbout,
            instructions: config.ownerInstructions)
        let tone = config.voice.tone.trimmingCharacters(
            in: .whitespacesAndNewlines)
        if !tone.isEmpty {
            text += "\nCómo debes sonar al hablar: " + tone
        }
        if let seed = RealtimeCodec.seed(from: history) {
            text += "\nContexto de la conversación previa:\n" + seed
        }
        return text
    }
}
