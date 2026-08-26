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
    /// The brake, reachable from the voice. Set by the session that owns the
    /// job runner.
    var onStopJob: (@Sendable () async -> Void)?
    /// The user answered a pending permission out loud. Returns whether the
    /// answer landed on a real request: the ack must not tell the model a
    /// permission was granted when there was nothing left to grant.
    var onResolveApproval: (@Sendable (Bool) async -> Bool)?

    /// Diagnostic microscope, set by the session. Observes turn boundaries and
    /// the model's goal; never affects the path.
    var audit: VoiceAudit?

    var micEnabled = true
    var didBecomeReady = false
    private(set) var pendingUpdate: String?
    private var voiceSent = false
    private var backchannel = BackchannelGate()
    /// The server's response lifecycle, tracked from ITS events — the turn
    /// machine tracks audio playback, and the gap between "audio drained" and
    /// `response.done` is exactly where a commit used to race the server.
    private(set) var responseActive = false
    /// A non-preempting response request that arrived mid-response; sent when
    /// the active one finishes.
    private var pendingResponse = false
    /// What the agent is saying in the CURRENT response — the reference for
    /// text-level echo discrimination (9j-6a): on speakers the mic hears the
    /// agent, so a heard segment overlapping these words is echo, not the
    /// user. The prototype's EchoGuard trick, revived.
    private(set) var agentSpeech = ""
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
        responseActive = false
        pendingResponse = false
        agentSpeech = ""
    }

    /// The single funnel for asking the server to respond. The server holds
    /// ONE response at a time; five call sites used to race it blind. A user
    /// turn preempts (their voice outranks whatever the agent was saying);
    /// everything else waits its turn.
    func requestResponse(preempting: Bool = false) async {
        guard responseActive else {
            await send(RealtimeCodec.responseCreate())
            return
        }
        if preempting {
            await send(RealtimeCodec.responseCancel())
            await player.flush()
            // The server processes in order: the cancel lands first.
            await send(RealtimeCodec.responseCreate())
        } else {
            pendingResponse = true
        }
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
                   ToolSpec.resolveApproval(config.language),
                   ToolSpec.stopJob(config.language)]
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

    /// Wave 9i: arm the turn from the ear's transcript — the mic never
    /// reaches the conversation model, so the accurate text IS the turn. The
    /// user's turn preempts whatever the agent was still saying.
    func commitWithText(_ text: String) async {
        await thread.appendUser(text)
        Log.app("voice: turn from native text «\(text)»")
        await send(RealtimeCodec.userTextItem(text))
        await requestResponse(preempting: true)
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
            // Wave 9i: OpenAI does not do VAD (turn_detection null); if a stray
            // event arrives it is harmless — turns are driven locally.
            return [.serverSpeechStarted]
        case .speechStopped:
            return [.serverSpeechStopped]
        case .userTranscript:
            // Wave 9i: OpenAI's transcription is off; if a stray one arrives it
            // is ignored — Apple es-MX is the source, delivered on commit.
            return []
        case .assistantTranscriptDelta(let delta):
            agentSpeech += delta
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
        case .responseCreated:
            responseActive = true
            // A fresh response is a fresh utterance: the echo reference must
            // not accumulate the whole session.
            agentSpeech = ""
            return []
        case .responseDone:
            responseActive = false
            if pendingResponse {
                pendingResponse = false
                await send(RealtimeCodec.responseCreate())
            }
            let pending = await player.hasPending
            return [.responseCompleted(hasPendingAudio: pending)]
        case .functionCall(let name, let arguments, let callId):
            if name == ToolSpec.resolveApproval(language).name {
                await resolveApproval(arguments: arguments, callId: callId)
                return [.functionOutputSent]
            }
            if name == ToolSpec.stopJob(language).name {
                await onStopJob?()
                await send(RealtimeCodec.functionOutput(
                    callId: callId, output: "stopped"))
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
                await requestResponse()
                return [.functionOutputSent]
            }
            await send(
                RealtimeCodec.functionOutput(
                    callId: callId, output: Self.functionAccepted(language)))
            await requestResponse()
            audit?.noteGoal(handoff.goal)
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
        await requestResponse()
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
