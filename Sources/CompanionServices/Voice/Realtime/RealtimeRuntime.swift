import CompanionCore
import Foundation

/// Port protocols (VoiceTransport, PCMPlaying, ConversationPresenting) may not
/// conform to Sendable but are safely isolated by exclusive access in VoiceSession.
/// Every async method is `nonisolated(nonsending)`: it runs on the caller's
/// actor (VoiceSession), so that exclusive access is enforced by the executor
/// and not only by convention. A caller outside the actor loses it.
/// Still `@unchecked Sendable`: dropping it makes VoiceSession.init fail
/// ("cannot access property 'realtime' here in nonisolated initializer"),
/// because init wires callbacks onto the stored runtime. Fixing that means
/// building it in locals before the actor owns it, a change to init.
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

    static func act(
        _ call: ToolCallRef, gate: ParentToolGuard, said: String, language: AppLanguage,
        tools: any ParentToolExecuting
    ) async -> ParentToolOutcome {
        if let denied = await gate.check(call, said: said, language: language, tools: tools) {
            return denied
        }
        // The guard's waits besides the sheet (binding, memory) are cut
        // points too, and this is the last one before the effect.
        if Task.isCancelled {
            tools.withdraw(call)
            return .failed(.interrupted, target: ParentTool.target(of: call), tool: call.name)
        }
        return await tools.execute(name: call.name, argumentsJSON: call.arguments)
    }

    let transport: any VoiceTransport
    let player: any PCMPlaying
    let thread: any ConversationPresenting
    /// Set by VoiceSession when a specialist is available.
    var onDelegate: (@Sendable (Handoff) -> Void)?
    /// The brake, reachable from the voice. Set by the session that owns the
    /// job runner.
    var onStopJob: (@Sendable () async -> Void)?
    /// Wave DM0: the session's clock. Only the runtime knows the instant a
    /// tool call arrives and the instant the parent finished; the session
    /// owns the timeline.
    var markTimeline: (@Sendable (TurnTimeline.Point) async -> Void)?
    /// The user answered a pending permission out loud. Returns whether the
    /// answer landed on a real request: the ack must not tell the model a
    /// permission was granted when there was nothing left to grant.
    var onResolveApproval: (@Sendable (Bool) async -> SpokenApproval)?
    /// A remote MCP tool waits for the user's yes (9j-3); the session parks
    /// it so the spoken resolve_approval can answer it.
    var onMCPApproval: (@Sendable (ApprovalRequest) -> Void)?
    /// The parent's hands (Wave 10b). The server runs the loop; the client
    /// answers each call inline and asks for the next response.
    var parentTools: (any ParentToolExecuting)?
    /// A parent tool's card (a map from `find_places`) takes the job card's
    /// road: the presenter port speaks text only, and the seam that already
    /// paints a specialist's map is the right one for the parent's too.
    /// The session's outward stream (Wave 12a): cards and the parent's hands.
    var events: AudioStreamBox<SessionEvent>?
    /// The `open_url` gate (Wave 10c 3D); empty = fail closed.
    var parentGuard = ParentToolGuard()
    /// What the user last said, for the gate: a URL is only unasked-for
    /// when it is not in these words.
    private(set) var lastUserText = ""

    /// Diagnostic microscope, set by the session. Observes turn boundaries and
    /// the model's goal; never affects the path.
    var audit: VoiceAudit?
    /// The reply as a caption (gap 2), set by the session. Every flush of
    /// the player passes through here, and so must the caption's cut.
    var captions: CaptionFeed?

    var micEnabled = true
    var didBecomeReady = false
    private(set) var pendingUpdate: String?
    private(set) var voiceSent = false
    private var backchannel = BackchannelGate()
    /// The server's response lifecycle, tracked from ITS events — the turn
    /// machine tracks audio playback, and the gap between "audio drained" and
    /// `response.done` is exactly where a commit used to race the server.
    private(set) var responseActive = false
    /// A non-preempting response request that arrived mid-response; sent when
    /// the active one finishes.
    private(set) var pendingResponse = false
    /// What the agent is saying in the CURRENT response — the reference for
    /// text-level echo discrimination (9j-6a): on speakers the mic hears the
    /// agent, so a heard segment overlapping these words is echo, not the
    /// user. The prototype's EchoGuard trick, revived.
    private(set) var agentSpeech = ""
    /// Whatever the session was opened with: the tools, the instructions and
    /// every model-facing line have to agree on one language.
    private(set) var language: AppLanguage = .en
    private(set) var transportDown = false
    /// A reply the network cut, waiting for the player to finish what it
    /// already holds before it joins the thread: threading it earlier would
    /// show the user words their ears have not reached.
    private var unthreadedCut: String?
    /// A cut reply already out of `unthreadedCut` but still on its way into
    /// the thread. The append suspends, so a user turn committed meanwhile
    /// finds nothing to thread and would land above the reply it answers.
    private var threadingCut: Task<Void, Never>?
    /// The same words, owed to the next user turn as a one-shot note.
    private var cutNote: String?
    /// The current response's full text already reached the thread (its
    /// final transcript), so a drop before `response.done` has nothing to add.
    private var replyThreaded = false
    /// The parent's call while the guard holds it. The event loop is not
    /// cancelled by a barge-in, so this is what the cut reaches.
    private var parentCall: Task<ParentToolOutcome, Never>?
    /// Barge-ins so far, for a call that arrived just before one.
    private var cuts = 0

    init(
        transport: any VoiceTransport,
        player: any PCMPlaying,
        thread: any ConversationPresenting
    ) {
        self.transport = transport
        self.player = player
        self.thread = thread
    }

    /// A whole new session: also re-opens the mic, which only the turn
    /// machine's mute may close.
    func reset() {
        micEnabled = true
        resetConnection()
        // A new session has no half-said reply to pick up. One already being
        // appended (`threadingCut`) stays: the user heard it, and its place is
        // before the next turn whatever the session.
        unthreadedCut = nil
        cutNote = nil
    }

    /// What dies with a socket. `micEnabled` is NOT here: it mirrors the
    /// user's mute, and a reconnect must not un-mute anybody.
    func resetConnection() {
        didBecomeReady = false
        pendingUpdate = nil
        voiceSent = false
        transportDown = false
        let partial = dropInFlightResponse()
        if !partial.isEmpty {
            // A later partial wins over an undrained earlier one: it is what
            // was being said when the voice stopped.
            unthreadedCut = partial
            cutNote = partial
        }
    }

    /// The server's response died with the connection; what it had said so
    /// far is handed back before it is cleared.
    private func dropInFlightResponse() -> String {
        // `agentSpeech` outlives a finished reply (the echo guard reads it),
        // so only a response still open on entry was actually cut.
        let wasCut = responseActive && !replyThreaded
        responseActive = false
        pendingResponse = false
        // HACK: `agentSpeech` is the generated transcript, not the played
        // audio, so the partial can include words the user never heard.
        // Upgrade to the player's played-sample count (or
        // conversation.item.truncate) once it is measured that the gap
        // confuses the model on "go on".
        let partial = agentSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
        agentSpeech = ""
        return wasCut ? partial : ""
    }

    /// The cut reply joins the thread as the assistant's, the same way the
    /// classic pipeline threads what it said before a cut. The island says why
    /// the voice stopped only when asked: a user turn that beat the drain has
    /// already been answered, and the card would show up stale at the next
    /// rest. Safe to call when nothing was cut.
    nonisolated(nonsending) func threadCutReply(announce: Bool) async {
        guard let partial = unthreadedCut else { return }
        // Cleared before the first await, so a second caller never threads
        // the same words twice.
        unthreadedCut = nil
        let thread = self.thread
        // Two cuts can be in flight at once (the reconnect and the drain pump
        // both thread); each waits for the one before, so they land in order.
        let earlier = threadingCut
        // Unstructured on purpose: a cancelled drain pump must not leave the
        // reply half-threaded while a committed turn waits on it.
        let append = Task {
            await earlier?.value
            await thread.appendAssistant(partial)
            await thread.finishStream()
        }
        threadingCut = append
        await append.value
        if threadingCut == append { threadingCut = nil }
        if announce { events?.yield(.replyCut) }
    }

    /// The single funnel for asking the server to respond. The server holds
    /// ONE response at a time; five call sites used to race it blind. A user
    /// turn preempts (their voice outranks whatever the agent was saying);
    /// everything else waits its turn.
    nonisolated(nonsending) func requestResponse(preempting: Bool = false) async {
        guard responseActive else {
            await send(RealtimeCodec.responseCreate())
            return
        }
        if preempting {
            await send(RealtimeCodec.responseCancel())
            await captions?.cut()
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
        let parentSpecs = parentTools?.specs(config.language) ?? []
        pendingUpdate = RealtimeCodec.sessionUpdate(
            instructions: Self.instructions(
                config: config, history: history, canDelegate: canDelegate,
                parentToolsEnabled: parentTools != nil,
                handsEnabled: parentSpecs.contains { $0.name == ParentTool.typeText.rawValue },
                sightEnabled: parentSpecs.contains { $0.name == ParentTool.look.rawValue }),
            // Approvals only exist because jobs exist: the same flag gates
            // both tools. Declared and tested since Wave 4, resolve_approval
            // had no caller outside the suite until Wave 8 — a permission
            // with your hands full died in the 120s auto-deny, unspoken.
            tools: parentSpecs
                + (canDelegate
                    ? [ToolSpec.delegate(config.language),
                       ToolSpec.resolveApproval(config.language),
                       ToolSpec.stopJob(config.language)]
                    : []),
            voice: voice,
            speed: config.voice.speed,
            turnDetection: config.voice.turnDetection,
            mcpServers: config.mcpServers)
    }

    nonisolated(nonsending) func flushPendingUpdate() async {
        guard let json = pendingUpdate else { return }
        pendingUpdate = nil
        voiceSent = true
        await send(json)
    }

    nonisolated(nonsending) func send(_ json: String) async {
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

    nonisolated(nonsending) func append(_ frame: MicFrame) async {
        await send(RealtimeCodec.appendAudio(frame.pcm16le24k))
    }

    /// Wave 9i: arm the turn from the ear's transcript — the mic never
    /// reaches the conversation model, so the accurate text IS the turn. The
    /// user's turn preempts whatever the agent was still saying.
    nonisolated(nonsending) func commitWithText(_ text: String, context: TurnContext? = nil) async {
        lastUserText = text
        // A turn that beats the drain must still come after the reply it
        // answers, also when the drain took the reply first and is still
        // appending it: the order cannot rest on the presenter's executor.
        await threadCutReply(announce: false)
        await threadingCut?.value
        await thread.appendUser(text, context: context)
        Log.app("voice: turn from native text \(text.count) chars")
        // The block goes to the server with THIS turn only; the thread keeps
        // the compact line, so the seed never fills with XML (Wave 10a).
        var sent = context
        if let note = cutNote {
            cutNote = nil
            sent = sent ?? TurnContext(source: .voice)
            sent?.replyCutAfter = note
        }
        let payload = sent.map {
            ContextBlock.wrap(text, with: ContextBlock.render($0, language: language))
        } ?? text
        await send(RealtimeCodec.userTextItem(payload))
        await requestResponse(preempting: true)
    }

    nonisolated(nonsending) func clearInputAudio() async {
        await send(RealtimeCodec.clearAudio())
    }

    nonisolated(nonsending) func cancelAgent() async {
        // A barge-in withdraws the sheet the cut reply was waiting on, as a
        // press does in classic (approval-after-cut D3, Karen 2026-10-01).
        cuts += 1
        parentCall?.cancel()
        await send(RealtimeCodec.responseCancel())
        await captions?.cut()
        await player.flush()
    }

    nonisolated(nonsending) func close(mic: any MicCapturing) async {
        reset()
        await transport.close()
        await captions?.cut()
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

    nonisolated(nonsending) func handle(
        _ event: RealtimeEvent,
        state: TurnState
    ) async -> [TurnEvent] {
        Log.app("voice: server \(event.traceName)")
        await captions?.observe(event)
        switch event {
        case .sessionCreated:
            await flushPendingUpdate()
            return []
        case .sessionUpdated:
            return []
        case .speechStarted:
            // A new utterance: what was said before no longer vouches for a
            // URL (10c 3D); the native ear sets it again on commit.
            lastUserText = ""
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
            // The ACCUMULATED text, not the delta: showStream replaces what
            // is on screen, so passing fragments made the bubble flash one
            // word at a time until the finished message landed whole.
            await thread.showStream(agentSpeech)
            return []
        case .assistantTranscriptDone(let text):
            replyThreaded = true
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
        case .mcpApprovalRequest(let id, let server, let tool, let args):
            // OpenAI runs the tool server-side once approved; the client's
            // whole job is the user's click. The request goes to the sheet
            // (`onMCPApproval`) and the model only says, in one short
            // sentence, that a card waits: it never approves.
            onMCPApproval?(ApprovalRequest(
                requestId: id, toolName: "\(server)/\(tool)",
                summary: tool, inputJSON: args, isMCP: true))
            await send(RealtimeCodec.systemItem(
                MCPServerConfig.approvalPrompt(
                    server: server, tool: tool, language)))
            await requestResponse()
            return []
        case .responseCreated:
            responseActive = true
            replyThreaded = false
            // A reply nobody asked for (the user's turn consumed the note
            // before asking) moved the thread on: "continue" would point at
            // a sentence that is no longer the last thing said.
            cutNote = nil
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
            // An action of the parent's own: done here, recorded in the
            // thread, answered to the server — no job, no sheet.
            if let parentTools, parentTools.handles(name) {
                return await runParentCall(
                    ToolCallRef(id: callId, name: name, arguments: arguments), tools: parentTools)
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
            if VoiceFailureMapping.isQuota(message) {
                await captions?.cut()
                return [.turnFailed(.quotaExceeded)]
            }
            if message.lowercased().contains("session") {
                await captions?.cut()
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

    private nonisolated(nonsending) func runParentCall(
        _ call: ToolCallRef, tools: any ParentToolExecuting
    ) async -> [TurnEvent] {
        // The awaits below come before the call is held: a barge-in in
        // between finds nothing to cancel, so it is counted instead.
        let cutsAtArrival = cuts
        await markTimeline?(.toolCallSeen)
        events?.yield(.parentActing(targets: [ParentTool.target(of: call)]))
        let work = Task { [parentGuard, lastUserText, language] in
            await Self.act(call, gate: parentGuard, said: lastUserText, language: language, tools: tools)
        }
        parentCall = work
        if cuts != cutsAtArrival { work.cancel() }
        // Closing the session cancels the loop, not the call.
        let outcome = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        // A closed session's call can unwind after the next session holds
        // its own.
        if parentCall == work { parentCall = nil }
        await thread.appendStatus(ParentToolCopy.status(call.name, outcome, language))
        if let card = outcome.card { events?.yield(.job(.card(card))) }
        events?.yield(.parentActed)
        await markTimeline?(.toolDone)
        // A cut call is still answered, or the model's next request is
        // malformed; but the user who cut it is talking, and their own turn
        // asks for the next response. A cut that lands during `execute`
        // cannot undo the effect; it only keeps the model quiet.
        await send(RealtimeCodec.functionOutput(callId: call.id, output: outcome.output))
        if work.isCancelled { return [] }
        await requestResponse()
        return [.functionOutputSent]
    }

    /// A spoken "sí" is not a decision until the model turns it into a JSON
    /// boolean: anything else (truncated arguments, `1`, a missing field)
    /// resolves nothing and leaves the request alive for the sheet or a
    /// second try. Granting a permission by accident is unrecoverable.
    private nonisolated(nonsending) func resolveApproval(arguments: String, callId: String) async {
        let decision = RealtimeCodec.approvalDecision(fromArguments: arguments)
        var output = Escalation.approvalNothingPending(language)
        if let decision, let onResolveApproval {
            switch await onResolveApproval(decision) {
            case .resolved: output = Escalation.approvalAck(approved: decision, language)
            case .needsClick: output = Escalation.approvalNeedsClick(language)
            case .nothingPending: break
            }
        } else if decision == nil {
            Log.app("voice: resolve_approval with no usable decision")
        }
        await send(
            RealtimeCodec.functionOutput(callId: callId, output: output))
        await requestResponse()
    }

    static func instructions(
        config: Config, history: [Turn], canDelegate: Bool = false,
        parentToolsEnabled: Bool = false, handsEnabled: Bool = false, sightEnabled: Bool = false
    ) -> String {
        var text = ChatPrompt.system(
            ownerFirstName: config.ownerFirstName,
            delegateEnabled: canDelegate,
            parentToolsEnabled: parentToolsEnabled,
            handsEnabled: handsEnabled,
            sightEnabled: sightEnabled,
            about: config.ownerAbout,
            instructions: config.ownerInstructions,
            language: config.language,
            memory: config.memory,
            skills: config.skills)
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
