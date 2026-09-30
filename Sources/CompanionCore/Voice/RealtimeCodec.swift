import Foundation

package enum RealtimeEvent: Sendable, Equatable {
    case sessionCreated, sessionUpdated
    case speechStarted, speechStopped
    case userTranscript(String)
    case assistantTranscriptDelta(String)
    case assistantTranscriptDone(String)
    case audioDelta(Data)
    case functionCall(name: String, arguments: String, callId: String)
    case responseCreated
    case responseDone, serverError(String)
    /// A remote MCP tool call waits for the user's yes (9j-3).
    case mcpApprovalRequest(id: String, server: String, tool: String,
                            argumentsJSON: String)
    case agentAudioStarted, agentAudioStopped
    // FIX 5: Preserve unknown event type names for observability, not just generic .ignored.
    case unknown(String)
    // Deprecated: kept for backward compatibility during migration.
    case ignored
}

package enum RealtimeCodec: Sendable {
    package static let model = "gpt-realtime"
    package static let seedTurns = 6
    package static let seedChars = 200

    package static func url(model: String = model) -> URL? {
        URL(string: "wss://api.openai.com/v1/realtime?model=\(model)")
    }

    package static func parse(_ text: String) -> RealtimeEvent {
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
        case "conversation.item.added", "conversation.item.created":
            guard let item = obj["item"] as? [String: Any],
                  item["type"] as? String == "mcp_approval_request",
                  let id = item["id"] as? String else { return .ignored }
            return .mcpApprovalRequest(
                id: id,
                server: item["server_label"] as? String ?? "",
                tool: item["name"] as? String ?? "",
                argumentsJSON: item["arguments"] as? String ?? "")
        case "response.created": return .responseCreated
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

    package static func sessionUpdate(
        instructions: String,
        tools: [ToolSpec],
        voice: VoiceID?,
        speed: Double,
        turnDetection: TurnDetection,
        mcpServers: [MCPServerConfig] = []
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
                    // No input_audio_transcription: OpenAI mis-hears Mexican
                    // Spanish (measured — "Mi madre no invierte" for "crea un
                    // archivo"). Apple es-MX is the source now (Wave 9i).
                    "noise_reduction": ["type": "near_field"],
                    // turn_detection: null — OpenAI does not listen at all. The
                    // mic never reaches it; a local endpointer decides turns and
                    // Apple es-MX provides the text (Wave 9i). No audio in means
                    // no audio conversation item to fight the text one.
                    "turn_detection": NSNull(),
                ],
                "output": output,
            ],
        ]
        // MCP servers ride the same tools array: OpenAI executes their
        // tools server-side, the client only declares and approves (9j-3).
        let allTools = tools.map { $0.realtimeObject() }
            + mcpServers.map { $0.realtimeObject() }
        if !allTools.isEmpty {
            session["tools"] = allTools
        }
        return encodeJSON(["type": "session.update", "session": session])
    }

    package static func seed(from history: [Turn], turns: Int = seedTurns) -> String? {
        guard !history.isEmpty else { return nil }
        return history.suffix(turns).map { turn in
            let who = turn.role == .user ? "Usuario" : "Companion"
            return "\(who): \(String(turn.content.prefix(seedChars)))"
        }.joined(separator: "\n")
    }

    package static func systemItem(_ text: String) -> String {
        encodeJSON([
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "system",
                "content": [["type": "input_text", "text": text]],
            ],
        ])
    }

    /// The user's turn as TEXT — the native (Apple) transcript — so the model
    /// reasons over what was actually said, not what it guessed from the audio.
    package static func userTextItem(_ text: String) -> String {
        encodeJSON([
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content": [["type": "input_text", "text": text]],
            ],
        ])
    }

    /// Seed is truncated plain text; an image cannot survive there. It has
    /// to enter as its own conversation item. Wired in 6c-3.
    /// Speed is the one output knob the server accepts mid-session (the voice
    /// is locked after the first audio frame): a minimal update touches only it.
    package static func speedUpdate(_ speed: Double) -> String {
        let payload: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "realtime",
                "audio": ["output": ["speed": speed]],
            ],
        ]
        return encodeJSON(payload)
    }

    package static func imageItem(dataURL: String, caption: String) -> String {
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

    package static func approvalToolJSON(
        _ language: AppLanguage = .en
    ) -> String {
        ToolSpec.resolveApproval(language).encodeRealtime()
    }

    /// Only a JSON boolean counts — a spoken "sí" must not grant a permission.
    package static func approvalDecision(fromArguments args: String) -> Bool? {
        guard let obj = jsonObject(from: args) else { return nil }
        return jsonBool(obj["approved"])
    }

    package static func appendAudio(_ pcm16le24k: Data) -> String {
        encodeJSON([
            "type": "input_audio_buffer.append",
            "audio": pcm16le24k.base64EncodedString(),
        ])
    }

    package static func commitAudio() -> String {
        encodeJSON(["type": "input_audio_buffer.commit"])
    }

    package static func clearAudio() -> String {
        encodeJSON(["type": "input_audio_buffer.clear"])
    }

    package static func responseCreate() -> String {
        encodeJSON(["type": "response.create"])
    }

    package static func responseCancel() -> String {
        encodeJSON(["type": "response.cancel"])
    }

    /// The user's decision on a remote MCP tool call (9j-3).
    package static func mcpApprovalResponse(
        requestId: String, approve: Bool
    ) -> String {
        encodeJSON([
            "type": "conversation.item.create",
            "item": [
                "type": "mcp_approval_response",
                "approval_request_id": requestId,
                "approve": approve,
            ],
        ])
    }

    package static func functionOutput(callId: String, output: String) -> String {
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

extension RealtimeEvent {
    /// Short label for the turn trace; never includes transcripts or audio.
    package var traceName: String {
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
        case .mcpApprovalRequest(_, let server, let tool, _):
            "mcp.approval \(server)/\(tool)"
        case .responseCreated: "response.created"
        case .responseDone: "response.done"
        case .functionCall: "function.call"
        case .serverError(let message): "server.error \(message)"
        case .ignored: "ignored"
        case .unknown(let typeName): "unknown(\(typeName))"
        }
    }
}
