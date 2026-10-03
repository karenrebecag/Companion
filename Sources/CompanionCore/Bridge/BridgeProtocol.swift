import Foundation

/// Wave 17. The wire protocol for the local bridge: a stable JSON-based
/// request-response contract that Companion publishes and the shim consumes.
/// Pure Codable shapes; the actor and socket handling live in Services.

// MARK: - Message Structure

package enum BridgeMethod: String, Codable, Sendable {
    case hello
    case call
    case bye
}

/// First message: the token and protocol version. The shim reads the token
/// from bridge.token (0600 file) and sends it here; if it does not match or
/// the file does not exist, Companion closes without a sheet.
package struct BridgeHello: Codable, Sendable, Equatable {
    package var token: String
    package var client: String
    package var protocolVersion: Int

    package init(token: String, client: String = "claude-code", protocolVersion: Int = 1) {
        self.token = token
        self.client = client
        self.protocolVersion = protocolVersion
    }

    enum CodingKeys: String, CodingKey {
        case token
        case client
        case protocolVersion = "protocol"
    }
}

/// A tool call: name and arguments as a JSON object on the wire.
/// The codec compacts arguments to a string for `ParentToolRunner.execute`.
package struct BridgeCall: Sendable, Equatable {
    package var name: String
    package var argumentsJSON: String

    package init(name: String, argumentsJSON: String) {
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

/// Inbound messages: hello, call, or bye. The id is stable across the
/// lifetime of a session to let the shim correlate responses.
package enum BridgeRequest: Sendable, Equatable {
    case hello(id: Int, BridgeHello)
    case call(id: Int, BridgeCall)
    case bye(id: Int)
}

// MARK: - Tool Specs

/// A Codable mirror of ToolSpec so the shim can build JSON Schema
/// and register tools from the hello result without duplicating schema logic.
package struct BridgeToolSpec: Codable, Sendable, Equatable {
    package var name: String
    package var description: String
    package var properties: [BridgeToolProperty]
    package var required: [String]

    package init(_ spec: ToolSpec) {
        self.name = spec.name
        self.description = spec.description
        self.properties = spec.properties.map { BridgeToolProperty($0) }
        self.required = spec.required
    }

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case properties
        case required
    }
}

package struct BridgeToolProperty: Codable, Sendable, Equatable {
    package var name: String
    package var type: String
    package var description: String
    package var allowed: [String]?
    package var minLength: Int?
    package var maxBytes: Int?

    package init(_ property: ToolProperty) {
        self.name = property.name
        self.type = property.type
        self.description = property.description
        self.allowed = property.allowed
        self.minLength = property.minLength
        self.maxBytes = property.maxBytes
    }

    enum CodingKeys: String, CodingKey {
        case name
        case type
        case description
        case allowed = "enum"
        case minLength
        case maxBytes
    }
}

// MARK: - Results

/// The hello response: session ID, language, accessibility status, and
/// the tools Companion announces.
package struct BridgeHelloResult: Codable, Sendable, Equatable {
    package var session: String
    package var language: AppLanguage
    package var accessibility: Bool
    package var tools: [BridgeToolSpec]

    package init(session: String, language: AppLanguage, accessibility: Bool, tools: [BridgeToolSpec]) {
        self.session = session
        self.language = language
        self.accessibility = accessibility
        self.tools = tools
    }
}

/// The result of a tool call: success flag, output, target app name, and
/// the tool that produced it. The card (UI state) is dropped here because
/// the shim has no canvas to paint it on.
package struct BridgeCallResult: Codable, Sendable, Equatable {
    package var ok: Bool
    package var output: String
    package var target: String
    package var tool: String?

    /// The only way a tool outcome becomes a bridge reply, so the screen
    /// text is cleaned here once for every call path.
    package init(_ outcome: ParentToolOutcome) {
        self.ok = outcome.ok
        self.output = BridgeScreenText.strip(outcome.output)
        self.target = BridgeScreenText.strip(outcome.target)
        self.tool = outcome.tool
    }

    package init(ok: Bool, output: String, target: String, tool: String? = nil) {
        self.ok = ok
        self.output = output
        self.target = target
        self.tool = tool
    }
}

/// The shape of an error response on the wire.
package struct BridgeErrorBody: Error, Codable, Sendable, Equatable {
    package var code: String
    package var message: String

    package init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

/// Outbound messages: success or error, correlated by id. The bye response
/// has no data.
package enum BridgeResponse: Sendable, Equatable {
    case hello(id: Int, BridgeHelloResult)
    case call(id: Int, BridgeCallResult)
    case bye(id: Int)
    case error(id: Int?, BridgeErrorBody)
}

// MARK: - Error Codes

/// Stable error codes the model recovers by. All listed in spec §3c.
package enum BridgeCode {
    package static let badToken = "bad_token"
    package static let noSession = "no_session"
    package static let sessionClosed = "session_closed"
    package static let busy = "busy"
    /// The user is in a voice turn: the hands come back on their own when it
    /// ends, unlike `busy`, which means someone else holds them.
    package static let paused = "paused"
    package static let rateLimited = "rate_limited"
    /// Too many denied approvals in a row: the caller is refused without a
    /// sheet until the window passes (Wave 20c D5).
    package static let coolingDown = "cooling_down"
    package static let unknownTool = "unknown_tool"
    package static let invalidArgs = "invalid_args"
    package static let targetChanged = "target_changed"
    package static let staleId = "stale_id"
    package static let secureField = "secure_field"
    package static let deniedByUser = "denied_by_user"
    package static let approvalTimeout = "approval_timeout"
    package static let notAvailable = "not_available"
    /// Wave 18: no browser extension is attached, or it went away mid-call.
    package static let notConnected = "not_connected"
    /// Wave 18b: the tab exists but this caller does not control it.
    package static let notControlled = "not_controlled"
    /// Wave 18: the extension did not answer within the call's deadline.
    package static let timeout = "timeout"
    /// A scoped browser_read whose selector matched nothing, or only hidden
    /// nodes: an empty page would read as "the menu is empty".
    package static let selectorNoMatch = "selector_no_match"
    package static let selectorHidden = "selector_hidden"
    // The extension's reasons, kept apart so each gets its own next step.
    package static let debuggerRevoked = "debugger_revoked"
    package static let debuggerUnavailable = "debugger_unavailable"
    package static let unreadablePage = "unreadable_page"
    package static let notTypable = "not_typable"
    /// P4: the element would not take the keyboard focus, so the key was not sent.
    package static let notFocused = "not_focused"
    /// The tool exists but Companion's own window is in front, so there is no
    /// other app to act on: the model can fix it, unlike `unknown_tool`.
    package static let selfInFront = "self_in_front"
    package static let needsAccessibility = "needs_accessibility"
    /// `see` needs pixels, and Screen Recording is what grants them.
    package static let screenRecordingRequired = "screen_recording_required"
    /// The session is locked: nothing on screen can be read or acted on, and
    /// an action caught by the lock has an outcome nobody saw.
    package static let screenLocked = "screen_locked"
    /// The window was raised but another app had the front right after.
    package static let foregroundUnavailable = "foreground_unavailable"
    /// Any privacy permission other than Accessibility or Screen Recording,
    /// Automation first: Incredible's one code, with the exact pane in words.
    package static let permissionRequired = "permission_required"
    // Framing errors
    package static let unknownMethod = "unknown_method"
    package static let badFrame = "bad_frame"
    package static let frameTooLarge = "frame_too_large"
    /// A repeated request id whose first answer was too big to keep.
    package static let replyTooLarge = "reply_too_large"
}

// MARK: - Codec

/// Encoder and decoder for the JSON Lines protocol. One line per message,
/// no trailing newline (the transport adds it).
package enum BridgeCodec {
    package static let maxLineBytes = 65_536

    /// Decode a line into a request or an error. The id is preserved when
    /// parseable so the shim can correlate responses.
    package static func decode(line: String) -> Result<BridgeRequest, BridgeErrorBody> {
        let bytes = line.utf8.count
        guard bytes <= maxLineBytes else {
            return .failure(BridgeErrorBody(code: BridgeCode.frameTooLarge,
                                             message: "Line exceeds \(maxLineBytes) bytes"))
        }

        guard let data = line.data(using: .utf8) else {
            return .failure(BridgeErrorBody(code: BridgeCode.badFrame,
                                             message: "Invalid JSON"))
        }

        let envelope: [String: Any]?
        do {
            envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return .failure(BridgeErrorBody(code: BridgeCode.badFrame,
                                             message: "Invalid JSON"))
        }

        guard let envelope = envelope else {
            return .failure(BridgeErrorBody(code: BridgeCode.badFrame,
                                             message: "Invalid JSON"))
        }

        guard let id = envelope["id"] as? Int else {
            return .failure(BridgeErrorBody(code: BridgeCode.badFrame,
                                             message: "Missing or invalid id"))
        }

        guard let methodStr = envelope["method"] as? String,
              let method = BridgeMethod(rawValue: methodStr)
        else {
            return .failure(BridgeErrorBody(code: BridgeCode.unknownMethod,
                                             message: "Unknown method: \(envelope["method"] ?? "nil")"))
        }

        let params = envelope["params"] as? [String: Any] ?? [:]

        do {
            switch method {
            case .hello:
                guard let token = params["token"] as? String,
                      let client = params["client"] as? String
                else {
                    return .failure(BridgeErrorBody(code: BridgeCode.badFrame,
                                                     message: "Invalid hello params"))
                }
                let protocolVersion = (params["protocol"] as? Int) ?? 1
                let hello = BridgeHello(token: token, client: client, protocolVersion: protocolVersion)
                let request: BridgeRequest = .hello(id: id, hello)
                return .success(request)

            case .call:
                guard let name = params["name"] as? String else {
                    return .failure(BridgeErrorBody(code: BridgeCode.badFrame,
                                                     message: "Missing call name"))
                }

                let argumentsJSON: String
                if let arguments = params["arguments"] {
                    if let argsDict = arguments as? [String: Any] {
                        // Object: compact encode it back to a string
                        let argsData = try JSONSerialization.data(withJSONObject: argsDict,
                                                                   options: [.sortedKeys])
                        argumentsJSON = String(data: argsData, encoding: .utf8) ?? "{}"
                    } else {
                        // Non-object: error
                        return .failure(BridgeErrorBody(code: BridgeCode.invalidArgs,
                                                         message: "arguments must be an object"))
                    }
                } else {
                    // Absent: empty object
                    argumentsJSON = "{}"
                }

                let call = BridgeCall(name: name, argumentsJSON: argumentsJSON)
                let request: BridgeRequest = .call(id: id, call)
                return .success(request)

            case .bye:
                let request: BridgeRequest = .bye(id: id)
                return .success(request)
            }
        } catch {
            return .failure(BridgeErrorBody(code: BridgeCode.badFrame,
                                             message: error.localizedDescription))
        }
    }

    /// Encode a response to a single line (no trailing newline).
    package static func encode(_ response: BridgeResponse) -> String {
        let envelope: [String: Any]

        switch response {
        case .hello(let id, let result):
            do {
                let resultData = try JSONEncoder().encode(result)
                if let resultDict = try JSONSerialization.jsonObject(with: resultData) as? [String: Any] {
                    envelope = ["id": id, "result": resultDict]
                } else {
                    envelope = ["id": id, "error": ["code": BridgeCode.badFrame, "message": "Failed to encode hello result"]]
                }
            } catch {
                envelope = ["id": id, "error": ["code": BridgeCode.badFrame, "message": error.localizedDescription]]
            }

        case .call(let id, let result):
            do {
                let resultData = try JSONEncoder().encode(result)
                if let resultDict = try JSONSerialization.jsonObject(with: resultData) as? [String: Any] {
                    envelope = ["id": id, "result": resultDict]
                } else {
                    envelope = ["id": id, "error": ["code": BridgeCode.badFrame, "message": "Failed to encode call result"]]
                }
            } catch {
                envelope = ["id": id, "error": ["code": BridgeCode.badFrame, "message": error.localizedDescription]]
            }

        case .bye(let id):
            envelope = ["id": id, "result": [:] as [String: Any]]

        case .error(let id, let error):
            let errorDict: [String: Any] = ["code": error.code, "message": error.message]
            if let id = id {
                envelope = ["id": id, "error": errorDict]
            } else {
                envelope = ["id": NSNull(), "error": errorDict]
            }
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return "{}"
        }
    }
}
