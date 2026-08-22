import CompanionCore
import Foundation

/// Port protocols (VoiceTransport, PCMPlaying, ConversationPresenting) may not
/// conform to Sendable but are safely isolated by exclusive access in VoiceSession.
final class RealtimeRuntime: @unchecked Sendable {
    /// Told to the model, not to the user: it keeps talking while the
    /// specialist works. Model-facing copy follows the answer language, or
    /// the agent narrates the job in one language and the turn in another.
    static func functionAccepted(_ language: AppLanguage) -> String {
        switch language {
        case .en: "The job is under way; say you are working on it."
        case .es: "El encargo está en marcha; avisa que lo estás trabajando."
        }
    }

    static func functionRefusal(_ language: AppLanguage) -> String {
        switch language {
        case .en: "Jobs will be available in a future version."
        case .es: "Los encargos estarán disponibles en una próxima versión."
        }
    }

    let transport: any VoiceTransport
    let player: any PCMPlaying
    let thread: any ConversationPresenting
    /// Set by VoiceSession when a specialist is available.
    var onDelegate: (@Sendable (Handoff) -> Void)?
    /// The user answered a pending permission out loud. Returns whether the
    /// answer landed on a real request: the ack must not tell the model a
    /// permission was granted when there was nothing left to grant.
    var onResolveApproval: (@Sendable (Bool) async -> Bool)?

    var micEnabled = true
    var didBecomeReady = false
    private(set) var pendingUpdate: String?
    private var voiceSent = false
    private var backchannel = BackchannelGate()
    /// Whatever the session was opened with: the tools, the instructions and
    /// every model-facing line have to agree on one language.
    private(set) var language: AppLanguage = .en
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
        language = config.language
        let voice: VoiceID? = voiceSent ? nil : config.voice.voice
        // Without the tool declared AND the prompt saying the specialist
        // exists, the model answers "I cannot create files" — it never learns
        // it can hand work over. Wave 3 shipped tools: [] on purpose; Wave 4
        // wired the call but never turned the tool back on.
        pendingUpdate = RealtimeCodec.sessionUpdate(
            instructions: Self.instructions(
                config: config, history: history, canDelegate: canDelegate),
            // Approvals only exist because jobs exist: the same flag gates
            // both tools. Declared and tested since Wave 4, resolve_approval
            // had no caller outside the suite until Wave 8 — a permission
            // with your hands full died in the 120s auto-deny, unspoken.
            tools: canDelegate
                ? [ToolSpec.delegate(config.language),
                   ToolSpec.resolveApproval(config.language)]
                : [],
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
            if name == ToolSpec.resolveApproval(language).name {
                await resolveApproval(arguments: arguments, callId: callId)
                return [.functionOutputSent]
            }
            // Answer the server immediately so the voice keeps flowing; the
            // job runs in the background and its result is announced later.
            guard let onDelegate,
                  let handoff = Handoff.parse(
                      toolName: name, arguments: arguments)
            else {
                await send(
                    RealtimeCodec.functionOutput(
                        callId: callId, output: Self.functionRefusal(language)))
                await send(RealtimeCodec.responseCreate())
                return [.functionOutputSent]
            }
            await send(
                RealtimeCodec.functionOutput(
                    callId: callId, output: Self.functionAccepted(language)))
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

    /// A spoken "sí" is not a decision until the model turns it into a JSON
    /// boolean: anything else (truncated arguments, `1`, a missing field)
    /// resolves nothing and leaves the request alive for the sheet or a
    /// second try. Granting a permission by accident is unrecoverable.
    private func resolveApproval(arguments: String, callId: String) async {
        let decision = RealtimeCodec.approvalDecision(fromArguments: arguments)
        var output = Escalation.approvalNothingPending(language)
        if let decision, let onResolveApproval {
            if await onResolveApproval(decision) {
                output = Escalation.approvalAck(approved: decision, language)
            }
        } else if decision == nil {
            Log.app("voice: resolve_approval with no usable decision")
        }
        await send(
            RealtimeCodec.functionOutput(callId: callId, output: output))
        await send(RealtimeCodec.responseCreate())
    }

    static func instructions(
        config: Config, history: [Turn], canDelegate: Bool = false
    ) -> String {
        var text = ChatPrompt.system(
            ownerFirstName: config.ownerFirstName,
            delegateEnabled: canDelegate,
            about: config.ownerAbout,
            instructions: config.ownerInstructions,
            language: config.language)
        let tone = config.voice.tone.trimmingCharacters(
            in: .whitespacesAndNewlines)
        if !tone.isEmpty {
            text += "\n" + toneLabel(config.language) + tone
        }
        if let seed = RealtimeCodec.seed(from: history) {
            text += "\n" + seedLabel(config.language) + "\n" + seed
        }
        return text
    }

    private static func toneLabel(_ language: AppLanguage) -> String {
        switch language {
        case .en: "How you should sound when speaking: "
        case .es: "Cómo debes sonar al hablar: "
        }
    }

    private static func seedLabel(_ language: AppLanguage) -> String {
        switch language {
        case .en: "Context from the earlier conversation:"
        case .es: "Contexto de la conversación previa:"
        }
    }
}
