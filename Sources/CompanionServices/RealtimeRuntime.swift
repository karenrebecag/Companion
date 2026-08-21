import CompanionCore
import Foundation

/// Port protocols (VoiceTransport, PCMPlaying, ConversationPresenting) may not
/// conform to Sendable but are safely isolated by exclusive access in VoiceSession.
final class RealtimeRuntime: @unchecked Sendable {
    static let functionRefusal =
        "Los encargos estarán disponibles en una próxima versión."

    let transport: any VoiceTransport
    let player: any PCMPlaying
    let thread: any ConversationPresenting

    var micEnabled = true
    var didBecomeReady = false
    private var pendingUpdate: String?
    private var voiceSent = false

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
    }

    func prepareSessionUpdate(config: Config, history: [Turn]) {
        let voice: VoiceID? = voiceSent ? nil : config.voice.voice
        pendingUpdate = RealtimeCodec.sessionUpdate(
            instructions: Self.instructions(config: config, history: history),
            tools: [],
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
        do {
            try await transport.send(json)
        } catch {
            Log.app("voice: realtime send failed")
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
        if aec { return true }
        return state != .speaking && !echoGuarded
    }

    func handle(
        _ event: RealtimeEvent,
        state: TurnState
    ) async -> [TurnEvent] {
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
        case .functionCall(_, _, let callId):
            await send(
                RealtimeCodec.functionOutput(
                    callId: callId, output: Self.functionRefusal))
            await send(RealtimeCodec.responseCreate())
            return [.functionOutputSent]
        case .serverError(let message):
            Log.app("voice: realtime error \(message)")
            if message.lowercased().contains("session") {
                return [.turnFailed(.sessionDropped)]
            }
            return []
        case .ignored:
            Log.app("voice: ignored realtime event")
            return []
        }
    }

    static func instructions(config: Config, history: [Turn]) -> String {
        var text = ChatPrompt.system(
            ownerFirstName: config.ownerFirstName, delegateEnabled: false)
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
