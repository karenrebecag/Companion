import Foundation

public enum RealtimeEvent: Sendable, Equatable {
    case sessionCreated, sessionUpdated
    case speechStarted, speechStopped
    case userTranscript(String)
    case assistantTranscriptDelta(String)
    case assistantTranscriptDone(String)
    case audioDelta(Data)
    case functionCall(name: String, arguments: String, callId: String)
    case responseDone, serverError(String)
    case agentAudioStarted, agentAudioStopped
    // FIX 5: Preserve unknown event type names for observability, not just generic .ignored.
    case unknown(String)
    // Deprecated: kept for backward compatibility during migration.
    case ignored
}

public enum RealtimeCodec: Sendable {
    public static let model = "gpt-realtime"
    public static let seedTurns = 6
    public static let seedChars = 200

    public static func url(model: String = model) -> URL? {
        URL(string: "wss://api.openai.com/v1/realtime?model=\(model)")
    }

    public static func parse(_ text: String) -> RealtimeEvent {
        guard let obj = jsonObject(from: text),
              let type = obj["type"] as? String
        else { return .ignored }
        switch type {
        case "session.created": return .sessionCreated
        case "session.updated": return .sessionUpdated
        case "input_audio_buffer.speech_started": return .speechStarted
        case "input_audio_buffer.speech_stopped": return .speechStopped
        case "conversation.item.input_audio_transcription.completed":
            let t = (obj["transcript"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? .ignored : .userTranscript(t)
        case "response.output_audio_transcript.delta":
            return .assistantTranscriptDelta(obj["delta"] as? String ?? "")
        case "response.output_audio_transcript.done":
            let t = (obj["transcript"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? .ignored : .assistantTranscriptDone(t)
        case "response.output_audio.delta":
            guard let b64 = obj["delta"] as? String,
                  let pcm = Data(base64Encoded: b64), !pcm.isEmpty
            else { return .ignored }
            return .audioDelta(pcm)
        case "response.function_call_arguments.done":
            guard let name = obj["name"] as? String,
                  let args = obj["arguments"] as? String,
                  let callId = obj["call_id"] as? String else { return .ignored }
            return .functionCall(name: name, arguments: args, callId: callId)
        case "response.done": return .responseDone
        case "output_audio_buffer.started": return .agentAudioStarted
        case "output_audio_buffer.stopped", "output_audio_buffer.cleared":
            return .agentAudioStopped
        case "error":
            let err = obj["error"] as? [String: Any]
            return .serverError(err?["message"] as? String ?? "error del servidor")
        default:
            // FIX 5: Preserve unknown type name for observability.
            return .unknown(type)
        }
    }

    public static func sessionUpdate(
        instructions: String,
        tools: [ToolSpec],
        voice: VoiceID?,
        speed: Double,
        turnDetection: TurnDetection
    ) -> String {
        var output: [String: Any] = [
            "format": ["type": "audio/pcm", "rate": 24000],
            "speed": speed,
        ]
        // Voice cannot change after the first audio frame; omit to leave it alone.
        if let voice {
            output["voice"] = voice.rawValue
        }
        var session: [String: Any] = [
            "type": "realtime",
            "instructions": instructions,
            "output_modalities": ["audio"],
            "audio": [
                "input": [
                    "format": ["type": "audio/pcm", "rate": 24000],
                    "transcription": ["model": "gpt-4o-mini-transcribe",
                                      "language": "es"],
                    "noise_reduction": ["type": "near_field"],
                    "turn_detection": turnDetectionJSON(turnDetection),
                ],
                "output": output,
            ],
        ]
        if !tools.isEmpty {
            session["tools"] = tools.map { $0.realtimeObject() }
        }
        return encodeJSON(["type": "session.update", "session": session])
    }

    public static func seed(from history: [Turn], turns: Int = seedTurns) -> String? {
        guard !history.isEmpty else { return nil }
        return history.suffix(turns).map { turn in
            let who = turn.role == .user ? "Usuario" : "Companion"
            return "\(who): \(String(turn.content.prefix(seedChars)))"
        }.joined(separator: "\n")
    }

    public static func systemItem(_ text: String) -> String {
        encodeJSON([
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "system",
                "content": [["type": "input_text", "text": text]],
            ],
        ])
    }

    /// Seed is truncated plain text; an image cannot survive there. It has
    /// to enter as its own conversation item. Wired in 6c-3.
    public static func imageItem(dataURL: String, caption: String) -> String {
        encodeJSON([
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [
                    ["type": "input_text", "text": caption],
                    ["type": "input_image", "image_url": dataURL],
                ],
            ],
        ])
    }

    public static func approvalToolJSON() -> String {
        ToolSpec.resolveApproval.encodeRealtime()
    }

    /// Only a JSON boolean counts — a spoken "sí" must not grant a permission.
    public static func approvalDecision(fromArguments args: String) -> Bool? {
        guard let obj = jsonObject(from: args) else { return nil }
        return jsonBool(obj["approved"])
    }

    public static func appendAudio(_ pcm16le24k: Data) -> String {
        encodeJSON([
            "type": "input_audio_buffer.append",
            "audio": pcm16le24k.base64EncodedString(),
        ])
    }

    public static func commitAudio() -> String {
        encodeJSON(["type": "input_audio_buffer.commit"])
    }

    public static func clearAudio() -> String {
        encodeJSON(["type": "input_audio_buffer.clear"])
    }

    public static func responseCreate() -> String {
        encodeJSON(["type": "response.create"])
    }

    public static func responseCancel() -> String {
        encodeJSON(["type": "response.cancel"])
    }

    public static func functionOutput(callId: String, output: String) -> String {
        encodeJSON([
            "type": "conversation.item.create",
            "item": [
                "type": "function_call_output",
                "call_id": callId,
                "output": output,
            ],
        ])
    }
}

private func turnDetectionJSON(_ detection: TurnDetection) -> [String: Any] {
    switch detection {
    case .serverVAD(let ms):
        return ["type": "server_vad", "silence_duration_ms": ms]
    case .semanticVAD(let eagerness):
        return ["type": "semantic_vad", "eagerness": eagerness.rawValue]
    }
}

extension RealtimeEvent {
    /// Short label for the turn trace; never includes transcripts or audio.
    public var traceName: String {
        switch self {
        case .sessionCreated: "session.created"
        case .sessionUpdated: "session.updated"
        case .speechStarted: "speech.started"
        case .speechStopped: "speech.stopped"
        case .userTranscript: "user.transcript"
        case .assistantTranscriptDelta: "assistant.delta"
        case .assistantTranscriptDone: "assistant.done"
        case .audioDelta(let data): "audio.delta \(data.count)B"
        case .agentAudioStarted: "audio.started"
        case .agentAudioStopped: "audio.stopped"
        case .responseDone: "response.done"
        case .functionCall: "function.call"
        case .serverError(let message): "server.error \(message)"
        case .ignored: "ignored"
        case .unknown(let typeName): "unknown(\(typeName))"
        }
    }
}
