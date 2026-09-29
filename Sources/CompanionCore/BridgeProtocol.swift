import Foundation

/// Wave 17. The wire protocol for the local bridge: a stable JSON-based
/// request-response contract that Companion publishes and the shim consumes.
/// Pure Codable shapes; the actor and socket handling live in Services.

// MARK: - Message Structure

public enum BridgeMethod: String, Codable, Sendable {
    case hello
    case call
    case bye
}

/// First message: the token and protocol version. The shim reads the token
/// from bridge.token (0600 file) and sends it here; if it does not match or
/// the file does not exist, Companion closes without a sheet.
public struct BridgeHello: Codable, Sendable, Equatable {
    public var token: String
    public var client: String
    public var protocolVersion: Int

    public init(token: String, client: String = "claude-code", protocolVersion: Int = 1) {
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
public struct BridgeCall: Sendable, Equatable {
    public var name: String
    public var argumentsJSON: String

    public init(name: String, argumentsJSON: String) {
        self.name = name
        self.argumentsJSON = argumentsJSON
    }
}

/// Inbound messages: hello, call, or bye. The id is stable across the
/// lifetime of a session to let the shim correlate responses.
public enum BridgeRequest: Sendable, Equatable {
    case hello(id: Int, BridgeHello)
    case call(id: Int, BridgeCall)
    case bye(id: Int)
}

// MARK: - Tool Specs

/// A Codable mirror of ToolSpec so the shim can build JSON Schema
/// and register tools from the hello result without duplicating schema logic.
public struct BridgeToolSpec: Codable, Sendable, Equatable {
    public var name: String
    public var description: String
    public var properties: [BridgeToolProperty]
    public var required: [String]

    public init(_ spec: ToolSpec) {
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

public struct BridgeToolProperty: Codable, Sendable, Equatable {
    public var name: String
    public var type: String
    public var description: String

    public init(_ property: ToolProperty) {
        self.name = property.name
        self.type = property.type
        self.description = property.description
    }

    enum CodingKeys: String, CodingKey {
        case name
        case type
        case description
    }
}

// MARK: - Results

/// The hello response: session ID, language, accessibility status, and
/// the tools Companion announces.
public struct BridgeHelloResult: Codable, Sendable, Equatable {
    public var session: String
    public var language: AppLanguage
    public var accessibility: Bool
    public var tools: [BridgeToolSpec]

    public init(session: String, language: AppLanguage, accessibility: Bool, tools: [BridgeToolSpec]) {
        self.session = session
        self.language = language
        self.accessibility = accessibility
        self.tools = tools
    }
}

/// The result of a tool call: success flag, output, target app name, and
/// the tool that produced it. The card (UI state) is dropped here because
/// the shim has no canvas to paint it on.
public struct BridgeCallResult: Codable, Sendable, Equatable {
    public var ok: Bool
    public var output: String
    public var target: String
    public var tool: String?

    public init(_ outcome: ParentToolOutcome) {
        self.ok = outcome.ok
        self.output = outcome.output
        self.target = outcome.target
        self.tool = outcome.tool
    }

    public init(ok: Bool, output: String, target: String, tool: String? = nil) {
        self.ok = ok
        self.output = output
        self.target = target
        self.tool = tool
    }
}

/// The shape of an error response on the wire.
public struct BridgeErrorBody: Error, Codable, Sendable, Equatable {
    public var code: String
    public var message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

/// Outbound messages: success or error, correlated by id. The bye response
/// has no data.
public enum BridgeResponse: Sendable, Equatable {
    case hello(id: Int, BridgeHelloResult)
    case call(id: Int, BridgeCallResult)
    case bye(id: Int)
    case error(id: Int?, BridgeErrorBody)
}

// MARK: - Error Codes

/// Stable error codes the model recovers by. All listed in spec §3c.
public enum BridgeCode {
    public static let badToken = "bad_token"
    public static let noSession = "no_session"
    public static let sessionClosed = "session_closed"
    public static let busy = "busy"
    public static let rateLimited = "rate_limited"
    /// Too many denied approvals in a row: the caller is refused without a
    /// sheet until the window passes (Wave 20c D5).
    public static let coolingDown = "cooling_down"
    public static let unknownTool = "unknown_tool"
    public static let invalidArgs = "invalid_args"
    public static let targetChanged = "target_changed"
    public static let staleId = "stale_id"
    public static let secureField = "secure_field"
    public static let deniedByUser = "denied_by_user"
    public static let approvalTimeout = "approval_timeout"
    public static let notAvailable = "not_available"
    /// The tool exists but Companion's own window is in front, so there is no
    /// other app to act on: the model can fix it, unlike `unknown_tool`.
    public static let selfInFront = "self_in_front"
    public static let needsAccessibility = "needs_accessibility"
    // Framing errors
    public static let unknownMethod = "unknown_method"
    public static let badFrame = "bad_frame"
    public static let frameTooLarge = "frame_too_large"
}

// MARK: - Codec

/// Encoder and decoder for the JSON Lines protocol. One line per message,
/// no trailing newline (the transport adds it).
public enum BridgeCodec {
    public static let maxLineBytes = 65_536

    /// Decode a line into a request or an error. The id is preserved when
    /// parseable so the shim can correlate responses.
    public static func decode(line: String) -> Result<BridgeRequest, BridgeErrorBody> {
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
    public static func encode(_ response: BridgeResponse) -> String {
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
